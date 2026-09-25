import SwiftUI

/// One exercise, drill or passage, as a row on its `FocusSection`'s
/// `GlassRowGroup`.
///
/// It used to be a `GlassCard` of its own, so a tool page was a column of
/// separate plates - forty of them across the four tools - where a list of rows
/// belongs on one (ui-design-system checklist 9). The row draws no surface now:
/// it pads itself and lights edge to edge on press (`RowPressStyle`), and the
/// group owns the plate, the hairlines and the clip.
struct PracticeItemRow: View {
    enum Accessory {
        case chevron
        case play
    }

    /// Row padding, dial and gap: where the group's hairlines start, so they
    /// run under the text rather than through the dial.
    static let dividerInset: CGFloat = horizontalPadding + dialDiameter + contentSpacing

    private static let horizontalPadding: CGFloat = 14
    private static let dialDiameter: CGFloat = 46
    private static let contentSpacing: CGFloat = 14

    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let durationFraction: Double
    let durationLabel: String
    var tag: String?
    var accessory: Accessory = .play
    let action: () -> Void

    /// The dial's cost label. It scales with Dynamic Type from its 8pt
    /// default, and shrinks back rather than spill out of the fixed ring.
    @ScaledMetric(relativeTo: .caption2) private var dialLabelSize: CGFloat = 8

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.contentSpacing) {
                durationDial

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let tag {
                        StatusPill(text: tag, color: tint)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)

                switch accessory {
                case .chevron:
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                case .play:
                    // Neutral, like every other in-card action: the row's
                    // colour is its identity and already lives in the dial
                    // and the tag. A filled play disc in that colour made
                    // the affordance the loudest thing on every row.
                    // Painted, not glass - this sits on the group's plate
                    // (rule 13b).
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 32, height: 32)
                        .background { Circle().fill(Color.white.opacity(0.10)) }
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                }
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, durationLabel, tag, subtitle].compactMap { $0 }.joined(separator: ". "))
    }

    private var durationDial: some View {
        ZStack {
            RingProgress(progress: durationFraction, color: tint, lineWidth: 3)
                .frame(width: Self.dialDiameter, height: Self.dialDiameter)

            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)

                Text(durationLabel)
                    .font(.system(size: dialLabelSize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: Self.dialDiameter - 10)
        }
    }
}

extension PracticeItemRow {
    static func fraction(_ value: Double, longest: Double) -> Double {
        guard longest > 0 else { return 0 }
        return min(1, max(0.12, value / longest))
    }
}

#Preview {
    ScrollView {
        GlassRowGroup(dividerInset: PracticeItemRow.dividerInset) {
            PracticeItemRow(
                title: "Lip Trills",
                subtitle: "Loosen the lips and jaw before speaking.",
                icon: "wind",
                tint: AppColors.toolWarmUp,
                durationFraction: PracticeItemRow.fraction(30, longest: 180),
                durationLabel: "30s",
                tag: "Vocal",
                accessory: .play
            ) {}

            PracticeItemRow(
                title: "Box Breathing",
                subtitle: "Four counts in, hold, out, hold. Settles the nerves.",
                icon: "lungs.fill",
                tint: AppColors.toolCalm,
                durationFraction: PracticeItemRow.fraction(180, longest: 180),
                durationLabel: "3m"
            ) {}
        }
        .padding()
    }
    .background(AppBackground())
}
