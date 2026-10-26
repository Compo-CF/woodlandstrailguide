import Foundation
import CoreLocation

/// Where a GPS fix landed on the pathway network.
struct CoverageMatch {
    /// Index into `TrailGraph.ways`.
    let wayIndex: Int
    /// Distance from the start of that way, in metres, to the projected point.
    let metersAlongWay: Double
    /// Perpendicular distance from the fix to the way, in metres.
    let distanceMeters: Double
}

/// Spatial index over the pathway network, for answering "which way is this
/// GPS fix on?" cheaply enough to run on every location update.
///
/// `Router.nearestNode` is a linear scan over 44,490 nodes. That is fine for a
/// one-shot "route from here", but a walk produces a fix every few metres and
/// coverage needs a *way* plus a distance along it, not a nearest node. This
/// buckets all 45,882 segments into 60 m cells once at load and queries the
/// 3x3 block around a fix.
///
/// Built once per graph and held by `CoverageStore`. Construction is the
/// expensive part (~46k segments); keep it off the first frame.
final class CoverageGrid {

    /// 60 m. Comfortably wider than the match radius (~12-20 m), so the 3x3
    /// block around a fix always contains every candidate.
    private static let cellSize: Double = 60

    /// Metres per degree of latitude. Longitude is scaled by cos(latitude);
    /// over one suburb a fixed scale at the network's mid-latitude is exact
    /// enough — the error across The Woodlands' ~15 km north-south span is
    /// well under a metre, far below GPS noise.
    private static let metersPerLatDegree: Double = 111_319.0

    private struct Segment {
        let wayIndex: Int
        let aLat, aLon, bLat, bLon: Double
        /// Metres from the start of the way to this segment's first node.
        let metersBefore: Double
        let length: Double
    }

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    private let segments: [Segment]
    private let cells: [Cell: [Int]]
    private let metersPerLonDegree: Double

    /// Node indices per way, for the junction test in `match`. Two ways that
    /// share a node meet at a junction; they are not competing parallel paths,
    /// and treating them as ambiguous would suppress matching at every
    /// intersection in the network.
    private let wayNodes: [Set<Int>]

    /// Length of each way in metres, taken from the graph rather than
    /// recomputed, so coverage percentages agree with every other distance
    /// the app displays.
    let wayLengths: [Double]

    init(graph: TrailGraph) {
        let midLat = (graph.bbox.south + graph.bbox.north) / 2
        let mPerLon = Self.metersPerLatDegree * cos(midLat * .pi / 180)
        self.metersPerLonDegree = mPerLon

        var segments: [Segment] = []
        segments.reserveCapacity(graph.nodes.count)
        var wayNodes: [Set<Int>] = []
        wayNodes.reserveCapacity(graph.ways.count)
        var wayLengths: [Double] = []
        wayLengths.reserveCapacity(graph.ways.count)

        for (wayIndex, way) in graph.ways.enumerated() {
            wayNodes.append(Set(way.nodeIndices))
            wayLengths.append(way.lengthMeters)

            guard way.nodeIndices.count >= 2 else { continue }
            var running: Double = 0
            for offset in 0..<(way.nodeIndices.count - 1) {
                let i = way.nodeIndices[offset]
                let j = way.nodeIndices[offset + 1]
                guard graph.nodes.indices.contains(i),
                      graph.nodes.indices.contains(j) else { continue }
                let a = graph.nodes[i]
                let b = graph.nodes[j]
                let dx = (b.longitude - a.longitude) * mPerLon
                let dy = (b.latitude - a.latitude) * Self.metersPerLatDegree
                let length = (dx * dx + dy * dy).squareRoot()
                segments.append(Segment(
                    wayIndex: wayIndex,
                    aLat: a.latitude, aLon: a.longitude,
                    bLat: b.latitude, bLon: b.longitude,
                    metersBefore: running,
                    length: length
                ))
                running += length
            }
        }
        self.segments = segments
        self.wayNodes = wayNodes
        self.wayLengths = wayLengths

        // Index by bounding box, not by endpoints. The median segment is 5 m
        // and would sit in one cell either way, but 115 segments exceed 60 m
        // (the longest is 232 m) and endpoint-only indexing would leave their
        // middles unreachable — a fix there would match nothing at all.
        var cells: [Cell: [Int]] = [:]
        cells.reserveCapacity(segments.count)
        for (index, segment) in segments.enumerated() {
            let x0 = Self.cellIndex(segment.aLon * mPerLon)
            let x1 = Self.cellIndex(segment.bLon * mPerLon)
            let y0 = Self.cellIndex(segment.aLat * Self.metersPerLatDegree)
            let y1 = Self.cellIndex(segment.bLat * Self.metersPerLatDegree)
            for x in min(x0, x1)...max(x0, x1) {
                for y in min(y0, y1)...max(y0, y1) {
                    cells[Cell(x: x, y: y), default: []].append(index)
                }
            }
        }
        self.cells = cells
    }

    private static func cellIndex(_ meters: Double) -> Int {
        Int((meters / cellSize).rounded(.down))
    }

    /// Every way within `radius` of the coordinate, nearest first, at most one
    /// entry per way (its closest point).
    func candidates(near coord: CLLocationCoordinate2D,
                    radius: Double) -> [CoverageMatch] {
        let cx = Self.cellIndex(coord.longitude * metersPerLonDegree)
        let cy = Self.cellIndex(coord.latitude * Self.metersPerLatDegree)

        var best: [Int: CoverageMatch] = [:]
        for dx in -1...1 {
            for dy in -1...1 {
                guard let bucket = cells[Cell(x: cx + dx, y: cy + dy)] else { continue }
                for index in bucket {
                    let segment = segments[index]
                    let (distance, t) = Router.projectionDistance(
                        lat: coord.latitude, lon: coord.longitude,
                        aLat: segment.aLat, aLon: segment.aLon,
                        bLat: segment.bLat, bLon: segment.bLon
                    )
                    guard distance <= radius else { continue }
                    if let existing = best[segment.wayIndex],
                       existing.distanceMeters <= distance {
                        continue
                    }
                    best[segment.wayIndex] = CoverageMatch(
                        wayIndex: segment.wayIndex,
                        metersAlongWay: segment.metersBefore + t * segment.length,
                        distanceMeters: distance
                    )
                }
            }
        }
        return best.values.sorted { $0.distanceMeters < $1.distanceMeters }
    }

    /// The way a fix should be credited to, or nil when the answer is not
    /// clear enough to record.
    ///
    /// Three refusals, in the order they fire:
    ///
    /// 1. **Inaccurate fix.** Anything worse than `maxAccuracy` is discarded
    ///    outright; a 60 m fix can sit convincingly on the wrong street.
    /// 2. **Nothing near.** Walking the road rather than the pathway should
    ///    credit nothing.
    /// 3. **Ambiguity.** If the nearest way is not nearer than the next
    ///    *unconnected* way by `ambiguityMargin`, record nothing. Measured
    ///    over the real network only ~2% of it has an unconnected way within
    ///    10 m, so this costs very little — and crediting the pathway on the
    ///    far side of a boulevard is worse than leaving a gap that the next
    ///    walk will fill.
    ///
    /// `preferring` resolves most of that remaining 2%: during navigation pass
    /// the ways on the active route, and while free-recording pass the way the
    /// previous fix matched. Walks are continuous, so the way you were just on
    /// is overwhelmingly the way you are still on.
    func match(_ location: CLLocation,
               maxAccuracy: Double = 20,
               ambiguityMargin: Double = 1.5,
               preferring preferred: Set<Int> = []) -> CoverageMatch? {
        let accuracy = location.horizontalAccuracy
        guard accuracy >= 0, accuracy <= maxAccuracy else { return nil }

        let radius = max(12, accuracy)
        let found = candidates(near: location.coordinate, radius: radius)
        guard let nearest = found.first else { return nil }

        if let hinted = found.first(where: { preferred.contains($0.wayIndex) }) {
            return hinted
        }

        let rival = found.dropFirst().first { other in
            wayNodes[nearest.wayIndex].isDisjoint(with: wayNodes[other.wayIndex])
        }
        if let rival {
            // A fix sitting essentially on top of one way is unambiguous
            // however close the rival is, so compare against a floor rather
            // than scaling from zero.
            let margin = max(nearest.distanceMeters, 1) * ambiguityMargin
            guard rival.distanceMeters > margin else { return nil }
        }
        return nearest
    }
}
