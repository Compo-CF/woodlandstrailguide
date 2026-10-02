import SwiftUI

/// The typographic half of the design system — `Natural` (NaturalPalette)
/// owns color, this owns type and the metrics that go with it.
///
/// The app previously used the system font everywhere. SF is excellent and
/// deliberately invisible, which is the problem: it signals nothing, so a
/// carefully chosen palette still reads as stock. Pairing a display face
/// with SF for body is the cheapest change that makes an app look authored.
///
/// Display face is **Fraunces** (SIL Open Font License 1.1 — free to embed
/// and ship). It's a warm old-style serif with a slightly rustic cut, which
/// lands close to park wayfinding and field-guide plates rather than generic
/// app chrome. Body text stays on SF, which is more legible at small sizes
/// than any serif and is what the platform's users already read fluently.
///
/// Rules of thumb for applying this:
///   - Display: numbers that matter (distance, elevation), screen and sheet
///     titles, achievement names. Things a sign would say.
///   - SF: everything the user reads in sentences, every control label.
///   - Never set the display face below ~15pt; Fraunces' contrast gets
///     fragile and it stops being more legible than SF.
enum NaturalType {

    // PostScript names, not filenames — this is what CoreText registers and
    // what Font.custom resolves. Taken from each TTF's name table (ID 6)
    // rather than guessed from the file name, because Google Fonts' static
    // instances name themselves inconsistently: two of these three report
    // their weight in the *family* name and call the subfamily "Regular".
    private static let medium   = "Fraunces-Medium"
    private static let semibold = "Fraunces-SemiBold"
    private static let bold     = "Fraunces-Bold"

    enum DisplayWeight {
        case medium, semibold, bold

        var postScriptName: String {
            switch self {
            case .medium:   return NaturalType.medium
            case .semibold: return NaturalType.semibold
            case .bold:     return NaturalType.bold
            }
        }
    }

    /// A display-face font that still honors Dynamic Type.
    ///
    /// `relativeTo:` is the load-bearing argument. `Font.custom(_:size:)`
    /// without it produces a fixed-size font that ignores the user's text
    /// size entirely — both an accessibility failure and exactly the kind of
    /// detail that separates a designed app from a styled one.
    static func display(_ size: CGFloat,
                        weight: DisplayWeight = .semibold,
                        relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: textStyle)
    }

    // MARK: - Semantic styles
    //
    // Prefer these over calling display(_:) with a raw size. Sizes chosen
    // once, here, is what keeps a type system a system.

    /// Big numerals — route distance, elevation totals, walk summaries.
    /// The one place the face should be unmistakable.
    static let hero = display(44, weight: .bold, relativeTo: .largeTitle)

    /// Sheet and screen titles.
    static let title = display(24, weight: .semibold, relativeTo: .title2)

    /// Card headings and achievement names.
    static let heading = display(18, weight: .semibold, relativeTo: .headline)

    /// Inline emphasis that should still feel like the display face —
    /// segment distances, stat values in the trip log.
    static let statValue = display(17, weight: .medium, relativeTo: .body)

    // MARK: - Metrics
    //
    // Corner radius and elevation were being chosen per call site, which is
    // why surfaces that should feel like siblings don't. One scale, used
    // everywhere, is most of what reads as "designed".

    enum Metrics {
        /// Chips, small controls.
        static let radiusSmall: CGFloat = 10
        /// Buttons, inline cards.
        static let radiusMedium: CGFloat = 14
        /// Sheets and the floating route card.
        static let radiusLarge: CGFloat = 22

        /// Surfaces resting on another surface.
        static let shadowResting = (color: Color.black.opacity(0.08),
                                    radius: CGFloat(6),
                                    y: CGFloat(2))
        /// Surfaces floating over the map, which need to separate from busy,
        /// high-contrast tiles.
        static let shadowFloating = (color: Color.black.opacity(0.18),
                                     radius: CGFloat(14),
                                     y: CGFloat(5))
    }
}

extension View {
    /// Floating-surface elevation, applied consistently.
    func naturalFloatingShadow() -> some View {
        let s = NaturalType.Metrics.shadowFloating
        return shadow(color: s.color, radius: s.radius, y: s.y)
    }

    /// Resting-surface elevation, applied consistently.
    func naturalRestingShadow() -> some View {
        let s = NaturalType.Metrics.shadowResting
        return shadow(color: s.color, radius: s.radius, y: s.y)
    }
}
