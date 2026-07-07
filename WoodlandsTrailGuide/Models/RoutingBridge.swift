import Foundation
import CoreLocation
import Observation

/// Cross-scope bridge for a "please route this" request that arrives outside
/// the MapTabView — currently only used for incoming custom-URL-scheme
/// deep links (e.g. woodlandstrailguide://route?…). App entry parses the
/// URL and sets `pending`; MapTabView observes and applies it to its
/// routing state, then clears it back to nil.
@Observable
final class RoutingBridge {
    var pending: PendingRoute?

    struct PendingRoute: Hashable {
        let start: CLLocationCoordinate2D
        let end: CLLocationCoordinate2D
        let waypoints: [CLLocationCoordinate2D]

        static func == (l: PendingRoute, r: PendingRoute) -> Bool {
            l.start.latitude == r.start.latitude
            && l.start.longitude == r.start.longitude
            && l.end.latitude == r.end.latitude
            && l.end.longitude == r.end.longitude
            && zip(l.waypoints, r.waypoints).allSatisfy {
                $0.latitude == $1.latitude && $0.longitude == $1.longitude
            }
            && l.waypoints.count == r.waypoints.count
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(start.latitude); hasher.combine(start.longitude)
            hasher.combine(end.latitude); hasher.combine(end.longitude)
            for wp in waypoints {
                hasher.combine(wp.latitude); hasher.combine(wp.longitude)
            }
        }
    }

    /// Parses URLs of the form
    ///   woodlandstrailguide://route?start=LAT,LON&end=LAT,LON&via=LAT,LON|LAT,LON
    /// Returns nil on any parse failure — bad URLs are silently ignored.
    static func parse(_ url: URL) -> PendingRoute? {
        guard url.scheme?.lowercased() == "woodlandstrailguide",
              (url.host?.lowercased() == "route" || url.path.hasSuffix("/route")),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard let s = items["start"].flatMap(parseCoord),
              let e = items["end"].flatMap(parseCoord) else { return nil }
        let via: [CLLocationCoordinate2D]
        if let viaRaw = items["via"], !viaRaw.isEmpty {
            via = viaRaw.split(separator: "|").compactMap { parseCoord(String($0)) }
        } else {
            via = []
        }
        return PendingRoute(start: s, end: e, waypoints: via)
    }

    private static func parseCoord(_ s: String) -> CLLocationCoordinate2D? {
        let parts = s.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Build a share URL for a computed route so users can send it to
    /// someone else with the app installed.
    static func buildShareURL(start: CLLocationCoordinate2D,
                              end: CLLocationCoordinate2D,
                              waypoints: [CLLocationCoordinate2D]) -> URL? {
        var comps = URLComponents()
        comps.scheme = "woodlandstrailguide"
        comps.host = "route"
        var items: [URLQueryItem] = [
            .init(name: "start", value: coordString(start)),
            .init(name: "end", value: coordString(end)),
        ]
        if !waypoints.isEmpty {
            let via = waypoints.map(coordString).joined(separator: "|")
            items.append(.init(name: "via", value: via))
        }
        comps.queryItems = items
        return comps.url
    }

    private static func coordString(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f", c.latitude, c.longitude)
    }
}
