import SwiftUI

/// A practice exercise in a browsable list.
///
/// Replaces two byte-identical implementations (`WarmUpListView` and
/// `ConfidenceToolsView` had independently written the same icon-in-a-circle
/// row, differing only in trailing glyph and duration unit).
///
/// The leading visual is the point of it. Every list in this app used to lead
/// with an SF Symbol in a tinted circle, which meant a 30-second tongue twister
/// and a 10-minute visualization presented identically — the row told you
/// nothing until you read it. Here the icon sits inside an arc showing this
/// item's length against the longest in the list, so a column of these scans as
/// a duration histogram. Same information the caption always carried, moved
/// somewhere the eye reads before the text.
struct PracticeItemRow: View {
    enum Accessory {
        case chevron
        case play
    }

    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    /// This item's length as a share of the longest in the visible set, 0–1.
    let durationFraction: Double
    /// Short enough to sit inside a 46pt dial — "45s", "3m", "≈2 min". Detail
    /// that does not fit goes in `tag`; the dial used to be handed
    /// "3m · 4 steps" and rendered it at 8pt, which nobody could read.
    let durationLabel: String
    /// Optional qualifier chip: what the session shows while it runs, how many
    /// steps it has, how hard the passage is.
    var tag: String?
    var accessory: Accessory = .play
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(spacing: 14) {
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
                            Text(tag)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background { Capsule().fill(tint.opacity(0.16)) }
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
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(tint)
                    }
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, durationLabel, tag, subtitle].compactMap { $0 }.joined(separator: ". "))
    }

    private var durationDial: some View {
        ZStack {
            RingProgress(progress: durationFraction, color: tint, lineWidth: 3)
                .frame(width: 46, height: 46)

            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)

                Text(durationLabel)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension PracticeItemRow {
    /// Longest item in a set, used as the denominator for every row's arc.
    /// Guards against a zero divisor and against a single-item list rendering
    /// one lonely full circle.
    static func fraction(_ value: Double, longest: Double) -> Double {
        guard longest > 0 else { return 0 }
        return min(1, max(0.12, value / longest))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            PracticeItemRow(
                title: "Lip Trills",
                subtitle: "Loosen the lips and jaw before speaking.",
                icon: "wind",
                tint: AppColors.toolWarmUp,
                durationFraction: PracticeItemRow.fraction(30, longest: 180),
                durationLabel: "30s",
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
