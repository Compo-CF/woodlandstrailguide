import Foundation

/// Curator-managed walk that highlights particularly good views, features, or
/// experiences along the pathway system. Delivered via `FeaturedWalks.json` on
/// GitHub Pages so new walks can be added without shipping an app update.
struct FeaturedWalk: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let village: String?
    let park: String?
    let difficulty: DifficultyRating
    let distanceMiles: Double
    let elevationGainFeet: Double?
    /// Ordered list of coordinates: the first is the start, the last is the
    /// end, and anything in between becomes a waypoint the router will hit
    /// in order. Two-point walks are point-to-point; loops repeat the start
    /// coord as the final entry.
    let waypoints: [WaypointStop]
    /// Bullet points shown in the detail sheet (e.g. "wooden bridge at 0.5mi",
    /// "sunset view over the lake").
    let highlights: [String]
    /// Optional guidance strings shown under "When to go".
    let bestTime: String?
    let seasonality: String?
    let curatedBy: String?
}

struct WaypointStop: Codable, Hashable {
    let lat: Double
    let lon: Double
    /// Optional note about this specific stop — currently unused in UI, but
    /// preserved in the schema for future "trail notes along the way" UI.
    let note: String?
}

enum DifficultyRating: String, Codable, Hashable {
    case easy, moderate, strenuous

    var label: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .strenuous: return "Strenuous"
        }
    }

    /// RGB triple used to tint the difficulty chip on cards + detail.
    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .easy:      return (0.36, 0.66, 0.34)  // forest green
        case .moderate:  return (0.85, 0.66, 0.15)  // amber
        case .strenuous: return (0.83, 0.38, 0.24)  // terracotta
        }
    }
}
