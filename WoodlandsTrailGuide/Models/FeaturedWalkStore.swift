import Foundation
import Observation

/// Curator-managed set of "Featured Walks" — routes highlighted by the
/// developer for their scenery, amenities, or difficulty. Same
/// bundled-seed + Pages-refresh pattern as TrailStore/POIStore.
///
///  Precedence:
///   1. On-disk cache in Documents (last successful refresh)
///   2. Bundled seed JSON shipped with the app
///   3. Empty (until first successful remote fetch)
@Observable
final class FeaturedWalkStore {
    static let remoteURL = URL(string: "https://compo-cf.github.io/woodlandstrailguide/FeaturedWalks.json")!
    static let cacheFilename = "FeaturedWalks.cache.json"

    var walks: [FeaturedWalk] = []
    var loadError: String?
    var lastFetchedAt: Date?

    init() {
        if !loadFromDiskCache() {
            loadBundled()
        }
        Task { await refresh() }
    }

    @discardableResult
    private func loadFromDiskCache() -> Bool {
        guard let cacheURL = cacheFileURL,
              FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([FeaturedWalk].self, from: data) else {
            return false
        }
        walks = decoded
        return true
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "FeaturedWalks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([FeaturedWalk].self, from: data) else {
            return
        }
        walks = decoded
    }

    /// Fetch the latest walks from GitHub Pages and update in-memory + disk cache.
    /// Failures are silent — we keep whatever we had; the UI stays functional.
    func refresh() async {
        do {
            var req = URLRequest(url: Self.remoteURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode([FeaturedWalk].self, from: data)
            await MainActor.run {
                walks = decoded
                loadError = nil
                lastFetchedAt = .now
                saveToDiskCache(data: data)
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
            }
        }
    }

    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Self.cacheFilename)
    }

    private func saveToDiskCache(data: Data) {
        guard let url = cacheFileURL else { return }
        try? data.write(to: url, options: .atomic)
    }
}
