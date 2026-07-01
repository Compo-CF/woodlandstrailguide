import Foundation
import CoreLocation

/// Client-side shortest-path routing over the TrailGraph.
///
/// The Woodlands pathway network has ~1,500 segments and ~10K nodes — tiny
/// for a binary-heap Dijkstra. A query from any node to any other returns in
/// single-digit milliseconds, well under one map-tap latency.
///
/// Usage:
///     let r = Router(graph: graph)
///     guard let route = r.route(from: nodeA, to: nodeB) else { return }
///     // route.nodes / route.lengthMeters / route.namedSegments
struct Router {
    let graph: TrailGraph

    struct Route {
        /// Ordered node indices from start to end.
        let nodes: [Int]
        /// Total route length in meters.
        let lengthMeters: Double
        /// Human-readable segments along the route: each is a (name, length)
        /// run of consecutive edges that share the same trail/pathway name.
        let namedSegments: [(name: String, lengthMeters: Double)]
        /// Unique named parks the route passes through, in first-encountered
        /// order. Sourced from each way's `parks` field (precomputed by
        /// link_trails_to_parks.py).
        let parks: [String]
        /// One instruction per named-segment leg: "Head out on Sawmill Path
        /// for 0.3 mi", "Turn right onto Cypress Trace for 0.1 mi", …
        /// "Arrive at destination." Anchored to nodes in `nodes`; consumed
        /// by MapTabView's navigation banner.
        let turnInstructions: [TurnInstruction]
    }

    struct TurnInstruction: Hashable {
        enum Kind: String, Hashable {
            case start
            case continueStraight
            case slightLeft
            case left
            case sharpLeft
            case slightRight
            case right
            case sharpRight
            case uTurn
            case arrive

            var icon: String {
                switch self {
                case .start:             return "figure.walk.circle.fill"
                case .continueStraight:  return "arrow.up"
                case .slightLeft:        return "arrow.up.left"
                case .left:              return "arrow.turn.up.left"
                case .sharpLeft:         return "arrow.down.left"
                case .slightRight:       return "arrow.up.right"
                case .right:             return "arrow.turn.up.right"
                case .sharpRight:        return "arrow.down.right"
                case .uTurn:             return "arrow.uturn.up"
                case .arrive:            return "mappin.and.ellipse"
                }
            }

            var verb: String {
                switch self {
                case .start:             return "Head out"
                case .continueStraight:  return "Continue"
                case .slightLeft:        return "Bear left"
                case .left:              return "Turn left"
                case .sharpLeft:         return "Sharp left"
                case .slightRight:       return "Bear right"
                case .right:             return "Turn right"
                case .sharpRight:        return "Sharp right"
                case .uTurn:             return "Make a U-turn"
                case .arrive:            return "Arrive"
                }
            }
        }

        let kind: Kind
        /// Name of the leg this instruction takes you onto. Nil for the arrive
        /// instruction (which has no street to be "on").
        let streetName: String?
        /// Length in meters of the leg this instruction describes. For an
        /// `arrive` instruction this is 0.
        let legMeters: Double
        /// Cumulative meters from the route start to where this instruction
        /// fires. Used to find the "current" instruction given the user's
        /// projected progress.
        let cumulativeMeters: Double
        /// Index into Route.nodes where this instruction is anchored.
        let nodeIndex: Int
    }

    /// Find the nearest node in the graph to an arbitrary point. Linear scan —
    /// fine at the current graph size; swap in a k-d tree if the graph grows.
    func nearestNode(to coord: CLLocationCoordinate2D) -> Int? {
        guard !graph.nodes.isEmpty else { return nil }
        var bestIdx = 0
        var bestDist = Double.infinity
        for (i, n) in graph.nodes.enumerated() {
            let dLat = n.latitude - coord.latitude
            let dLon = n.longitude - coord.longitude
            // Squared planar distance is fine for "find the closest" — we
            // don't need true geodesic distance for this ranking, just a
            // monotonic proxy that's cheap to compute.
            let d = dLat * dLat + dLon * dLon
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        return bestIdx
    }

    /// Dijkstra from `start` to `end`, minimizing total meters traversed.
    /// Returns nil if no path exists.
    func route(from start: Int, to end: Int) -> Route? {
        route(through: [start, end])
    }

    /// Route through an ordered sequence of stops — [start, waypoint₁,
    /// waypoint₂, …, end]. Each adjacent pair is computed with an
    /// independent Dijkstra run and stitched together. Turn instructions,
    /// named segments, and park listings are rebuilt over the combined
    /// path so the summary reads as one continuous route.
    ///
    /// Callers can also use this to produce loops (same start and end with
    /// a distant waypoint in between).
    func route(through stops: [Int]) -> Route? {
        guard stops.count >= 2 else {
            if stops.count == 1 {
                return Route(nodes: [stops[0]], lengthMeters: 0,
                             namedSegments: [], parks: [], turnInstructions: [])
            }
            return nil
        }
        var combinedPath: [Int] = []
        var combinedEdgeWays: [Int] = []
        var totalMeters = 0.0
        for i in 0..<(stops.count - 1) {
            guard let segment = _pathFrom(stops[i], to: stops[i + 1]) else {
                return nil
            }
            if combinedPath.isEmpty {
                combinedPath = segment.path
            } else if let last = combinedPath.last, last == segment.path.first {
                // Adjacent segments share the seam node; drop the duplicate.
                combinedPath.append(contentsOf: segment.path.dropFirst())
            } else {
                combinedPath.append(contentsOf: segment.path)
            }
            combinedEdgeWays.append(contentsOf: segment.edgeWays)
            totalMeters += segment.lengthMeters
        }
        return Route(
            nodes: combinedPath,
            lengthMeters: totalMeters,
            namedSegments: collapseSegments(edgeWays: combinedEdgeWays, path: combinedPath),
            parks: uniqueParks(edgeWays: combinedEdgeWays),
            turnInstructions: buildTurnInstructions(edgeWays: combinedEdgeWays, path: combinedPath)
        )
    }

    /// The raw Dijkstra + reconstruction primitive shared by route(from:to:)
    /// and route(through:). Returns nil on unreachable, empty edges for a
    /// zero-length trip (start == end).
    private func _pathFrom(_ start: Int, to end: Int)
        -> (path: [Int], edgeWays: [Int], lengthMeters: Double)? {
        let n = graph.nodes.count
        guard start >= 0, start < n, end >= 0, end < n else { return nil }
        if start == end {
            return (path: [start], edgeWays: [], lengthMeters: 0)
        }

        var dist = [Double](repeating: .infinity, count: n)
        var prev = [Int](repeating: -1, count: n)
        var prevEdgeWay = [Int](repeating: -1, count: n)
        dist[start] = 0

        var heap = MinHeap<HeapEntry>()
        heap.push(HeapEntry(node: start, dist: 0))

        while let cur = heap.pop() {
            if cur.dist > dist[cur.node] { continue }
            if cur.node == end { break }
            for edge in graph.adj[cur.node] {
                let nd = cur.dist + edge.lengthMeters
                if nd < dist[edge.neighbor] {
                    dist[edge.neighbor] = nd
                    prev[edge.neighbor] = cur.node
                    prevEdgeWay[edge.neighbor] = edge.wayIndex
                    heap.push(HeapEntry(node: edge.neighbor, dist: nd))
                }
            }
        }
        guard dist[end].isFinite else { return nil }

        var path: [Int] = []
        var edgeWays: [Int] = []
        var cur = end
        while cur != -1 {
            path.append(cur)
            if prevEdgeWay[cur] != -1 { edgeWays.append(prevEdgeWay[cur]) }
            cur = prev[cur]
        }
        path.reverse()
        edgeWays.reverse()
        return (path: path, edgeWays: edgeWays, lengthMeters: dist[end])
    }

    /// Walk the path edge by edge, group consecutive edges by name, emit one
    /// TurnInstruction per leg. Bearing comparison at each name boundary
    /// decides whether the boundary is a turn or just a name change on a
    /// straight pathway.
    private func buildTurnInstructions(edgeWays: [Int], path: [Int]) -> [TurnInstruction] {
        guard !edgeWays.isEmpty, path.count >= 2 else {
            if let last = path.last {
                return [TurnInstruction(kind: .arrive, streetName: nil,
                                        legMeters: 0, cumulativeMeters: 0, nodeIndex: last)]
            }
            return []
        }

        // Pre-compute each edge: length, label, bearing (deg from north).
        struct EdgeInfo { let len: Double; let name: String; let bearing: Double }
        var edges: [EdgeInfo] = []
        edges.reserveCapacity(edgeWays.count)
        for (i, wayIdx) in edgeWays.enumerated() {
            let way = graph.ways[wayIdx]
            let label = way.name ?? (way.park ?? "unnamed pathway")
            let len = graph.adj[path[i]].first { $0.neighbor == path[i + 1] }?.lengthMeters ?? 0
            let b = Router.bearing(from: graph.nodes[path[i]], to: graph.nodes[path[i + 1]])
            edges.append(EdgeInfo(len: len, name: label, bearing: b))
        }

        var out: [TurnInstruction] = []
        var cursor = 0
        var cumulative = 0.0
        while cursor < edges.count {
            // Extend the leg while consecutive edges share the name.
            var end = cursor
            while end + 1 < edges.count && edges[end + 1].name == edges[cursor].name {
                end += 1
            }
            let legLen = (cursor...end).reduce(0.0) { $0 + edges[$1].len }
            let kind: TurnInstruction.Kind
            if cursor == 0 {
                kind = .start
            } else {
                kind = Router.classifyTurn(
                    bearingIn: edges[cursor - 1].bearing,
                    bearingOut: edges[cursor].bearing
                )
            }
            out.append(TurnInstruction(
                kind: kind,
                streetName: edges[cursor].name,
                legMeters: legLen,
                cumulativeMeters: cumulative,
                nodeIndex: path[cursor]
            ))
            cumulative += legLen
            cursor = end + 1
        }
        // Final arrive instruction at the destination node.
        out.append(TurnInstruction(
            kind: .arrive, streetName: nil,
            legMeters: 0, cumulativeMeters: cumulative, nodeIndex: path.last!
        ))
        return out
    }

    /// Initial bearing (degrees, 0=N, 90=E) from point a to point b.
    /// Standard great-circle formula; accurate enough for trail-scale jumps.
    private static func bearing(from a: TrailGraph.Coord, to b: TrailGraph.Coord) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Map a bearing change at an intersection to a TurnInstruction.Kind.
    /// Thresholds tuned for residential pathway intersections (mostly 90°
    /// crossings with the occasional bend).
    private static func classifyTurn(bearingIn: Double, bearingOut: Double) -> TurnInstruction.Kind {
        var delta = bearingOut - bearingIn
        while delta > 180  { delta -= 360 }
        while delta < -180 { delta += 360 }
        let magnitude = abs(delta)
        if magnitude < 25       { return .continueStraight }
        if magnitude > 160      { return .uTurn }
        if delta < 0 {
            if magnitude < 50   { return .slightLeft }
            if magnitude < 130  { return .left }
            return .sharpLeft
        } else {
            if magnitude < 50   { return .slightRight }
            if magnitude < 130  { return .right }
            return .sharpRight
        }
    }

    // MARK: - Live navigation progress

    /// Where the user is along a given route. Projects userLocation onto the
    /// route polyline (segment-by-segment, equirectangular meters) and keeps
    /// the closest hit. Used by MapTabView to drive the navigation banner.
    func progress(along route: Route, at userLocation: CLLocation) -> RouteProgress {
        guard route.nodes.count >= 2 else {
            return RouteProgress(
                distanceAlongRoute: 0, distanceFromRoute: 0,
                remainingMeters: 0,
                currentInstructionIndex: 0,
                upcomingInstruction: route.turnInstructions.first,
                distanceToNext: 0,
                isArrived: true
            )
        }

        // Cumulative meters to each node along the route.
        var cum: [Double] = [0]
        cum.reserveCapacity(route.nodes.count)
        for i in 1..<route.nodes.count {
            let a = graph.nodes[route.nodes[i - 1]]
            let b = graph.nodes[route.nodes[i]]
            let segLen = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            cum.append(cum[i - 1] + segLen)
        }

        // Find the segment whose projected distance to the user is smallest.
        var best: (idx: Int, t: Double, perp: Double) = (0, 0, .infinity)
        for i in 0..<(route.nodes.count - 1) {
            let a = graph.nodes[route.nodes[i]]
            let b = graph.nodes[route.nodes[i + 1]]
            let (perp, t) = Router.projectionDistance(
                lat: userLocation.coordinate.latitude,
                lon: userLocation.coordinate.longitude,
                aLat: a.latitude, aLon: a.longitude,
                bLat: b.latitude, bLon: b.longitude
            )
            if perp < best.perp {
                best = (i, t, perp)
            }
        }

        let segLen = cum[best.idx + 1] - cum[best.idx]
        let alongRoute = cum[best.idx] + best.t * segLen
        let remaining = max(0, route.lengthMeters - alongRoute)
        let isArrived = remaining < 15

        // Current = last instruction whose cumulative meters <= alongRoute.
        var currentIdx = 0
        for (i, inst) in route.turnInstructions.enumerated() {
            if inst.cumulativeMeters <= alongRoute {
                currentIdx = i
            } else {
                break
            }
        }
        let upcoming: TurnInstruction?
        let distanceToNext: Double
        if currentIdx + 1 < route.turnInstructions.count {
            let next = route.turnInstructions[currentIdx + 1]
            upcoming = next
            distanceToNext = max(0, next.cumulativeMeters - alongRoute)
        } else {
            upcoming = route.turnInstructions.last
            distanceToNext = 0
        }

        return RouteProgress(
            distanceAlongRoute: alongRoute,
            distanceFromRoute: best.perp,
            remainingMeters: remaining,
            currentInstructionIndex: currentIdx,
            upcomingInstruction: upcoming,
            distanceToNext: distanceToNext,
            isArrived: isArrived
        )
    }

    /// Equirectangular projection of point P onto segment A→B at the
    /// midpoint latitude. Returns (perpendicular distance m, t in [0,1]).
    private static func projectionDistance(
        lat: Double, lon: Double,
        aLat: Double, aLon: Double,
        bLat: Double, bLon: Double
    ) -> (Double, Double) {
        let midLat = (aLat + bLat) / 2
        let mPerLon = 111_319.0 * cos(midLat * .pi / 180)
        let mPerLat = 111_319.0
        let ax = aLon * mPerLon; let ay = aLat * mPerLat
        let bx = bLon * mPerLon; let by = bLat * mPerLat
        let px = lon * mPerLon;  let py = lat * mPerLat
        let dx = bx - ax; let dy = by - ay
        let seg2 = dx * dx + dy * dy
        if seg2 < 1e-6 {
            return (sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay)), 0)
        }
        var t = ((px - ax) * dx + (py - ay) * dy) / seg2
        t = max(0, min(1, t))
        let cx = ax + t * dx
        let cy = ay + t * dy
        return (sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)), t)
    }

    // MARK: - Named segments + parks

    /// Distinct parks the route passes through, ordered by first appearance
    /// along the route — so "Bear Branch Park, Shadowbend Park" reads
    /// chronologically.
    private func uniqueParks(edgeWays: [Int]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for wi in edgeWays {
            guard let parks = graph.ways[wi].parks else { continue }
            for p in parks where !seen.contains(p) {
                seen.insert(p)
                out.append(p)
            }
        }
        return out
    }

    /// Walk the edges in order and group consecutive edges that belong to ways
    /// sharing the same display name. Unnamed connectors collapse into
    /// "unnamed pathway" runs.
    private func collapseSegments(edgeWays: [Int], path: [Int]) -> [(name: String, lengthMeters: Double)] {
        var out: [(name: String, lengthMeters: Double)] = []
        var currentName: String? = nil
        var currentLen: Double = 0
        for (i, wayIdx) in edgeWays.enumerated() {
            let way = graph.ways[wayIdx]
            let label = way.name ?? (way.park ?? "unnamed pathway")
            // Edge length: lookup from adjacency between path[i] and path[i+1]
            let edgeLen = graph.adj[path[i]].first { $0.neighbor == path[i + 1] }?.lengthMeters ?? 0
            if label != currentName {
                if let n = currentName, currentLen > 0 {
                    out.append((name: n, lengthMeters: currentLen))
                }
                currentName = label
                currentLen = edgeLen
            } else {
                currentLen += edgeLen
            }
        }
        if let n = currentName, currentLen > 0 {
            out.append((name: n, lengthMeters: currentLen))
        }
        return out
    }
}

// MARK: - Navigation progress

/// Live state of the user's walk against a given route. Updated whenever
/// LocationManager emits a new fix.
struct RouteProgress {
    /// Meters from the route's start to the user's projected position.
    let distanceAlongRoute: Double
    /// Perpendicular meters from the user to the closest segment of the route.
    /// Surfaced subtly in the nav banner so the user knows when they've drifted.
    let distanceFromRoute: Double
    /// Route total − distanceAlongRoute.
    let remainingMeters: Double
    /// Which TurnInstruction is currently "in effect" (the leg the user is on).
    let currentInstructionIndex: Int
    /// The next instruction the user should follow — a turn, or the arrive.
    /// Nil only if the route has zero instructions (shouldn't happen).
    let upcomingInstruction: Router.TurnInstruction?
    /// Meters from the user to where `upcomingInstruction` fires.
    let distanceToNext: Double
    /// True when the user is within 15 m of the destination.
    let isArrived: Bool
}

// MARK: - MinHeap

private struct HeapEntry: Comparable {
    let node: Int
    let dist: Double
    static func < (a: HeapEntry, b: HeapEntry) -> Bool { a.dist < b.dist }
    static func == (a: HeapEntry, b: HeapEntry) -> Bool { a.dist == b.dist && a.node == b.node }
}

private struct MinHeap<T: Comparable> {
    private var storage: [T] = []
    var isEmpty: Bool { storage.isEmpty }

    mutating func push(_ value: T) {
        storage.append(value)
        siftUp(storage.count - 1)
    }

    mutating func pop() -> T? {
        guard !storage.isEmpty else { return nil }
        storage.swapAt(0, storage.count - 1)
        let v = storage.removeLast()
        if !storage.isEmpty { siftDown(0) }
        return v
    }

    private mutating func siftUp(_ i0: Int) {
        var i = i0
        while i > 0 {
            let parent = (i - 1) / 2
            if storage[i] < storage[parent] {
                storage.swapAt(i, parent)
                i = parent
            } else { break }
        }
    }

    private mutating func siftDown(_ i0: Int) {
        var i = i0
        let count = storage.count
        while true {
            let l = 2 * i + 1
            let r = 2 * i + 2
            var smallest = i
            if l < count && storage[l] < storage[smallest] { smallest = l }
            if r < count && storage[r] < storage[smallest] { smallest = r }
            if smallest == i { break }
            storage.swapAt(i, smallest)
            i = smallest
        }
    }
}
