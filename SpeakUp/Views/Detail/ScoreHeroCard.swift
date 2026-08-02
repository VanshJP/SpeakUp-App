import SwiftUI

/// The answer to the question the user opened this screen to ask.
///
/// A score with nothing to compare it against is trivia — 78 means nothing
/// until you know your average is 72. So the number leads, the verdict names
/// the band in words, and the delta supplies the only context that makes the
/// number actionable. Everything else on the page is evidence for this card.
///
/// Compact mode (default for the detail hero) shows number + verdict + delta
/// only. The full subscore radar lives under Breakdown as evidence for “why,”
/// so the above-fold stack stays answer → next action → tabs.
struct ScoreHeroCard: View {
    let score: Int
    /// Rolling average of recent sessions, excluding this one. Nil until it
    /// loads, or when there is no prior session to compare against.
    let personalAverage: Int?
    let axes: [SubscoreRadarChart.Axis]
    /// Nil when there is no meaningful spread (a single axis is both).
    let strongestAxisID: String?
    let weakestAxisID: String?
    let onShowWeights: () -> Void
    /// When false, skip the radar and show a compact number + verdict row.
    /// Breakdown tab hosts the radar when this is false on the hero.
    var showRadar: Bool = true

    private var scoreColor: Color { AppColors.scoreColor(for: score) }

    private var delta: Int? {
        guard let personalAverage else { return nil }
        return score - personalAverage
    }

    private var strongestAxis: SubscoreRadarChart.Axis? {
        strongestAxisID.flatMap { id in axes.first { $0.id == id } }
    }

    private var weakestAxis: SubscoreRadarChart.Axis? {
        weakestAxisID.flatMap { id in axes.first { $0.id == id } }
    }

    /// Radar only when the caller asked for it and there are axes to plot.
    private var showsRadarChart: Bool {
        showRadar && !axes.isEmpty
    }

    var body: some View {
        GlassCard(padding: 16, elevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow

                if showsRadarChart {
                    // Score lives in the middle of the ring — one numeral,
                    // inside the donut it belongs to.
                    SubscoreRadarChart(
                        axes: axes,
                        overallScore: score,
                        emphasizedAxisIDs: (strongestAxisID, weakestAxisID)
                    )
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)

                    verdictLine
                } else {
                    soloScoreRow
                    TickMeter(fraction: Double(score) / 100, color: scoreColor)
                        .frame(height: 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Verdict and delta on one centred line beneath the ring — the context the
    /// number needs, at caption weight so it supports the ring instead of
    /// competing with it.
    private var verdictLine: some View {
        HStack(spacing: 8) {
            Text(AppColors.scoreVerdict(for: score))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(scoreColor)

            deltaLabel
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Subviews

    private var eyebrow: some View {
        HStack {
            Text("Session score")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.7)

            Spacer()

            Button {
                Haptics.light()
                onShowWeights()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Adjust score weights")
        }
    }

    /// Compact hero (and empty-axes fallback): big number + verdict + delta.
    private var soloScoreRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .contentTransition(.numericText(value: Double(score)))
                    .monospacedDigit()

                Text("/100")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(AppColors.scoreVerdict(for: score))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                deltaLabel
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var deltaLabel: some View {
        if let delta {
            // A delta inside ±2 is noise, not progress — calling it out would
            // manufacture a trend from run-to-run variance.
            if abs(delta) <= 2 {
                Text("On par with your average")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(abs(delta)) \(delta > 0 ? "above" : "below") your average")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(delta > 0 ? AppColors.success : AppColors.warning)
            }
        } else {
            Text("Your first scored session")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Strongest/weakest only when the radar (or its callouts) are on this card.
    private var accessibilitySummary: String {
        var parts = ["Session score \(score) out of 100, \(AppColors.scoreVerdict(for: score))"]
        if let delta, abs(delta) > 2 {
            parts.append("\(abs(delta)) points \(delta > 0 ? "above" : "below") your average")
        }
        if showsRadarChart {
            if let strongestAxis { parts.append("strongest \(strongestAxis.label) \(strongestAxis.value)") }
            if let weakestAxis { parts.append("weakest \(weakestAxis.label) \(weakestAxis.value)") }
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    let axes: [SubscoreRadarChart.Axis] = [
        .init(id: "clarity", label: "Clarity", icon: "waveform", value: 88),
        .init(id: "pace", label: "Pace", icon: "speedometer", value: 74),
        .init(id: "fillers", label: "Fillers", icon: "text.badge.minus", value: 52),
        .init(id: "pauses", label: "Pauses", icon: "pause.circle", value: 69),
        .init(id: "vocal", label: "Vocal", icon: "waveform.path.ecg", value: 71),
        .init(id: "delivery", label: "Delivery", icon: "speaker.wave.3", value: 80)
    ]

    return ZStack {
        AppBackground()
        ScrollView {
            VStack(spacing: 16) {
                ScoreHeroCard(
                    score: 78,
                    personalAverage: 72,
                    axes: axes,
                    strongestAxisID: "clarity",
                    weakestAxisID: "fillers",
                    onShowWeights: {},
                    showRadar: false
                )
                ScoreHeroCard(
                    score: 78,
                    personalAverage: 72,
                    axes: axes,
                    strongestAxisID: "clarity",
                    weakestAxisID: "fillers",
                    onShowWeights: {},
                    showRadar: true
                )
                ScoreHeroCard(
                    score: 91,
                    personalAverage: nil,
                    axes: [],
                    strongestAxisID: nil,
                    weakestAxisID: nil,
                    onShowWeights: {}
                )
            }
            .padding()
        }
    }
}
