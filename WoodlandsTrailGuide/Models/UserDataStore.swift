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
    /// Walk vs bike — changes the pace assumption used for every ETA/duration
    /// display (route summary, nav banner, remaining-time). Doesn't change
    /// the routed path itself (shared pathway network either way).
    var travelMode: TravelMode = .walk
    /// When on, routing penalizes natural-surface trail edges so the router
    /// strongly prefers paved pathways — for strollers/wheelchairs/etc.
    /// Still finds a route even if the only path is unpaved (penalty, not
    /// exclusion), it just won't be picked when a paved alternative exists.
    var preferPavedRoutes: Bool = false
    /// Opt-in — off by default. When on, a completed walk is also logged to
    /// Apple Health as an HKWorkout.
    var healthKitSyncEnabled: Bool = false
    /// Permanent record of which achievements have ever been earned. Unlike
    /// the live stats that back them (streak in particular can drop back to
    /// zero), once earned an achievement stays unlocked.
    var celebratedAchievementIDs: Set<String> = []

    private let defaults = UserDefaults.standard
    private let favoritesKey = "favorites.v1"
    private let onboardingKey = "hasSeenOnboarding.v1"
    private let appLaunchesKey = "appLaunches.v1"
    private let mapStyleKey = "mapStyle.v1"
    private let kofiLastShownKey = "kofiPromptLastShown.v1"
    private let tripLogKey = "tripLog.v1"
    private let travelModeKey = "travelMode.v1"
    private let preferPavedKey = "preferPavedRoutes.v1"
    private let healthKitSyncKey = "healthKitSyncEnabled.v1"
    private let celebratedAchievementsKey = "celebratedAchievementIDs.v1"

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
        if let raw = defaults.string(forKey: travelModeKey),
           let parsed = TravelMode(rawValue: raw) {
            travelMode = parsed
        }
        preferPavedRoutes = defaults.bool(forKey: preferPavedKey)
        healthKitSyncEnabled = defaults.bool(forKey: healthKitSyncKey)
        if let data = defaults.data(forKey: celebratedAchievementsKey),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            celebratedAchievementIDs = Set(arr)
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
        // Doesn't affect the "supporter" badge either way — that's checked
        // with real tip status at the tip-purchase call site.
        checkForNewAchievements(hasTipped: false)
    }

    func saveMapStyle() {
        defaults.set(mapStyle.rawValue, forKey: mapStyleKey)
    }

    func saveTravelMode() {
        defaults.set(travelMode.rawValue, forKey: travelModeKey)
    }

    func savePreferPavedRoutes() {
        defaults.set(preferPavedRoutes, forKey: preferPavedKey)
    }

    func saveHealthKitSyncEnabled() {
        defaults.set(healthKitSyncEnabled, forKey: healthKitSyncKey)
    }

    // MARK: - Achievements

    /// Diffs the achievements earnable from current stats against what's
    /// already been celebrated, persists any new ones, and returns them
    /// (newest-worthy first) so the caller can show a toast. Safe to call
    /// often — e.g. after every favorite toggle or tip — since it's a no-op
    /// when nothing new was earned.
    @discardableResult
    func checkForNewAchievements(hasTipped: Bool) -> [Achievement] {
        let earned = Achievement.unlockedIDs(
            stats: tripStats,
            favoritesCount: favoriteWayIDs.count,
            hasTipped: hasTipped
        )
        let fresh = earned.subtracting(celebratedAchievementIDs)
        guard !fresh.isEmpty else { return [] }
        celebratedAchievementIDs.formUnion(fresh)
        if let data = try? JSONEncoder().encode(Array(celebratedAchievementIDs)) {
            defaults.set(data, forKey: celebratedAchievementsKey)
        }
        return Achievement.all.filter { fresh.contains($0.id) }
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

    func recordTrip(distanceMeters: Double, startLabel: String, endLabel: String,
                     durationSeconds: Double? = nil, travelMode: TravelMode = .walk) {
        let entry = TripLogEntry(
            id: UUID(),
            date: .now,
            distanceMeters: distanceMeters,
            startLabel: startLabel,
            endLabel: endLabel,
            durationSeconds: durationSeconds,
            travelMode: travelMode
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

    // MARK: - Aggregated trip stats

    /// Rolls the trip log into a small stats snapshot: total miles, total
    /// walks, longest single walk, and consecutive-day streak. Recomputed
    /// on each access, but tripLog is tiny (capped at 100 entries) so this
    /// is essentially free.
    var tripStats: TripStats {
        var total = 0.0
        var longest = 0.0
        let calendar = Calendar.current
        var walkDays = Set<Date>()
        for entry in tripLog {
            total += entry.distanceMeters
            longest = max(longest, entry.distanceMeters)
            walkDays.insert(calendar.startOfDay(for: entry.date))
        }
        // Streak: count consecutive days walking, working back from today.
        var streak = 0
        var cursor = calendar.startOfDay(for: .now)
        while walkDays.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return TripStats(
            totalMeters: total,
            walkCount: tripLog.count,
            longestMeters: longest,
            currentStreakDays: streak
        )
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

struct TripStats: Hashable {
    let totalMeters: Double
    let walkCount: Int
    let longestMeters: Double
    let currentStreakDays: Int

    var totalMiles: Double { totalMeters / 1609.344 }
    var longestMiles: Double { longestMeters / 1609.344 }
    var isEmpty: Bool { walkCount == 0 }
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
    /// Wall-clock duration of the walk, in seconds. Optional (and decodes
    /// gracefully via decodeIfPresent) since entries recorded before this
    /// field existed don't have it.
    let durationSeconds: Double?
    /// Walk vs bike. Defaults to .walk on decode for pre-existing entries —
    /// this field didn't exist before travel modes shipped.
    let travelMode: TravelMode

    init(id: UUID, date: Date, distanceMeters: Double, startLabel: String,
         endLabel: String, durationSeconds: Double? = nil, travelMode: TravelMode = .walk) {
        self.id = id
        self.date = date
        self.distanceMeters = distanceMeters
        self.startLabel = startLabel
        self.endLabel = endLabel
        self.durationSeconds = durationSeconds
        self.travelMode = travelMode
    }

    enum CodingKeys: String, CodingKey {
        case id, date, distanceMeters, startLabel, endLabel, durationSeconds, travelMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        distanceMeters = try c.decode(Double.self, forKey: .distanceMeters)
        startLabel = try c.decode(String.self, forKey: .startLabel)
        endLabel = try c.decode(String.self, forKey: .endLabel)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds)
        travelMode = try c.decodeIfPresent(TravelMode.self, forKey: .travelMode) ?? .walk
    }

    var miles: Double { distanceMeters / 1609.344 }
}

/// Walk vs bike. Both route over the same shared pathway network — this
/// only changes the pace assumption used for ETA/duration displays (and
/// which HKWorkoutActivityType a synced walk is logged as).
enum TravelMode: String, CaseIterable, Codable {
    case walk
    case bike

    var label: String {
        switch self {
        case .walk: return "Walk"
        case .bike: return "Bike"
        }
    }

    var systemImage: String {
        switch self {
        case .walk: return "figure.walk"
        case .bike: return "figure.outdoor.cycle"
        }
    }

    /// Assumed pace in miles per hour, used for every duration estimate.
    var paceMph: Double {
        switch self {
        case .walk: return 3.0
        case .bike: return 12.0
        }
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
