import Foundation
import CoreLocation
import Observation

/// Fetches elevation samples along a route from Open-Elevation
/// (open-elevation.com — free public API, no key, batch POST endpoint).
/// Results are cached to disk keyed by a hash of the sampled coordinates,
/// so once a user runs the same route the profile appears instantly.
///
/// Cached miss + failed fetch = we just hide the profile; hiking/biking
/// doesn't need elevation to be usable, so it's a nice-to-have overlay.
@Observable
final class ElevationService {
    /// Sampled points → elevation (meters) parallel arrays, per route hash.
    /// Nil while a fetch is in flight for a route we don't have cached.
    private var cache: [String: [Double]] = [:]
    /// Route hashes currently being fetched. Used to dedupe concurrent asks.
    private var inflight = Set<String>()

    private static let sampleSpacingMeters = 100.0
    private static let maxSamples = 100
    private var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("elevation_cache.json")
    }

    init() {
        loadCache()
    }

    /// Returns cached elevations for this route if available; otherwise nil
    /// and kicks off a background fetch (call again after the store notifies).
    func profile(for route: Router.Route, graph: TrailGraph) -> ElevationProfile? {
        let samples = sample(route: route, graph: graph)
        guard !samples.isEmpty else { return nil }
        let key = hashKey(for: samples)
        if let elevations = cache[key], elevations.count == samples.count {
            return ElevationProfile(distancesMeters: samples.map(\.distance), elevationsMeters: elevations)
        }
        if !inflight.contains(key) {
            inflight.insert(key)
            Task { await fetch(key: key, samples: samples) }
        }
        return nil
    }

    private func sample(route: Router.Route, graph: TrailGraph) -> [Sample] {
        guard route.nodes.count >= 2 else { return [] }
        // Cumulative distance to each route node.
        var cum = [0.0]
        for i in 1..<route.nodes.count {
            let a = graph.nodes[route.nodes[i - 1]]
            let b = graph.nodes[route.nodes[i]]
            let d = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            cum.append(cum.last! + d)
        }
        let total = cum.last ?? 0
        let count = min(Self.maxSamples, max(2, Int(total / Self.sampleSpacingMeters) + 1))
        let step = total / Double(count - 1)
        var out: [Sample] = []
        out.reserveCapacity(count)
        var segIdx = 0
        for i in 0..<count {
            let target = Double(i) * step
            while segIdx + 1 < cum.count - 1 && cum[segIdx + 1] < target {
                segIdx += 1
            }
            let d0 = cum[segIdx]
            let d1 = cum[segIdx + 1]
            let t = d1 > d0 ? (target - d0) / (d1 - d0) : 0
            let a = graph.nodes[route.nodes[segIdx]]
            let b = graph.nodes[route.nodes[segIdx + 1]]
            let lat = a.latitude + (b.latitude - a.latitude) * t
            let lon = a.longitude + (b.longitude - a.longitude) * t
            out.append(Sample(distance: target, latitude: lat, longitude: lon))
        }
        return out
    }

    private func hashKey(for samples: [Sample]) -> String {
        var hasher = Hasher()
        for s in samples {
            hasher.combine(Int(s.latitude * 1e5))
            hasher.combine(Int(s.longitude * 1e5))
        }
        hasher.combine(samples.count)
        return String(hasher.finalize())
    }

    private func fetch(key: String, samples: [Sample]) async {
        defer {
            Task { @MainActor in self.inflight.remove(key) }
        }
        guard let url = URL(string: "https://api.open-elevation.com/api/v1/lookup") else { return }
        struct RequestBody: Encodable {
            struct Loc: Encodable {
                let latitude: Double
                let longitude: Double
            }
            let locations: [Loc]
        }
        let body = RequestBody(locations: samples.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            struct ResponseBody: Decodable {
                struct Result: Decodable {
                    let elevation: Double
                }
                let results: [Result]
            }
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            let elevations = decoded.results.map(\.elevation)
            guard elevations.count == samples.count else { return }
            await MainActor.run {
                self.cache[key] = elevations
                self.persistCache()
            }
        } catch {
            // Open-Elevation is occasionally flaky. Swallow silently.
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data) else {
            return
        }
        cache = decoded
    }

    private func persistCache() {
        // Cap on-disk cache to the 50 most-recent entries to avoid growth.
        let trimmed = cache.count > 50 ? Dictionary(uniqueKeysWithValues: Array(cache.suffix(50))) : cache
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }

    private struct Sample: Hashable {
        let distance: Double
        let latitude: Double
        let longitude: Double
    }
}

struct ElevationProfile: Hashable {
    /// Cumulative distance along the route, meters.
    let distancesMeters: [Double]
    /// Elevation at each sample, meters above sea level.
    let elevationsMeters: [Double]

    /// Total meters of climb — sum of positive segment deltas.
    var gainMeters: Double {
        var g = 0.0
        for i in 1..<elevationsMeters.count {
            let d = elevationsMeters[i] - elevationsMeters[i - 1]
            if d > 0 { g += d }
        }
        return g
    }

    /// Total meters of descent — sum of negative segment deltas.
    var lossMeters: Double {
        var l = 0.0
        for i in 1..<elevationsMeters.count {
            let d = elevationsMeters[i] - elevationsMeters[i - 1]
            if d < 0 { l -= d }
        }
        return l
    }

    var minMeters: Double { elevationsMeters.min() ?? 0 }
    var maxMeters: Double { elevationsMeters.max() ?? 0 }
}

extension ElevationProfile {
    var gainFeet: Double { gainMeters * 3.28084 }
    var lossFeet: Double { lossMeters * 3.28084 }
}
