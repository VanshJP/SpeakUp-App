import SwiftUI

/// The type scale the app was already improvising across 227 hardcoded
/// `.system(size:)` calls.
///
/// Two families, and the split is deliberate:
///
/// **Numerals are fixed.** A hero score is a graphic element, not running text —
/// a 68pt numeral scaled to AX5 would be wider than the screen. These keep a
/// fixed size and rely on the accessibility label for non-visual users, which is
/// the pattern `ScoreHeroCard` already established.
///
/// **Everything else scales.** Text tokens are built on `Font.TextStyle`, so
/// Dynamic Type works without a `@ScaledMetric` at every call site.
extension Font {

    // MARK: - Numerals (fixed by design)

    /// The one hero numeral on a screen. Never two.
    static let displayNumeral = Font.system(size: 68, weight: .bold, design: .rounded)

    /// Big number in a metric tile or gauge.
    static let metricValue = Font.system(size: 21, weight: .bold, design: .rounded)

    /// Number inside a ring or a compact stat pair.
    static let statValue = Font.system(size: 17, weight: .bold, design: .rounded)

    // MARK: - Text (scales with Dynamic Type)

    /// Small-caps section label. Prefer `.eyebrowStyle()`, which also applies
    /// the casing, tracking, and color this token is always paired with.
    static let eyebrow = Font.system(.caption2).weight(.semibold)
}

extension View {
    /// Uppercase, tracked, secondary section label. This exact four-line
    /// combination was written out identically in `ScoreHeroCard` and
    /// `RingStatsView` before it had a name.
    func eyebrowStyle() -> some View {
        self.font(.eyebrow)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.7)
    }
}
