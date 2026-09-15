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

    /// One week-over-week comparison. Modelled rather than built inline so the
    /// same three can render as columns or as rows without a second copy of
    /// the arithmetic.
    private struct Metric: Identifiable {
        let label: String
        let value: String
        /// Sign of the change. Direction only — `deltaText` carries the number.
        let delta: Int
        let higherIsBetter: Bool
        let deltaText: String

        var id: String { label }

        var isFlat: Bool { delta == 0 }
        var improved: Bool { higherIsBetter ? delta > 0 : delta < 0 }

        var tint: Color {
            if isFlat { return .secondary }
            return improved ? AppColors.success : AppColors.error
        }

        var spokenDelta: String {
            isFlat ? "unchanged from last week" : "\(deltaText) versus last week"
        }
    }

    private var metrics: [Metric] {
        var result: [Metric] = []

        if let score = progress.avgScoreThisWeek, let lastScore = progress.avgScoreLastWeek {
            result.append(Metric(
                label: "Avg Score",
                value: "\(score)",
                delta: score - lastScore,
                higherIsBetter: true,
                deltaText: signed(score - lastScore)
            ))
        }

        if let fillers = progress.fillersPerMinThisWeek,
           let lastFillers = progress.fillersPerMinLastWeek {
            let change = fillers - lastFillers
            result.append(Metric(
                label: "Fillers/min",
                value: String(format: "%.1f", fillers),
                delta: changeDirection(change),
                higherIsBetter: false,
                deltaText: String(format: "%+.1f", change)
            ))
        }

        result.append(Metric(
            label: "Sessions",
            value: "\(progress.sessionsThisWeek)",
            delta: progress.sessionsThisWeek - progress.sessionsLastWeek,
            higherIsBetter: true,
            deltaText: signed(progress.sessionsThisWeek - progress.sessionsLastWeek)
        ))

        return result
    }

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                header

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 0.5)

                // Three columns while they fit, stacked rows when they do not.
                // Three eyebrow labels across a 320pt SE is already tight at
                // the default text size and impossible a couple of Dynamic
                // Type steps up.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(metrics) { metricColumn($0) }
                    }

                    VStack(spacing: 12) {
                        ForEach(metrics) { metricRow($0) }
                    }
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
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

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
            // 28pt of chrome in a 44pt hit box, trailing-aligned so the glyph
            // still sits on the card's inset. No fixed row height: the title
            // has to be free to wrap at accessibility sizes.
            .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget, alignment: .trailing)
            .contentShape(Rectangle())
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Dismiss weekly recap")
        }
    }

    // MARK: - Metrics

    /// Wide layout: value over label over delta, three abreast.
    private func metricColumn(_ metric: Metric) -> some View {
        VStack(spacing: 8) {
            value(metric)
            Text(metric.label).eyebrowStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            deltaPill(metric)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label): \(metric.value), \(metric.spokenDelta)")
    }

    /// Narrow layout: label leading, value and delta trailing.
    private func metricRow(_ metric: Metric) -> some View {
        HStack(spacing: 10) {
            Text(metric.label).eyebrowStyle()
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            value(metric)
            deltaPill(metric)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label): \(metric.value), \(metric.spokenDelta)")
    }

    private func value(_ metric: Metric) -> some View {
        Text(metric.value)
            .font(.statValue)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
    }

    private func deltaPill(_ metric: Metric) -> some View {
        HStack(spacing: 3) {
            if !metric.isFlat {
                Image(systemName: metric.improved ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(metric.isFlat ? "same" : metric.deltaText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(metric.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            Capsule().fill(metric.isFlat ? Color.white.opacity(0.06) : metric.tint.opacity(0.14))
        }
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
