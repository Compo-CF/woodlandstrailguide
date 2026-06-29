import Foundation
import CoreLocation
import Observation

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
    /// seed. This keeps the UI from being empty for even one frame.
    private func loadLocalFirst() {
        if let cached = try? Data(contentsOf: cacheURL),
           let decoded = Self.decode(cached) {
            graph = decoded
            return
        }
        loadBundled()
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "TrailGraph", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = Self.decode(data) else {
            print("Bundled TrailGraph.json missing or invalid")
            return
        }
        graph = decoded
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
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let decoded = Self.decode(data),
                  !decoded.ways.isEmpty
            else { return }
            graph = decoded
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            // Offline or fetch failed — keep whatever local data we had.
        }
    }

    private static func decode(_ data: Data) -> TrailGraph? {
        try? JSONDecoder().decode(TrailGraph.self, from: data)
    }
}
