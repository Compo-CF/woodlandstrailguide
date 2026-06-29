import Foundation
import CoreLocation
import Observation

/// Loads POIs.json + Polygons.json from the bundle on launch, then refreshes
/// from GitHub Pages so amenity additions and corrections roll out without
/// an App Store release. Same shape as TrailStore.
@Observable
final class POIStore {
    var pois: POICatalog?
    var polygons: PolygonCatalog?
    var isRefreshing = false

    private let remotePOIs = URL(string: "https://compo-cf.github.io/woodlandstrailguide/POIs.json")!
    private let remotePolys = URL(string: "https://compo-cf.github.io/woodlandstrailguide/Polygons.json")!

    private var poiCache: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("POIs.cache.json")
    }

    private var polyCache: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("Polygons.cache.json")
    }

    init() {
        loadLocalFirst()
        Task { await refreshFromRemote() }
    }

    private func loadLocalFirst() {
        if let data = try? Data(contentsOf: poiCache),
           let decoded = Self.decodePOIs(data) {
            pois = decoded
        } else if let url = Bundle.main.url(forResource: "POIs", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = Self.decodePOIs(data) {
            pois = decoded
        }
        if let data = try? Data(contentsOf: polyCache),
           let decoded = Self.decodePolys(data) {
            polygons = decoded
        } else if let url = Bundle.main.url(forResource: "Polygons", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = Self.decodePolys(data) {
            polygons = decoded
        }
    }

    @MainActor
    func refreshFromRemote() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetchAndUpdate(url: remotePOIs, cache: poiCache, decoder: Self.decodePOIs) { [weak self] new in
            self?.pois = new
        }
        await fetchAndUpdate(url: remotePolys, cache: polyCache, decoder: Self.decodePolys) { [weak self] new in
            self?.polygons = new
        }
    }

    private func fetchAndUpdate<T>(
        url: URL,
        cache: URL,
        decoder: (Data) -> T?,
        apply: @MainActor (T) -> Void
    ) async {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let decoded = decoder(data) else { return }
            await apply(decoded)
            try? data.write(to: cache, options: .atomic)
        } catch {
            // Offline / fetch failed — keep whatever we had.
        }
    }

    private static func decodePOIs(_ data: Data) -> POICatalog? {
        guard var decoded = try? JSONDecoder().decode(POICatalog.self, from: data) else {
            return nil
        }
        // Stamp the dictionary key onto each category so views can identify
        // categories without an extra lookup.
        var keyed: [String: POICategory] = [:]
        for (key, cat) in decoded.categories {
            var c = cat
            c.key = key
            keyed[key] = c
        }
        decoded = POICatalog(version: decoded.version, source: decoded.source, categories: keyed)
        return decoded
    }

    private static func decodePolys(_ data: Data) -> PolygonCatalog? {
        try? JSONDecoder().decode(PolygonCatalog.self, from: data)
    }
}

extension POICatalog {
    /// All POIs within `meters` of the line described by `nodes`, ordered by
    /// their position along the route from start to end. Used to populate the
    /// "Along the way" section of the route summary card.
    func poisAlong(
        nodes: [CLLocationCoordinate2D],
        within meters: Double,
        excludingKeys: Set<String> = []
    ) -> [POIAlongRoute] {
        guard nodes.count >= 2 else { return [] }
        var routeCum: [Double] = [0]
        var total = 0.0
        for i in 1..<nodes.count {
            let a = CLLocation(latitude: nodes[i-1].latitude, longitude: nodes[i-1].longitude)
            let b = CLLocation(latitude: nodes[i].latitude, longitude: nodes[i].longitude)
            total += a.distance(from: b)
            routeCum.append(total)
        }

        var results: [POIAlongRoute] = []
        for (key, cat) in categories where !excludingKeys.contains(key) {
            for poi in cat.items {
                let pLoc = CLLocation(latitude: poi.lat, longitude: poi.lon)
                var best: (dist: Double, alongDist: Double) = (.infinity, 0)
                for i in 0..<(nodes.count - 1) {
                    let aLoc = CLLocation(latitude: nodes[i].latitude, longitude: nodes[i].longitude)
                    let bLoc = CLLocation(latitude: nodes[i+1].latitude, longitude: nodes[i+1].longitude)
                    let seg = aLoc.distance(from: bLoc)
                    if seg < 0.5 { continue }
                    let t = max(0, min(1, projectionT(p: pLoc, a: aLoc, b: bLoc)))
                    let projLat = aLoc.coordinate.latitude + (bLoc.coordinate.latitude - aLoc.coordinate.latitude) * t
                    let projLon = aLoc.coordinate.longitude + (bLoc.coordinate.longitude - aLoc.coordinate.longitude) * t
                    let projLoc = CLLocation(latitude: projLat, longitude: projLon)
                    let d = pLoc.distance(from: projLoc)
                    if d < best.dist {
                        let alongDist = routeCum[i] + seg * t
                        best = (d, alongDist)
                    }
                }
                if best.dist <= meters {
                    results.append(POIAlongRoute(
                        poi: poi,
                        category: cat,
                        distanceFromRoute: best.dist,
                        distanceAlongRoute: best.alongDist
                    ))
                }
            }
        }
        return results.sorted { $0.distanceAlongRoute < $1.distanceAlongRoute }
    }

    /// Linear projection parameter for closest point on segment a→b.
    /// Equirectangular approximation — accurate enough at this scale.
    private func projectionT(p: CLLocation, a: CLLocation, b: CLLocation) -> Double {
        let ax = a.coordinate.longitude, ay = a.coordinate.latitude
        let bx = b.coordinate.longitude, by = b.coordinate.latitude
        let px = p.coordinate.longitude, py = p.coordinate.latitude
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        if len2 < 1e-12 { return 0 }
        return ((px - ax) * dx + (py - ay) * dy) / len2
    }
}

/// A POI matched to an active route, with its location along the route in meters.
struct POIAlongRoute: Identifiable, Hashable {
    let poi: POI
    let category: POICategory
    let distanceFromRoute: Double
    let distanceAlongRoute: Double
    var id: String { "\(category.key):\(poi.id)" }

    static func == (l: POIAlongRoute, r: POIAlongRoute) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
