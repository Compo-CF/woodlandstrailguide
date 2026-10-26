import Foundation
import CoreLocation

/// Codable mirror of the JSON produced by `scripts/fetch_township_data.py`.
///
/// The JSON is intentionally compact (single-letter keys for the hot lists,
/// nodes as `[lat, lon]` pairs) so the bundled file stays small. Decoding
/// happens once at launch.
struct TrailGraph: Decodable {
    let version: Int
    let source: String
    let bbox: BBox
    /// All graph nodes. Index into this array is the canonical node id used
    /// everywhere else in the graph (`Way.nodeIndices`, `Adjacency`).
    let nodes: [Coord]
    let ways: [Way]
    /// `adj[i]` is the adjacency list for node `i`: each entry is an edge to
    /// a neighbor, with precomputed segment length in meters and the index of
    /// the parent `Way` (so the router can label the route with trail names).
    let adj: [[Edge]]

    struct BBox: Decodable {
        let south, west, north, east: Double
    }

    private enum CodingKeys: String, CodingKey {
        case version, source, bbox, nodes, ways, adj
    }

    /// Hand-written so each `Way` can be stamped with its stable id, which
    /// needs the node coordinates decoded first. `id` is deliberately absent
    /// from `CodingKeys` — it is derived here, never present in the JSON.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        source = try c.decode(String.self, forKey: .source)
        bbox = try c.decode(BBox.self, forKey: .bbox)
        adj = try c.decode([[Edge]].self, forKey: .adj)

        let decodedNodes = try c.decode([Coord].self, forKey: .nodes)
        var decodedWays = try c.decode([Way].self, forKey: .ways)
        for i in decodedWays.indices {
            decodedWays[i].id = Self.stableID(for: decodedWays[i], nodes: decodedNodes)
        }
        nodes = decodedNodes
        ways = decodedWays
    }

    /// A way's identity, stable across data refreshes.
    ///
    /// Paved pathways use the Township's own asset id (`PTHWY-1`…), read
    /// straight from `PathwayID` in `scripts/fetch_township_data.py`. All
    /// 1,493 of them have one and none are duplicated.
    ///
    /// The ~71 natural-surface trails have no such id, so they are keyed on
    /// geometry: both endpoints to five decimal places (~1 m) plus length.
    ///
    /// Eight ways collide under that key, and collapsing them is **correct**
    /// rather than a defect — they are the Township publishing one stretch of
    /// ground twice, once plainly and once suffixed "TEMPORARILY CLOSED"
    /// (Beaver Pond Loop, three runs of Rob Fleming Trail, Spring Creek
    /// Nature Trail MC 1), plus a triple of 0.1 m Mid-Loop stubs. One path
    /// should be one id. Resist adding `name` to break them apart: the name
    /// is what carries the closure status, and names drift.
    static func stableID(for way: Way, nodes: [Coord]) -> String {
        if let pathwayID = way.pathwayID, !pathwayID.isEmpty {
            return "p:" + pathwayID
        }
        guard let first = way.nodeIndices.first,
              let last = way.nodeIndices.last,
              nodes.indices.contains(first),
              nodes.indices.contains(last) else {
            // Shouldn't happen with well-formed data; a name-based fallback
            // is still better than an index-based one, which is guaranteed to
            // rot. Unnamed ways here get a constant key and simply never
            // persist usefully, which is the honest outcome.
            return "x:" + (way.name ?? "unknown")
        }
        let a = nodes[first]
        let b = nodes[last]
        return String(format: "g:%.5f,%.5f,%.5f,%.5f,%.1f",
                      a.latitude, a.longitude,
                      b.latitude, b.longitude,
                      way.lengthMeters)
    }

    /// A graph node. Stored as `[lat, lon]` in the JSON to halve the byte count
    /// vs. a keyed object. Decoded as a struct here for ergonomics.
    struct Coord: Decodable {
        let latitude: Double
        let longitude: Double

        var clCoord: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            latitude = try c.decode(Double.self)
            longitude = try c.decode(Double.self)
        }
    }

    /// One pathway or trail segment. May or may not have a `name` — Township
    /// data is well-named for residential pathways and park trails, but not
    /// every short connector has one.
    struct Way: Decodable, Identifiable {
        /// Stable identity, safe to persist across Township data refreshes.
        ///
        /// Assigned once by `TrailGraph.init(from:)` rather than computed,
        /// because a trail's identity depends on its node *coordinates* and a
        /// `Way` only carries indices into the graph's node array.
        ///
        /// This was previously derived from `nodeIndices.prefix(4)`, which is
        /// a bug: node indices are array positions in a regenerated graph, so
        /// every data refresh reshuffled them and silently detached anything
        /// keyed on them — favourites on all the park trails, 31.5 mi of
        /// network including every trail in George Mitchell Nature Preserve.
        /// See `TrailGraph.stableID(for:nodes:)`.
        var id: String = ""

        /// Ordered list of node indices forming this segment.
        let nodeIndices: [Int]
        /// "pathway" (residential, concrete) or "trail" (natural surface).
        let kind: String
        /// Display name. Optional — short connectors may be unnamed.
        let name: String?
        /// Length of the full segment in meters (sum of haversine across nodes).
        let lengthMeters: Double
        /// Village name for residential pathways: "Grogan's Mill" etc. Nil for
        /// park trails.
        let village: String?
        /// Park name for natural-surface trails: "George Mitchell Nature
        /// Preserve" etc. Nil for residential pathways.
        let park: String?
        /// Trail system name (e.g. "Spring Creek Greenway"). Often nil.
        let system: String?
        /// Surface material: "concrete", "asphalt", "dirt", "mulch", etc.
        let surface: String?
        /// Township pathway id for joining back to the source layer.
        let pathwayID: String?
        /// Named parks this way's geometry passes through, computed at build
        /// time by link_trails_to_parks.py via point-in-polygon. Most-
        /// overlapping park is first.
        let parks: [String]?

        enum CodingKeys: String, CodingKey {
            case n, kind, name, lengthMeters = "len_m"
            case village, park, system, surface, parks
            case pathwayID = "pathway_id"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nodeIndices = try c.decode([Int].self, forKey: .n)
            kind = try c.decode(String.self, forKey: .kind)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            lengthMeters = try c.decode(Double.self, forKey: .lengthMeters)
            village = try c.decodeIfPresent(String.self, forKey: .village)
            park = try c.decodeIfPresent(String.self, forKey: .park)
            system = try c.decodeIfPresent(String.self, forKey: .system)
            surface = try c.decodeIfPresent(String.self, forKey: .surface)
            pathwayID = try c.decodeIfPresent(String.self, forKey: .pathwayID)
            parks = try c.decodeIfPresent([String].self, forKey: .parks)
        }
    }

    /// One adjacency entry: `[neighborNodeIndex, lengthMeters, wayIndex]`.
    struct Edge: Decodable {
        let neighbor: Int
        let lengthMeters: Double
        let wayIndex: Int

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            neighbor = try c.decode(Int.self)
            lengthMeters = try c.decode(Double.self)
            wayIndex = try c.decode(Int.self)
        }
    }
}
