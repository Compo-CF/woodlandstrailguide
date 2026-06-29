import Foundation
import CoreLocation
import Observation
import OSLog

/// Loads the trail graph from the app bundle on launch, then asynchronously
/// refreshes it from the GitHub Pages-hosted copy so we can ship trail
/// updates without an App Store release. Mirrors the SpotStore pattern from
/// the WoodlandsFishing app.
@Observable
final class TrailStore {
    /// The decoded graph. Nil until the first successful load.
    var graph: TrailGraph?
    /// True while a remote refresh is in flight.
    var isRefreshing = false
    /// User's current location, fed in from LocationManager via the app root.
    var userLocation: CLLocation?
    /// Last load/decode error surfaced to the UI. Nil when everything's fine.
    /// MapTabView shows this in place of the spinner once a few seconds have
    /// passed, so a silent decode failure doesn't look like an infinite hang.
    var loadError: String?

    private let log = Logger(subsystem: "com.compofelice.WoodlandsTrailGuide", category: "TrailStore")

    /// Remote source of truth. Update the JSON at `docs/TrailGraph.json` in
    /// the repo and push — GitHub Pages serves the new copy and every app
    /// picks it up on next launch.
    private let remoteURL = URL(string: "https://compo-cf.github.io/woodlandstrailguide/TrailGraph.json")!

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("TrailGraph.cache.json")
    }

    init() {
        loadLocalFirst()
        Task { await refreshFromRemote() }
    }

    /// Prefer the cached remote copy from a previous launch, else the bundled
    /// seed. Loud about failures — silent ones make hangs look like infinite
    /// loaders.
    private func loadLocalFirst() {
        if let data = try? Data(contentsOf: cacheURL) {
            do {
                graph = try JSONDecoder().decode(TrailGraph.self, from: data)
                log.info("Loaded cached TrailGraph: \(self.graph?.ways.count ?? 0) ways")
                return
            } catch {
                log.error("Cache decode failed: \(error.localizedDescription, privacy: .public)")
                // Fall through to bundled.
            }
        }
        loadBundled()
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "TrailGraph", withExtension: "json") else {
            let msg = "TrailGraph.json missing from app bundle"
            log.error("\(msg, privacy: .public)")
            loadError = msg
            return
        }
        do {
            let data = try Data(contentsOf: url)
            log.info("Read bundled TrailGraph.json (\(data.count) bytes)")
            let decoded = try JSONDecoder().decode(TrailGraph.self, from: data)
            graph = decoded
            log.info("Decoded bundled graph: \(decoded.ways.count) ways, \(decoded.nodes.count) nodes")
        } catch let DecodingError.keyNotFound(key, ctx) {
            let msg = "Decode failed — missing key '\(key.stringValue)' at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            log.error("\(msg, privacy: .public)")
            loadError = msg
        } catch let DecodingError.typeMismatch(type, ctx) {
            let msg = "Decode failed — type mismatch (expected \(type)) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            log.error("\(msg, privacy: .public)")
            loadError = msg
        } catch let DecodingError.valueNotFound(type, ctx) {
            let msg = "Decode failed — value not found (\(type)) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            log.error("\(msg, privacy: .public)")
            loadError = msg
        } catch {
            let msg = "Decode failed: \(error.localizedDescription)"
            log.error("\(msg, privacy: .public)")
            loadError = msg
        }
    }

    @MainActor
    func refreshFromRemote() async {
        isRefreshing = true
        defer { isRefreshing = false }
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log.error("Remote refresh: non-HTTP response")
                return
            }
            log.info("Remote refresh: HTTP \(http.statusCode), \(data.count) bytes")
            guard http.statusCode == 200 else {
                if graph == nil { loadError = "Remote refresh returned HTTP \(http.statusCode)" }
                return
            }
            let decoded = try JSONDecoder().decode(TrailGraph.self, from: data)
            guard !decoded.ways.isEmpty else {
                log.error("Remote refresh: decoded graph has no ways")
                return
            }
            graph = decoded
            loadError = nil
            try? data.write(to: cacheURL, options: .atomic)
            log.info("Remote refresh applied: \(decoded.ways.count) ways")
        } catch {
            log.error("Remote refresh failed: \(error.localizedDescription, privacy: .public)")
            if graph == nil { loadError = "Remote refresh failed: \(error.localizedDescription)" }
        }
    }
}
