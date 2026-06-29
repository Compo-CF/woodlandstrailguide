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
        let n = graph.nodes.count
        guard start >= 0, start < n, end >= 0, end < n else { return nil }
        if start == end {
            return Route(nodes: [start], lengthMeters: 0, namedSegments: [], parks: [])
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

        // Reconstruct path
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

        return Route(
            nodes: path,
            lengthMeters: dist[end],
            namedSegments: collapseSegments(edgeWays: edgeWays, path: path),
            parks: uniqueParks(edgeWays: edgeWays)
        )
    }

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
