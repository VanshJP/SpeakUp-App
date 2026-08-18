import SwiftUI

/// A number over its label — the smallest unit of reported data in the app.
///
/// Written out inline in twelve places (score weights, before/after replay,
/// lesson detail, practice results, streak detail, the analyzing skeleton,
/// the comparison view twice) as the same
/// `VStack(spacing: 4) { bold value; caption label }`.
struct StatPair: View {
    let value: String
    let label: String
    var valueColor: Color = .white
    var valueFont: Font = .statValue
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(value)
                .font(valueFont)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

#Preview {
    HStack(spacing: 20) {
        StatPair(value: "84", label: "Score", valueColor: AppColors.scoreHigh)
        StatPair(value: "142", label: "WPM")
        StatPair(value: "3:20", label: "Total time")
    }
    .padding(40)
    .background(AppBackground())
}
