import Foundation
import Observation

/// A time-limited, curated set of walks (an App Store In-App Event in the
/// app). Kept out of `FeaturedWalks.json` on purpose: that file is refreshed
/// remotely by every shipped version, and versions before this one have no
/// date logic, so they would show seasonal walks all year.
struct WalkEvent: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let tagline: String
    /// "yyyy-MM-dd", Woodlands local time. The Featured tab starts showing
    /// the event (as "starts Jan 1") from this day, matching the App Store
    /// event page, which goes up before the event begins.
    let previewFrom: String
    let startsOn: String
    /// Inclusive last day.
    let endsOn: String
    let walks: [FeaturedWalk]

    enum Phase { case hidden, upcoming, live, ended }

    func phase(at now: Date = .now) -> Phase {
        guard let preview = Self.day(previewFrom),
              let start = Self.day(startsOn),
              let end = Self.day(endsOn),
              let endExclusive = Self.calendar.date(byAdding: .day, value: 1, to: end) else {
            return .hidden
        }
        if now >= endExclusive { return .ended }
        if now >= start { return .live }
        if now >= preview { return .upcoming }
        return .hidden
    }

    /// "Jan 1 – Jan 31"
    var dateRangeLabel: String {
        guard let s = Self.day(startsOn), let e = Self.day(endsOn) else { return "" }
        let f = DateFormatter()
        f.calendar = Self.calendar
        f.timeZone = Self.calendar.timeZone
        f.dateFormat = "MMM d"
        return "\(f.string(from: s)) – \(f.string(from: e))"
    }

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        return c
    }()

    static func day(_ s: String) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// Same bundled-seed + GitHub Pages refresh pattern as FeaturedWalkStore.
@Observable
final class WalkEventStore {
    static let remoteURL = URL(string: "https://compo-cf.github.io/woodlandstrailguide/EventWalks.json")!
    static let cacheFilename = "EventWalks.cache.json"

    var event: WalkEvent?
    /// Set by the `woodlandstrailguide://event/...` deep link (the App Store
    /// In-App Event card links here). ContentView switches to the Featured
    /// tab and FeaturedTabView presents the event sheet.
    var showRequested = false

    init() {
        if !loadFromDiskCache() { loadBundled() }
        Task { await refresh() }
    }

    /// Event to promote in the Featured tab right now, if any.
    var featuredEvent: WalkEvent? {
        guard let event else { return nil }
        switch event.phase() {
        case .upcoming, .live: return event
        case .hidden, .ended: return nil
        }
    }

    @discardableResult
    private func loadFromDiskCache() -> Bool {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WalkEvent.self, from: data) else {
            return false
        }
        event = decoded
        return true
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "EventWalks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WalkEvent.self, from: data) else {
            return
        }
        event = decoded
    }

    func refresh() async {
        do {
            var req = URLRequest(url: Self.remoteURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(WalkEvent.self, from: data)
            await MainActor.run {
                event = decoded
                if let url = cacheFileURL { try? data.write(to: url, options: .atomic) }
            }
        } catch {
            // Keep whatever we had; the bundled seed always works offline.
        }
    }

    /// Handles `woodlandstrailguide://event` and `woodlandstrailguide://event/<id>`.
    /// Returns true when the URL was an event link.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "woodlandstrailguide",
              url.host?.lowercased() == "event" else { return false }
        showRequested = true
        return true
    }

    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Self.cacheFilename)
    }
}
