import Foundation
import Observation

/// User-specific per-device state: onboarding flag, launch counter, map style,
/// Ko-fi prompt cooldown. Persisted to UserDefaults — no backend, no account.
@Observable
final class UserDataStore {
    var favoriteWayIDs: Set<String> = []
    var appLaunches: Int = 0
    var mapStyle: MapStyleChoice = .standard
    var kofiPromptLastShown: Date?
    /// Log of successfully-completed walks (route arrived at destination).
    /// Newest first. Rendered on the About tab.
    var tripLog: [TripLogEntry] = []

    private let defaults = UserDefaults.standard
    private let favoritesKey = "favorites.v1"
    private let onboardingKey = "hasSeenOnboarding.v1"
    private let appLaunchesKey = "appLaunches.v1"
    private let mapStyleKey = "mapStyle.v1"
    private let kofiLastShownKey = "kofiPromptLastShown.v1"
    private let tripLogKey = "tripLog.v1"

    init() {
        if let data = defaults.data(forKey: favoritesKey),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            favoriteWayIDs = Set(arr)
        }
        appLaunches = defaults.integer(forKey: appLaunchesKey)
        if let raw = defaults.string(forKey: mapStyleKey),
           let parsed = MapStyleChoice(rawValue: raw) {
            mapStyle = parsed
        }
        kofiPromptLastShown = defaults.object(forKey: kofiLastShownKey) as? Date
        if let data = defaults.data(forKey: tripLogKey),
           let entries = try? JSONDecoder().decode([TripLogEntry].self, from: data) {
            tripLog = entries
        }
    }

    var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: onboardingKey) }
        set { defaults.set(newValue, forKey: onboardingKey) }
    }

    /// One-time intro shown the first time the directions button is tapped.
    private let routingIntroKey = "hasSeenRoutingIntro.v1"
    var hasSeenRoutingIntro: Bool {
        get { defaults.bool(forKey: routingIntroKey) }
        set { defaults.set(newValue, forKey: routingIntroKey) }
    }

    func recordAppLaunch() {
        appLaunches += 1
        defaults.set(appLaunches, forKey: appLaunchesKey)
    }

    func isFavorite(_ id: String) -> Bool { favoriteWayIDs.contains(id) }

    func toggleFavorite(_ id: String) {
        if favoriteWayIDs.contains(id) {
            favoriteWayIDs.remove(id)
        } else {
            favoriteWayIDs.insert(id)
        }
        if let data = try? JSONEncoder().encode(Array(favoriteWayIDs)) {
            defaults.set(data, forKey: favoritesKey)
        }
    }

    func saveMapStyle() {
        defaults.set(mapStyle.rawValue, forKey: mapStyleKey)
    }

    // MARK: - Ko-fi support nudge

    /// Whether the Ko-fi support prompt is eligible to show on this launch.
    /// Requires the user to be engaged (10+ launches OR 3+ favorites saved)
    /// AND at least 45 days since the last time it was shown. Mirrors the
    /// WoodlandsFishing engagement rule so the prompt feels earned, not pushy.
    var shouldShowKofiPrompt: Bool {
        guard appLaunches >= 10 || favoriteWayIDs.count >= 3 else { return false }
        if let last = kofiPromptLastShown {
            let daysSince = Calendar.current.dateComponents([.day], from: last, to: .now).day ?? 0
            return daysSince >= 45
        }
        return true
    }

    func markKofiPromptShown() {
        kofiPromptLastShown = .now
        defaults.set(kofiPromptLastShown, forKey: kofiLastShownKey)
    }

    // MARK: - System review prompt eligibility

    /// Cumulative routes the user has successfully walked to completion
    /// (arrived state hit). Used as one engagement signal for review prompts.
    var routesCompleted: Int {
        get { defaults.integer(forKey: routesCompletedKey) }
        set { defaults.set(newValue, forKey: routesCompletedKey) }
    }
    private let routesCompletedKey = "routesCompleted.v1"

    /// When we last asked iOS to consider showing the system review prompt.
    /// Apple caps the actual presentation at 3/year regardless of how often
    /// we call requestReview(), but we add a 30-day local cooldown so we
    /// don't burn a request inside a short engagement window.
    var lastReviewRequestedAt: Date? {
        get { defaults.object(forKey: lastReviewRequestKey) as? Date }
        set { defaults.set(newValue, forKey: lastReviewRequestKey) }
    }
    private let lastReviewRequestKey = "lastReviewRequestedAt.v1"

    func markReviewRequested() {
        lastReviewRequestedAt = .now
    }

    func markRouteCompleted() {
        routesCompleted += 1
    }

    // MARK: - Trip log

    func recordTrip(distanceMeters: Double, startLabel: String, endLabel: String) {
        let entry = TripLogEntry(
            id: UUID(),
            date: .now,
            distanceMeters: distanceMeters,
            startLabel: startLabel,
            endLabel: endLabel
        )
        tripLog.insert(entry, at: 0)
        // Cap to the most recent 100 to keep UserDefaults compact.
        if tripLog.count > 100 { tripLog = Array(tripLog.prefix(100)) }
        saveTripLog()
    }

    func deleteTrip(id: UUID) {
        tripLog.removeAll { $0.id == id }
        saveTripLog()
    }

    private func saveTripLog() {
        if let data = try? JSONEncoder().encode(tripLog) {
            defaults.set(data, forKey: tripLogKey)
        }
    }

    /// True when (a) the user has shown enough engagement to deserve being
    /// asked, and (b) we haven't asked recently. The actual decision to
    /// show a prompt still belongs to iOS — this just gates our call to
    /// requestReview(), so we don't burn cycles on first-launch noise.
    var eligibleForReviewRequest: Bool {
        // Never on first launch — Apple may suppress and reduce our quota.
        guard appLaunches >= 2 else { return false }
        if let last = lastReviewRequestedAt {
            let days = Calendar.current.dateComponents([.day], from: last, to: .now).day ?? 0
            if days < 30 { return false }
        }
        return true
    }
}

/// A completed walk. Persisted so users can look back at where they've been.
struct TripLogEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let date: Date
    let distanceMeters: Double
    /// Name of the first named segment along the route (e.g. "Sawmill Path").
    let startLabel: String
    /// Name of the last named segment along the route.
    let endLabel: String

    var miles: Double { distanceMeters / 1609.344 }
}

/// Map base-layer style. Mirrors MKMapConfiguration's three concrete subclasses.
enum MapStyleChoice: String, CaseIterable {
    case standard
    case hybrid     // satellite imagery + roads & labels overlay
    case satellite  // imagery only, no labels

    var label: String {
        switch self {
        case .standard:  return "Map"
        case .hybrid:    return "Hybrid"
        case .satellite: return "Satellite"
        }
    }

    var systemImage: String {
        switch self {
        case .standard:  return "map"
        case .hybrid:    return "globe.americas.fill"
        case .satellite: return "globe.americas"
        }
    }

    var next: MapStyleChoice {
        switch self {
        case .standard:  return .hybrid
        case .hybrid:    return .satellite
        case .satellite: return .standard
        }
    }
}
