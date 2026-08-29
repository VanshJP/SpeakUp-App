import SwiftUI

/// The answer to the question the user opened this screen to ask.
///
/// A score with nothing to compare it against is trivia — 78 means nothing
/// until you know your average is 72. So the number leads, the verdict names
/// the band in words, and the delta supplies the only context that makes the
/// number actionable. Everything else on the page is evidence for this card.
///
/// The full subscore breakdown rides along as a radar directly under the
/// number: seeing every axis at once is what makes the composite score legible,
/// and the strongest/weakest callouts live on the chart itself rather than as a
/// separate labeled row.
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

    var body: some View {
        GlassCard(padding: 16, elevated: true) {
            ScoreHeroBody(
                score: score,
                axes: axes,
                strongestAxisID: strongestAxisID,
                weakestAxisID: weakestAxisID,
                personalAverage: personalAverage,
                showsWeightsButton: true,
                showsPersonalContext: true,
                animate: true,
                interactive: true,
                onShowWeights: onShowWeights
            )
        }
        // The weights button is a real child action; `.combine` swallowed it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var strongestAxis: SubscoreRadarChart.Axis? {
        strongestAxisID.flatMap { id in axes.first { $0.id == id } }
    }

    private var weakestAxis: SubscoreRadarChart.Axis? {
        weakestAxisID.flatMap { id in axes.first { $0.id == id } }
    }

    /// The radar carries strongest/weakest visually, so VoiceOver has to say it
    /// here or that information disappears entirely for non-visual users.
    private var accessibilitySummary: String {
        var parts = ["Session score \(score) out of 100, \(AppColors.scoreVerdict(for: score))"]
        if let personalAverage {
            let delta = score - personalAverage
            if abs(delta) > 2 {
                parts.append("\(abs(delta)) points \(delta > 0 ? "above" : "below") your average")
            }
        }
        if let strongestAxis { parts.append("strongest \(strongestAxis.label) \(strongestAxis.value)") }
        if let weakestAxis { parts.append("weakest \(weakestAxis.label) \(weakestAxis.value)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Shared body

/// Innards of the in-app hero and the share card. Sharing a screenshot of a
/// different layout than the one the user just celebrated is how the "aha"
/// dies in the share sheet.
struct ScoreHeroBody: View {
    let score: Int
    let axes: [SubscoreRadarChart.Axis]
    var strongestAxisID: String? = nil
    var weakestAxisID: String? = nil
    var personalAverage: Int? = nil
    var showsWeightsButton: Bool = true
    /// Personal average is for the owner. A share card that tells a friend
    /// they are "5 above your average" is talking to the wrong person.
    var showsPersonalContext: Bool = true
    var animate: Bool = true
    var interactive: Bool = true
    var radarHeight: CGFloat = 260
    var onShowWeights: () -> Void = {}

    private var scoreColor: Color { AppColors.scoreColor(for: score) }

    private var delta: Int? {
        guard showsPersonalContext, let personalAverage else { return nil }
        return score - personalAverage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow

            if axes.isEmpty {
                soloScoreRow
                TickMeter(fraction: Double(score) / 100, color: scoreColor)
                    .frame(height: 18)
            } else {
                SubscoreRadarChart(
                    axes: axes,
                    overallScore: score,
                    animate: animate,
                    emphasizedAxisIDs: (strongestAxisID, weakestAxisID),
                    interactive: interactive
                )
                .frame(height: radarHeight)
                .frame(maxWidth: .infinity)

                verdictLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Verdict and (optionally) delta on one centred line beneath the ring.
    private var verdictLine: some View {
        HStack(spacing: 8) {
            Text(AppColors.scoreVerdict(for: score))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(scoreColor)

            if showsPersonalContext {
                deltaLabel
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var eyebrow: some View {
        HStack {
            Text("Session score")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.7)

            Spacer()

            if showsWeightsButton {
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
    }

    /// Only used when there is no breakdown to anchor the number.
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

                if showsPersonalContext {
                    deltaLabel
                }
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
        } else if showsPersonalContext {
            Text("Your first scored session")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                    onShowWeights: {}
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
