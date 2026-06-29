import Foundation
import CoreLocation

/// Codable mirror of POIs.json. Categories are server-driven: the JSON ships
/// the label, SF Symbol name, and tint color for each category, so adding
/// a new POI type is a data-only change (no app release required).
struct POICatalog: Decodable {
    let version: Int
    let source: String
    let categories: [String: POICategory]

    var allItems: [(POICategory, POI)] {
        categories.values.flatMap { cat in cat.items.map { (cat, $0) } }
    }
}

struct POICategory: Decodable, Identifiable {
    /// The dictionary key from POICatalog.categories — assigned by the store
    /// after decode so views can use it as an Identifiable id without lookup.
    var key: String = ""
    let label: String
    let icon: String
    let tint: String
    let items: [POI]

    var id: String { key }

    /// Parse the "#RRGGBB" tint into something the renderer can use.
    var tintHex: UInt32 {
        var s = tint
        if s.hasPrefix("#") { s.removeFirst() }
        return UInt32(s, radix: 16) ?? 0x888888
    }

    private enum CodingKeys: String, CodingKey {
        case label, icon, tint, items
    }
}

struct POI: Decodable, Hashable, Identifiable {
    let id: String
    let lat: Double
    let lon: Double
    let name: String?
    let park: String?
    let village: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private enum CodingKeys: String, CodingKey {
        case id, lat, lon, name, park, village
    }
}

/// Codable mirror of Polygons.json. Park outlines, lakes, village boundaries,
/// creek lines — visual context drawn under the trails so the map has a real
/// sense of place without depending on MapKit's POI layer.
struct PolygonCatalog: Decodable {
    let version: Int
    let source: String?
    let polygons: [String: PolygonGroup]
    let lines: [String: LineGroup]
}

struct PolygonGroup: Decodable {
    let label: String
    /// Fill color "#RRGGBB" — nil means draw outline-only (used for village
    /// boundaries which would be too loud as a fill).
    let fill: String?
    let items: [PolygonShape]

    var fillHex: UInt32? {
        guard let fill else { return nil }
        var s = fill
        if s.hasPrefix("#") { s.removeFirst() }
        return UInt32(s, radix: 16)
    }
}

struct PolygonShape: Decodable {
    /// Outer ring first, holes follow.
    let rings: [[Coord]]
    let name: String?
    let village: String?

    /// JSON ships each coord as [lat, lon] for byte savings.
    struct Coord: Decodable {
        let latitude: Double
        let longitude: Double

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            latitude = try c.decode(Double.self)
            longitude = try c.decode(Double.self)
        }

        var clCoord: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}

struct LineGroup: Decodable {
    let label: String
    let stroke: String?
    /// Each line is a sequence of [lat, lon] pairs.
    let items: [[PolygonShape.Coord]]

    var strokeHex: UInt32? {
        guard let stroke else { return nil }
        var s = stroke
        if s.hasPrefix("#") { s.removeFirst() }
        return UInt32(s, radix: 16)
    }
}
