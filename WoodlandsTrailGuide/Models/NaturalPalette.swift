import SwiftUI
import UIKit

/// Warm, earthy palette pulled from the app icon — cream paths against deep
/// forest greens. Every color is dynamic so dark mode flips to a deeper-forest
/// variant of the same hue family, not to a flat system gray.
///
/// Used by the floating route card, chips, and map pins. Anywhere the iOS
/// system colors would have produced a bone-stock gray, we reach for these
/// instead so the app feels like it belongs to a trail in the woods.
enum Natural {

    // MARK: - Surfaces

    /// Floating-card background. Light: warm cream. Dark: deep forest.
    /// Slight translucency in both modes so the map shows through gently.
    static let cardBg = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.085, green: 0.135, blue: 0.105, alpha: 0.92)
            : UIColor(red: 0.965, green: 0.930, blue: 0.842, alpha: 0.94)
    })

    /// Pill/chip background (resting on a card).
    static let chipBg = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.135, green: 0.205, blue: 0.165, alpha: 1.0)
            : UIColor(red: 0.918, green: 0.872, blue: 0.768, alpha: 1.0)
    })

    /// Map-control buttons (directions, map style) sitting on the map surface.
    /// Slightly cooler / cleaner than `cardBg` so they read as controls.
    static let buttonBg = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.115, green: 0.175, blue: 0.135, alpha: 0.96)
            : UIColor(red: 0.985, green: 0.965, blue: 0.910, alpha: 0.96)
    })

    // MARK: - Strokes / borders

    static let hairline = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.08)
            : UIColor(red: 0.30, green: 0.26, blue: 0.18, alpha: 0.13)
    })

    // MARK: - Ink

    /// Primary text on cream cards.
    static let ink = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.90, blue: 0.79, alpha: 1.0)
            : UIColor(red: 0.165, green: 0.235, blue: 0.185, alpha: 1.0)
    })

    /// Supporting text on cream cards.
    static let inkMuted = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.60, blue: 0.50, alpha: 1.0)
            : UIColor(red: 0.41, green: 0.39, blue: 0.30, alpha: 1.0)
    })

    // MARK: - Accents

    /// Pathway green — matches the trail polyline color.
    static let forest = Color(red: 0.13, green: 0.55, blue: 0.27)

    /// Route accent. A softened terracotta, calmer than pure orange but
    /// still bold enough to read on top of the green trail network.
    static let route = Color(red: 0.875, green: 0.445, blue: 0.165)
    static let routeUI = UIColor(red: 0.875, green: 0.445, blue: 0.165, alpha: 1.0)

    /// Start/end waypoint pins. Forest green and a clay red — less neon
    /// than systemGreen/systemRed against the calmer base.
    static let startPinUI = UIColor(red: 0.18, green: 0.55, blue: 0.30, alpha: 1.0)
    static let endPinUI   = UIColor(red: 0.770, green: 0.290, blue: 0.250, alpha: 1.0)

    /// Off-white used inside waypoint and POI pin rings. Slightly warm so
    /// the markers don't look stark against the cream-leaning UI.
    static let pinRingUI = UIColor(red: 0.985, green: 0.970, blue: 0.935, alpha: 1.0)
}
