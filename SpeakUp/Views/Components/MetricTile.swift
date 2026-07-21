import SwiftUI

/// Bevel-style metric tile: caption row (icon + label), a large rounded
/// value with a small unit, and an optional status pill that interprets the
/// number for the user ("On pace", "Clean") so the tile reads as a verdict,
/// not just data. Used in 2-column grids on analysis surfaces.
struct MetricTile: View {
    let icon: String
    let label: String
    let value: String
    var unit: String? = nil
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
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                    Text(label)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())

                    if let unit {
                        Text(unit)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let status {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 5, height: 5)
                        Text(status.text)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(status.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(status.color.opacity(0.12)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit ?? "")\(status.map { ", \($0.text)" } ?? "")")
    }
}

#Preview {
    ZStack {
        AppBackground()
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricTile(icon: "speedometer", label: "Pace", value: "148", unit: "wpm", status: .good("On pace"))
            MetricTile(icon: "exclamationmark.bubble", label: "Fillers", value: "3", status: .caution("A few"))
            MetricTile(icon: "text.word.spacing", label: "Words", value: "412")
            MetricTile(icon: "pause.circle", label: "Pauses", value: "9", status: .good("Strategic"))
        }
        .padding()
    }
}
