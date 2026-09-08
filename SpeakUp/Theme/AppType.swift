import SwiftUI

/// The type scale the app was already improvising across 227 hardcoded
/// `.system(size:)` calls.
///
extension Font {

    // MARK: - Numerals (fixed by design)
    //
    // Tabular figures on every changing value so timers, scores, and streak
    // chips do not shift layout as digits update.

    /// The one hero numeral on a screen. Never two.
    static let displayNumeral = Font.system(size: 68, weight: .bold, design: .rounded).monospacedDigit()

    static let metricValue = Font.system(size: 21, weight: .bold, design: .rounded).monospacedDigit()

    static let statValue = Font.system(size: 17, weight: .bold, design: .rounded).monospacedDigit()

    // MARK: - Text (scales with Dynamic Type)

    static let eyebrow = Font.system(.caption2).weight(.semibold)
}

extension View {
    func eyebrowStyle() -> some View {
        self.font(.eyebrow)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.7)
    }
}
