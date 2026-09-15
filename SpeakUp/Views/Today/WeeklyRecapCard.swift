import SwiftUI

/// Week-over-week delta strip on Today.
///
/// Styling deliberately mirrors `RingStatsView`, the card it sits directly
/// under: same `GlassCard` padding, same eyebrow labels, same `.statValue`
/// numerals, same hairline rule under the header. It had drifted onto its own
/// ad-hoc type scale, which read as a plain grey box wedged between two
/// finished cards.
struct WeeklyRecapCard: View {
    let progress: WeeklyProgressData
    let onDismiss: () -> Void

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                header

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 0.5)

                HStack(alignment: .top, spacing: 0) {
                    if let score = progress.avgScoreThisWeek, let lastScore = progress.avgScoreLastWeek {
                        recapMetric(
                            label: "Avg Score",
                            value: "\(score)",
                            delta: score - lastScore,
                            higherIsBetter: true,
                            deltaText: signed(score - lastScore)
                        )
                    }

                    if let fillers = progress.fillersPerMinThisWeek,
                       let lastFillers = progress.fillersPerMinLastWeek {
                        let change = fillers - lastFillers
                        recapMetric(
                            label: "Fillers/min",
                            value: String(format: "%.1f", fillers),
                            delta: changeDirection(change),
                            higherIsBetter: false,
                            deltaText: String(format: "%+.1f", change)
                        )
                    }

                    recapMetric(
                        label: "Sessions",
                        value: "\(progress.sessionsThisWeek)",
                        delta: progress.sessionsThisWeek - progress.sessionsLastWeek,
                        higherIsBetter: true,
                        deltaText: signed(progress.sessionsThisWeek - progress.sessionsLastWeek)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Keep the dismiss button independently reachable to VoiceOver.
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("This Week vs Last")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            Button {
                Haptics.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.06))
                            .overlay { Circle().stroke(AppColors.cardStroke, lineWidth: 0.5) }
                    }
            }
            .frame(width: 44, height: 44, alignment: .trailing)
            .contentShape(Rectangle())
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Dismiss weekly recap")
        }
        // The 44pt tap target overhangs the card's padding; pull the row back
        // so the glyph still optically lines up with the card edge.
        .padding(.trailing, -8)
        .frame(height: 28)
    }

    // MARK: - Metrics

    private func recapMetric(
        label: String,
        value: String,
        delta: Int,
        higherIsBetter: Bool,
        deltaText: String
    ) -> some View {
        let improved = higherIsBetter ? delta > 0 : delta < 0
        let flat = delta == 0
        let tint: Color = flat ? .secondary : (improved ? AppColors.success : AppColors.error)
        let spokenDelta: String = flat
            ? "unchanged from last week"
            : "\(deltaText) versus last week"

        return VStack(spacing: 8) {
            Text(value)
                .font(.statValue)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Text(label).eyebrowStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 3) {
                if !flat {
                    Image(systemName: improved ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(flat ? "same" : deltaText)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(flat ? Color.white.opacity(0.06) : tint.opacity(0.14))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value), \(spokenDelta)")
    }

    // MARK: - Helpers

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func changeDirection(_ change: Double) -> Int {
        if abs(change) < 0.05 { return 0 }
        return change > 0 ? 1 : -1
    }
}
