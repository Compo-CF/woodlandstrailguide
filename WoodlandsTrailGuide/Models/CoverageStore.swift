import Foundation
import CoreLocation
import Observation

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
    func record(_ location: CLLocation, routeWays: Set<Int> = []) -> Int? {
        guard let grid, let graph else { return nil }

        var preferred = routeWays
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
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }
        bins = payload.bins.mapValues(Set.init)
        revision += 1
    }

    /// Write if anything changed. Cheap enough to call on a timer during a
    /// walk and on backgrounding; a no-op when nothing moved.
    func saveIfNeeded() {
        guard isDirty else { return }
        let payload = Payload(version: 1, bins: bins.mapValues { Array($0).sorted() })
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
        resetTrace()
        revision += 1
        isDirty = true
        saveIfNeeded()
    }
}
