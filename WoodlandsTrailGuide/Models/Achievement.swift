import Foundation

/// A milestone badge earned from cumulative walking stats. The catalog is
/// static; which ones are unlocked is computed from TripStats + a couple of
/// other signals (favorites saved, whether the user has ever tipped).
///
/// Once earned an achievement stays earned — UserDataStore.celebratedAchievementIDs
/// is the permanent record, since some of the underlying stats (streak in
/// particular) can drop back down after being hit.
struct Achievement: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String

    static let all: [Achievement] = [
        Achievement(id: "first_walk", title: "First Steps",
                    subtitle: "Complete your first walk", systemImage: "figure.walk"),
        Achievement(id: "miles_5", title: "Getting Started",
                    subtitle: "Walk 5 miles total", systemImage: "shoeprints.fill"),
        Achievement(id: "miles_25", title: "Trailblazer",
                    subtitle: "Walk 25 miles total", systemImage: "map.fill"),
        Achievement(id: "miles_100", title: "Century Walker",
                    subtitle: "Walk 100 miles total", systemImage: "trophy.fill"),
        Achievement(id: "walks_10", title: "Regular",
                    subtitle: "Complete 10 walks", systemImage: "checkmark.seal.fill"),
        Achievement(id: "longest_5", title: "Marathoner",
                    subtitle: "Complete a single walk of 5+ miles", systemImage: "flame.fill"),
        Achievement(id: "streak_3", title: "3-Day Streak",
                    subtitle: "Walk 3 days in a row", systemImage: "calendar"),
        Achievement(id: "streak_7", title: "Week Streak",
                    subtitle: "Walk 7 days in a row", systemImage: "calendar.badge.clock"),
        Achievement(id: "streak_30", title: "Monthly Streak",
                    subtitle: "Walk 30 days in a row", systemImage: "calendar.badge.exclamationmark"),
        Achievement(id: "favorites_5", title: "Collector",
                    subtitle: "Save 5 favorite trails", systemImage: "heart.fill"),
        Achievement(id: "supporter", title: "Supporter",
                    subtitle: "Send a tip to support the app", systemImage: "cup.and.saucer.fill"),
    ]

    /// Which achievement IDs the given stats currently qualify for. Pure
    /// function of the inputs — callers diff this against what's already
    /// been celebrated to find newly-earned ones.
    static func unlockedIDs(stats: TripStats, favoritesCount: Int, hasTipped: Bool) -> Set<String> {
        var ids: Set<String> = []
        if stats.walkCount >= 1 { ids.insert("first_walk") }
        if stats.totalMiles >= 5 { ids.insert("miles_5") }
        if stats.totalMiles >= 25 { ids.insert("miles_25") }
        if stats.totalMiles >= 100 { ids.insert("miles_100") }
        if stats.walkCount >= 10 { ids.insert("walks_10") }
        if stats.longestMiles >= 5 { ids.insert("longest_5") }
        if stats.currentStreakDays >= 3 { ids.insert("streak_3") }
        if stats.currentStreakDays >= 7 { ids.insert("streak_7") }
        if stats.currentStreakDays >= 30 { ids.insert("streak_30") }
        if favoritesCount >= 5 { ids.insert("favorites_5") }
        if hasTipped { ids.insert("supporter") }
        return ids
    }
}
