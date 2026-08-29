import SwiftUI

/// "This week vs last" recap — appears once per week when both weeks have
/// enough sessions to compare. Dismissing hides it until next week.
/// Color lives only in the deltas (the data); everything else stays neutral.
struct WeeklyRecapCard: View {
    let progress: WeeklyProgressData
    let onDismiss: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("This Week vs Last")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        Haptics.light()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, height: 28)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel("Dismiss weekly recap")
                }

                HStack(spacing: 12) {
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
        }
        // Keep the dismiss button independently reachable to VoiceOver.
        .accessibilityElement(children: .contain)
    }

    // MARK: - Subviews

    private func recapMetric(
        label: String,
        value: String,
        delta: Int,
        higherIsBetter: Bool,
        deltaText: String
    ) -> some View {
        let improved = higherIsBetter ? delta > 0 : delta < 0
        let flat = delta == 0
        let color: Color = flat ? .secondary : (improved ? AppColors.success : AppColors.error)

        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            HStack(spacing: 2) {
                if !flat {
                    Image(systemName: improved ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(flat ? "same" : deltaText)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    /// Collapses a fractional fillers/min change to a comparison direction,
    /// treating tiny drift (< 0.05) as flat.
    private func changeDirection(_ change: Double) -> Int {
        if abs(change) < 0.05 { return 0 }
        return change > 0 ? 1 : -1
    }
}
