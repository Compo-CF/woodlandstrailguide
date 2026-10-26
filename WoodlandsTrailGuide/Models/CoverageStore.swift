import Foundation
import CoreLocation
import Observation

/// A moment worth telling the user about, and the one moment they might
/// want to post. Identified by a stable `key` so it is only ever shown once.
struct CoverageMilestone: Identifiable, Hashable {
    let key: String
    let title: String
    let detail: String
    var id: String { key }
}

/// How much of one bucket of the network has been walked.
struct CoverageProgress {
    let name: String
    let coveredMeters: Double
    let totalMeters: Double

    var fraction: Double {
        totalMeters > 0 ? min(max(coveredMeters / totalMeters, 0), 1) : 0
    }
    var coveredMiles: Double { coveredMeters / 1609.344 }
    var totalMiles: Double { totalMeters / 1609.344 }
    var isComplete: Bool { fraction >= 0.999 }
}

/// Which of the pathway network this device has walked.
///
/// Stored as 25 m bins per way rather than a walked/not-walked flag. Way
/// length is wildly skewed — median 75 m, but 46 ways run over a kilometre and
/// the longest is 6.6 km — so "you touched it, you walked it" would credit
/// 6.6 km for stepping on ten metres of one end. Bins make the number mean
/// something, at the cost of a little state.
///
/// Keys are `TrailGraph.Way.id`, which survives a Township data refresh. That
/// matters more here than anywhere else in the app: this is the one feature
/// whose entire value is that it accumulates over months, so an id that
/// reshuffled on refresh would quietly erase it. See
/// `TrailGraph.stableID(for:nodes:)`.
@Observable
final class CoverageStore {

    /// 25 m. Fine enough that the 6.6 km way needs real walking to complete,
    /// coarse enough that the whole network is only ~13,300 bins at 100%.
    static let binMeters: Double = 25

    /// A way counts as walked at 80% of its length. GPS noise at the ends, and
    /// stubs that dead-end at a fence, make 100% unreachable in practice.
    static let completionThreshold: Double = 0.8

    /// Ways at or below this length are excluded from every denominator. There
    /// are six of them, all ~0.1 m artefacts of the Township export; counting
    /// them would make 100% impossible to reach for reasons no user could see.
    static let minimumWayMeters: Double = 0.5

    /// How many fixes must land on a way before any of its bins are kept.
    ///
    /// Walking *past* a junction throws a fix or two onto the crossing path.
    /// The grid's ambiguity rule can't catch it — it deliberately exempts ways
    /// that share a node, or matching would be suppressed at every
    /// intersection in the network — so it has to be caught here instead.
    ///
    /// Three is measured, not guessed. Over 25 simulated 2.5 km walks with 5 m
    /// GPS noise: at one fix, 18 ways were credited that were never walked; at
    /// three, 12, and only one of those ever reached the completion threshold,
    /// the rest keeping a stray bin or two. The cost is two genuinely-walked
    /// ways out of 148, with credited distance unchanged at 98% of truth.
    static let confirmingFixes: Int = 3

    /// Covered bin indices per stable way id.
    private(set) var bins: [String: Set<UInt16>] = [:]

    /// Bumped on every change, for cheap invalidation of the map overlay —
    /// rebuilding 1,564 polylines per GPS fix is not viable.
    private(set) var revision: Int = 0

    private var grid: CoverageGrid?
    private var graph: TrailGraph?

    /// The way the previous fix matched. Walks are continuous, so this is the
    /// strongest available hint for resolving parallel paths.
    private var lastMatchedWay: Int?
    /// Bin of the previous fix, to fill the gap between sparse fixes.
    private var lastBin: Int?

    /// Fixes seen per way during this walk, and the bins they produced, held
    /// back until `confirmingFixes` is reached. Both are per-walk: a way
    /// brushed once today and once next week is two separate brushes, not a
    /// walk, so these are cleared by `resetTrace()` rather than persisted.
    private var sessionHits: [Int: Int] = [:]
    private var pendingBins: [Int: Set<UInt16>] = [:]

    /// Ways of the active route, if any.
    ///
    /// Held here rather than passed per fix because recording outlives the
    /// map: a walk continues while the user is reading the About tab or has
    /// the screen off, and the view that knows the route is not involved in
    /// those moments. MapTabView sets this when the route changes.
    var routeHint: Set<Int> = []

    private var isDirty = false

    private static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask)[0]
        return documents.appendingPathComponent("coverage.json")
    }

    init() {
        load()
    }

    // MARK: - Graph

    /// Attach the graph and build the spatial index. Safe to call again when a
    /// refresh swaps the graph in.
    func attach(graph: TrailGraph) {
        if let existing = self.graph,
           existing.version == graph.version,
           existing.ways.count == graph.ways.count,
           self.grid != nil {
            return
        }
        self.graph = graph
        self.grid = CoverageGrid(graph: graph)
        resetTrace()
    }

    /// Forget where the last fix was. Call when a walk ends or is interrupted,
    /// so the continuity hint doesn't carry across a gap — somebody who drives
    /// across town and starts again is not still on the way they finished on.
    func resetTrace() {
        lastMatchedWay = nil
        lastBin = nil
        sessionHits = [:]
        pendingBins = [:]
    }

    // MARK: - Recording

    /// Record a fix. Returns the way credited, or nil if nothing was.
    ///
    /// `routeWays` is the set of ways on the active route, if navigating —
    /// passed to the grid as a disambiguation hint.
    @discardableResult
    func record(_ location: CLLocation, routeWays: Set<Int>? = nil) -> Int? {
        guard let grid, let graph else { return nil }

        var preferred = routeWays ?? routeHint
        if let lastMatchedWay { preferred.insert(lastMatchedWay) }

        guard let match = grid.match(location, preferring: preferred) else {
            // Deliberately does NOT reset the trace. A single bad fix mid-walk
            // is normal; dropping the continuity hint for it would make the
            // next fix more ambiguous, not less.
            return nil
        }

        let wayIndex = match.wayIndex
        guard graph.ways.indices.contains(wayIndex) else { return nil }
        let way = graph.ways[wayIndex]
        let length = grid.wayLengths[wayIndex]
        guard length > Self.minimumWayMeters else { return nil }

        let bin = Self.binIndex(forMeters: match.metersAlongWay, wayLength: length)
        var newBins: Set<UInt16> = [bin]

        // Fill the gap to the previous fix on the same way. A 3 m distance
        // filter at jogging pace still skips bins, and a comb of covered and
        // uncovered 25 m stripes along one path is both wrong and ugly.
        if wayIndex == lastMatchedWay, let lastBin {
            let from = min(Int(bin), lastBin)
            let to = max(Int(bin), lastBin)
            // Only bridge a plausible gap. A large jump means signal loss or a
            // drive, not walking, and filling it would invent coverage.
            if to - from <= 8 {
                for b in from...to { newBins.insert(UInt16(b)) }
            }
        }

        lastMatchedWay = wayIndex
        lastBin = Int(bin)

        // Hold bins back until this way has been seen enough times to be a
        // walk rather than a brush past a junction. Once confirmed, the
        // pending set is flushed and subsequent fixes commit immediately.
        sessionHits[wayIndex, default: 0] += 1
        pendingBins[wayIndex, default: []].formUnion(newBins)
        guard sessionHits[wayIndex, default: 0] >= Self.confirmingFixes else {
            return nil
        }

        let confirmed = pendingBins.removeValue(forKey: wayIndex) ?? newBins
        let before = bins[way.id]?.count ?? 0
        bins[way.id, default: []].formUnion(confirmed)
        let after = bins[way.id]?.count ?? 0

        if after != before {
            revision += 1
            isDirty = true
        }
        return wayIndex
    }

    static func binIndex(forMeters meters: Double, wayLength: Double) -> UInt16 {
        let clamped = min(max(meters, 0), max(wayLength - 0.001, 0))
        let index = Int((clamped / binMeters).rounded(.down))
        return UInt16(min(max(index, 0), Int(UInt16.max)))
    }

    static func binCount(forLength length: Double) -> Int {
        max(1, Int((length / binMeters).rounded(.up)))
    }

    // MARK: - Reading

    func coveredMeters(forWayAt index: Int) -> Double {
        guard let graph, graph.ways.indices.contains(index) else { return 0 }
        return coveredMeters(for: graph.ways[index])
    }

    func coveredMeters(for way: TrailGraph.Way) -> Double {
        guard let count = bins[way.id]?.count, count > 0 else { return 0 }
        return min(Double(count) * Self.binMeters, way.lengthMeters)
    }

    func isComplete(_ way: TrailGraph.Way) -> Bool {
        guard way.lengthMeters > Self.minimumWayMeters else { return false }
        return coveredMeters(for: way) >= way.lengthMeters * Self.completionThreshold
    }

    func hasAnyCoverage(_ way: TrailGraph.Way) -> Bool {
        bins[way.id]?.isEmpty == false
    }

    /// Covered bins for a way, for drawing partial coverage on the map.
    func bins(for way: TrailGraph.Way) -> Set<UInt16> {
        bins[way.id] ?? []
    }

    /// Geometry of the walked parts of a way, as one coordinate run per
    /// contiguous stretch of covered bins.
    ///
    /// Per-bin rather than per-way on purpose. Forty-six ways run over a
    /// kilometre and the longest is 6.6 km; colouring them all-or-nothing
    /// would leave the longest paths looking untouched for most of the walk
    /// along them, which is both wrong and the opposite of encouraging.
    ///
    /// Returns nothing for an uncovered way, so callers can skip cheaply.
    func coveredRuns(for way: TrailGraph.Way,
                     graph: TrailGraph) -> [[CLLocationCoordinate2D]] {
        guard let covered = bins[way.id], !covered.isEmpty,
              way.nodeIndices.count >= 2,
              way.lengthMeters > Self.minimumWayMeters else { return [] }

        // Contiguous bins become one run, so a fully walked way is a single
        // polyline rather than dozens of 25 m stubs butted together.
        let sorted = covered.sorted()
        var ranges: [(start: Double, end: Double)] = []
        var runStart = Int(sorted[0])
        var runEnd = runStart
        for bin in sorted.dropFirst() {
            if Int(bin) == runEnd + 1 {
                runEnd = Int(bin)
            } else {
                ranges.append((Double(runStart) * Self.binMeters,
                               Double(runEnd + 1) * Self.binMeters))
                runStart = Int(bin)
                runEnd = runStart
            }
        }
        ranges.append((Double(runStart) * Self.binMeters,
                       Double(runEnd + 1) * Self.binMeters))

        return ranges.compactMap { range in
            let slice = Self.slice(way: way, graph: graph,
                                   from: range.start,
                                   to: min(range.end, way.lengthMeters))
            return slice.count >= 2 ? slice : nil
        }
    }

    /// The part of a way between two distances along it, interpolating at
    /// both ends so a run starts and stops exactly where the bins do rather
    /// than snapping to the nearest node.
    private static func slice(way: TrailGraph.Way,
                              graph: TrailGraph,
                              from startMeters: Double,
                              to endMeters: Double) -> [CLLocationCoordinate2D] {
        guard endMeters > startMeters else { return [] }
        var out: [CLLocationCoordinate2D] = []
        var travelled: Double = 0

        for i in 0..<(way.nodeIndices.count - 1) {
            let aIndex = way.nodeIndices[i]
            let bIndex = way.nodeIndices[i + 1]
            guard graph.nodes.indices.contains(aIndex),
                  graph.nodes.indices.contains(bIndex) else { continue }
            let a = graph.nodes[aIndex].clCoord
            let b = graph.nodes[bIndex].clCoord

            let segmentLength = Self.distance(a, b)
            let segmentStart = travelled
            let segmentEnd = travelled + segmentLength
            travelled = segmentEnd
            guard segmentLength > 0 else { continue }

            // Skip segments entirely outside the requested span.
            if segmentEnd <= startMeters || segmentStart >= endMeters { continue }

            let enterT = max(0, (startMeters - segmentStart) / segmentLength)
            let exitT = min(1, (endMeters - segmentStart) / segmentLength)
            if out.isEmpty {
                out.append(Self.interpolate(a, b, enterT))
            }
            out.append(Self.interpolate(a, b, exitT))
        }
        return out
    }

    private static func interpolate(_ a: CLLocationCoordinate2D,
                                    _ b: CLLocationCoordinate2D,
                                    _ t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    private static func distance(_ a: CLLocationCoordinate2D,
                                 _ b: CLLocationCoordinate2D) -> Double {
        let midLat = (a.latitude + b.latitude) / 2
        let mPerLon = 111_319.0 * cos(midLat * .pi / 180)
        let dx = (b.longitude - a.longitude) * mPerLon
        let dy = (b.latitude - a.latitude) * 111_319.0
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Progress for every village, plus one bucket for the natural-surface
    /// trails (which carry no village), biggest first.
    ///
    /// Deduplicated by stable id, because the Township publishes eight ways
    /// twice — once plainly and once suffixed "TEMPORARILY CLOSED". Summing
    /// raw way lengths would put 684 m of Beaver Pond Loop into the
    /// denominator twice and make the total unreachable.
    func progressByVillage() -> [CoverageProgress] {
        guard let graph else { return [] }

        var totals: [String: Double] = [:]
        var covered: [String: Double] = [:]
        var seen: Set<String> = []

        for way in graph.ways {
            guard way.lengthMeters > Self.minimumWayMeters else { continue }
            guard seen.insert(way.id).inserted else { continue }
            let bucket = way.village ?? "Parks & Preserves"
            totals[bucket, default: 0] += way.lengthMeters
            covered[bucket, default: 0] += coveredMeters(for: way)
        }

        return totals.map { name, total in
            CoverageProgress(name: name,
                             coveredMeters: covered[name] ?? 0,
                             totalMeters: total)
        }
        .sorted { $0.totalMeters > $1.totalMeters }
    }

    // MARK: - Milestones

    /// Milestones already shown, so none is celebrated twice.
    private(set) var celebratedMilestones: Set<String> = []

    /// The most significant milestone reached but not yet celebrated.
    ///
    /// Overall progress every 10%, and each village at halfway and done.
    ///
    /// The scope said "first village finished". On its own that is close to
    /// unreachable: a village is 100+ ways, some of them stubs that dead-end
    /// at a fence, and 0.999 of all of them is not a goal anyone will hit.
    /// Halfway is a real milestone somebody reaches in a season, and without
    /// it village-level progress would never say anything at all.
    func pendingMilestone() -> CoverageMilestone? {
        let overall = overallProgress()
        guard overall.coveredMeters > 0 else { return nil }

        // Biggest first: finishing a village on the same walk that crosses
        // 30% should announce the village, not the decade.
        for village in progressByVillage() where village.isComplete {
            let key = "village-done-\(village.name)"
            if !celebratedMilestones.contains(key) {
                return CoverageMilestone(key: key,
                                         title: "\(village.name) complete",
                                         detail: "You've walked all of it.")
            }
        }
        for village in progressByVillage() where village.fraction >= 0.5 {
            let key = "village-half-\(village.name)"
            if !celebratedMilestones.contains(key) {
                return CoverageMilestone(key: key,
                                         title: "Halfway through \(village.name)",
                                         detail: String(format: "%.1f of %.1f miles.",
                                                        village.coveredMiles,
                                                        village.totalMiles))
            }
        }
        let decade = Int(overall.fraction * 10) * 10
        if decade >= 10 {
            let key = "overall-\(decade)"
            if !celebratedMilestones.contains(key) {
                return CoverageMilestone(key: key,
                                         title: "\(decade)% of The Woodlands",
                                         detail: String(format: "%.1f miles walked.",
                                                        overall.coveredMiles))
            }
        }
        return nil
    }

    func markCelebrated(_ milestone: CoverageMilestone) {
        guard celebratedMilestones.insert(milestone.key).inserted else { return }
        isDirty = true
        saveIfNeeded()
    }

    /// Progress across the whole network.
    func overallProgress() -> CoverageProgress {
        let parts = progressByVillage()
        return CoverageProgress(
            name: "The Woodlands",
            coveredMeters: parts.reduce(0) { $0 + $1.coveredMeters },
            totalMeters: parts.reduce(0) { $0 + $1.totalMeters }
        )
    }

    // MARK: - Persistence

    private struct Payload: Codable {
        var version: Int
        var bins: [String: [UInt16]]
        /// Optional so a file written before milestones existed still
        /// decodes. A user who had already walked half of Panther Creek
        /// should not have the app refuse to open their coverage.
        var celebrated: [String]?
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }
        bins = payload.bins.mapValues(Set.init)
        celebratedMilestones = Set(payload.celebrated ?? [])
        revision += 1
    }

    /// Write if anything changed. Cheap enough to call on a timer during a
    /// walk and on backgrounding; a no-op when nothing moved.
    func saveIfNeeded() {
        guard isDirty else { return }
        let payload = Payload(version: 1,
                              bins: bins.mapValues { Array($0).sorted() },
                              celebrated: celebratedMilestones.sorted())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try data.write(to: Self.fileURL, options: .atomic)
            isDirty = false
        } catch {
            // Leave isDirty set so the next attempt retries. Losing a walk's
            // coverage is a far smaller failure than interrupting the walk to
            // report it, and there is nothing useful the user could do.
        }
    }

    /// Erase everything. Only from an explicit, confirmed user action — this
    /// is months of someone's walking.
    func reset() {
        bins = [:]
        celebratedMilestones = []
        resetTrace()
        revision += 1
        isDirty = true
        saveIfNeeded()
    }
}
