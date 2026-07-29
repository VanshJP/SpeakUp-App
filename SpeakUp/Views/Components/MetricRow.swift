import SwiftUI

/// One measured number, as a full-width row.
///
/// This replaces a 2×2 grid of tiles that each stacked four things vertically —
/// label, value, baseline, verdict pill — in a narrow column, leaving the whole
/// right half of every tile empty. Four short stacks in tall boxes used more
/// height than the numbers deserved and less width than they had.
///
/// As rows: the label and its verdict read left, the value and its baseline
/// right-align into a shared column, so the numbers line up down the card and
/// the eye can compare them without re-scanning. Same information, roughly half
/// the height, and no dead space.
struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    var unit: String? = nil
    /// What this number usually looks like for this user — "vs 132 avg".
    /// A metric with no baseline is trivia: 148 wpm only means something once
    /// you know you normally run 132. Nil until enough history exists.
    var baseline: String? = nil
    var status: Status? = nil

    struct Status {
        let text: String
        let color: Color

        static func good(_ text: String) -> Status { Status(text: text, color: AppColors.success) }
        static func caution(_ text: String) -> Status { Status(text: text, color: AppColors.warning) }
        static func bad(_ text: String) -> Status { Status(text: text, color: AppColors.error) }
        static func neutral(_ text: String) -> Status { Status(text: text, color: AppColors.info) }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let status {
                StatusPill(text: status.text, color: status.color, glyph: .dot)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.metricValue)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .monospacedDigit()

                    if let unit {
                        Text(unit)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let baseline {
                    Text(baseline)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(label): \(value) \(unit ?? "")"
                + (baseline.map { ", \($0)" } ?? "")
                + (status.map { ", \($0.text)" } ?? "")
        )
    }
}

/// Groups `MetricRow`s into one card with hairline separators, so a set of
/// measurements reads as a single stat sheet rather than four floating boxes.
struct MetricRowGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 10) {
                content
            }
        }
    }
}

/// Hairline between rows. Its own view so callers read as a list of rows.
struct MetricRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 0.5)
    }
}

#Preview {
    ZStack {
        AppBackground()
        MetricRowGroup {
            MetricRow(icon: "speedometer", label: "Pace", value: "148", unit: "wpm",
                      baseline: "vs 132 avg", status: .good("On pace"))
            MetricRowDivider()
            MetricRow(icon: "exclamationmark.bubble", label: "Fillers", value: "3",
                      baseline: "vs 7 avg", status: .caution("A few"))
            MetricRowDivider()
            MetricRow(icon: "text.word.spacing", label: "Words", value: "412",
                      baseline: "vs 380 avg", status: .good("Full"))
            MetricRowDivider()
            MetricRow(icon: "pause.circle", label: "Pauses", value: "9",
                      baseline: "vs 9 avg", status: .good("Strategic"))
        }
        .padding()
    }
}
