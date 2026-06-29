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
    struct Way: Decodable {
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
            case n, kind = "k", name, lengthMeters = "len_m"
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
