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

    /// How close the user is to earning this one.
    ///
    /// Exists because a locked badge that only says "Walk 25 miles total"
    /// is the same for somebody at 24 miles as for somebody at zero. Every
    /// threshold here is numeric, so there's no reason not to say which.
    struct Progress {
        /// 0...1, clamped — drives the bar.
        let fraction: Double
        /// Human-readable, e.g. "18.4 / 25 mi".
        let label: String
    }

    /// Nil when there's nothing meaningful to count toward (the supporter
    /// badge is binary — a half-tip isn't a thing).
    func progress(stats: TripStats, favoritesCount: Int, hasTipped: Bool) -> Progress? {
        func make(_ current: Double, _ target: Double, _ unit: String,
                  decimals: Int = 0) -> Progress {
            // Never show more than the target: "27 / 25 mi" on an unearned
            // badge looks like a bug, and on an earned one it's noise.
            let shown = min(current, target)
            let fmt = decimals > 0 ? "%.\(decimals)f" : "%.0f"
            return Progress(
                fraction: target > 0 ? min(max(current / target, 0), 1) : 0,
                label: "\(String(format: fmt, shown)) / \(String(format: fmt, target)) \(unit)"
            )
        }

        switch id {
        case "first_walk":  return make(Double(stats.walkCount), 1, "walk")
        case "miles_5":     return make(stats.totalMiles, 5, "mi", decimals: 1)
        case "miles_25":    return make(stats.totalMiles, 25, "mi", decimals: 1)
        case "miles_100":   return make(stats.totalMiles, 100, "mi", decimals: 1)
        case "walks_10":    return make(Double(stats.walkCount), 10, "walks")
        case "longest_5":   return make(stats.longestMiles, 5, "mi", decimals: 1)
        case "streak_3":    return make(Double(stats.currentStreakDays), 3, "days")
        case "streak_7":    return make(Double(stats.currentStreakDays), 7, "days")
        case "streak_30":   return make(Double(stats.currentStreakDays), 30, "days")
        case "favorites_5": return make(Double(favoritesCount), 5, "saved")
        default:            return nil
        }
    }

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
