import Foundation
import Observation

/// User-specific per-device state: onboarding flag, launch counter.
/// Persisted to UserDefaults — no backend, no account.
///
/// Favorites and a trip log are scaffolded for a future v1.x; the structure
/// matches the WoodlandsFishing app's UserDataStore so porting those features
/// later is a small lift.
@Observable
final class UserDataStore {
    var favoriteWayIDs: Set<String> = []
    var appLaunches: Int = 0

    private let defaults = UserDefaults.standard
    private let favoritesKey = "favorites.v1"
    private let onboardingKey = "hasSeenOnboarding.v1"
    private let appLaunchesKey = "appLaunches.v1"

    init() {
        if let data = defaults.data(forKey: favoritesKey),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            favoriteWayIDs = Set(arr)
        }
        appLaunches = defaults.integer(forKey: appLaunchesKey)
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
}
