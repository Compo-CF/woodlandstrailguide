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

    private let defaults = UserDefaults.standard
    private let favoritesKey = "favorites.v1"
    private let onboardingKey = "hasSeenOnboarding.v1"
    private let appLaunchesKey = "appLaunches.v1"
    private let mapStyleKey = "mapStyle.v1"
    private let kofiLastShownKey = "kofiPromptLastShown.v1"

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
    }

    var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: onboardingKey) }
        set { defaults.set(newValue, forKey: onboardingKey) }
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
