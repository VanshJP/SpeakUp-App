import SwiftUI

// MARK: - MetricExplainerSheet

/// Modal describing a single subscore axis from the `SubscoreRadarChart`.
/// Presents the score value, a band label, what the metric measures, and
/// how it is calculated. Text is sourced verbatim from `ScoreWeightsView` so
/// the explainer matches the in-Settings breakdown word-for-word.
struct MetricExplainerSheet: View {
    let axis: SubscoreRadarChart.Axis

    private var description: (measures: String, howCalculated: String) {
        SubscoreRadarChart.description(for: axis.id)
            ?? ("No description available for this metric.", "")
    }

    private var bandLabel: String {
        switch axis.value {
        case 80...: return "Great"
        case 60..<80: return "Solid"
        case 40..<60: return "Developing"
        default: return "Needs work"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                headerCard
                measuresCard
                if !description.howCalculated.isEmpty {
                    calculationCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            AppBackground(style: .subtle)
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        let color = AppColors.scoreColor(for: axis.value)
        return GlassCard(tint: AppColors.glassTintPrimary) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(axis.value) / 100)
                        .stroke(
                            AppColors.scoreGradient(for: axis.value),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(axis.value)")
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                }
                .frame(width: 110, height: 110)

                VStack(spacing: 4) {
                    Text(axis.label)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(bandLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }

    private var measuresCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("What this measures")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Text(description.measures)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var calculationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("How it's calculated")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Text(description.howCalculated)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Metric Descriptions

extension SubscoreRadarChart {
    /// Canonical descriptions keyed by `Axis.id` values produced in
    /// `Axis.from(subscores:isPromptRelevance:)`. Text is mirrored from
    /// `ScoreWeightsView.SubscoreDescription` to keep a single source of truth.
    static func description(for id: String) -> (measures: String, howCalculated: String)? {
        switch id {
        case "clarity":
            return ("How clearly you articulate words. Clear pronunciation makes your message easier to understand.",
                    "Combines voiced frame ratio (articulation quality), word duration consistency, ASR word confidence, hedge word penalty, and an authority score from language analysis.")
        case "pace":
            return ("Speaking speed and fluency. Optimal pace is conversational — not rushed or dragging.",
                    "Gaussian comparison to your target WPM (wider tolerance ±30 WPM), with optional rate variation (18%) and fluency signals (14%) blended in when available.")
        case "fillers":
            return ("How often you use filler words like 'um', 'uh', 'like', and 'you know'.",
                    "Uses a gentle logarithmic curve: occasional fillers (under 3%) barely affect the score, while frequent use lowers it progressively.")
        case "pauses":
            return ("Quality and placement of your pauses. Strategic pauses enhance speeches; awkward silences hurt them.",
                    "Evaluates pause length, placement between ideas, and penalizes hesitation pauses or rushing without pauses.")
        case "vocal":
            return ("How dynamically you vary your pitch, volume, and speaking rate throughout your speech.",
                    "Combines pitch variation, volume dynamics, rate variation, and pitch-energy correlation scores.")
        case "delivery":
            return ("Your overall energy, emphasis on key points, and presentation arc from opening to close.",
                    "Weighs energy level, volume variation, content density, emphasis distribution, energy arc shape, and language engagement signals.")
        case "vocab":
            return ("Word choice sophistication and diversity. Using varied, precise words improves this score.",
                    "Blends MATTR (Moving Average Type-Token Ratio, the academic standard for lexical diversity), word rarity via on-device language model, repetition penalty, and word length diversity. MATTR is length-invariant so longer speeches are not penalized.")
        case "structure":
            return ("Sentence organization, flow, and rhetorical quality of your speech.",
                    "Evaluates sentence variety, completeness, rhetorical devices, transition usage, plus conciseness and audience engagement quality.")
        case "relevance":
            return ("How well your speech stays on topic (with a prompt) or maintains internal coherence (free practice).",
                    "Uses keyword overlap, semantic similarity, and sentence alignment to measure topic relevance or coherence.")
        default:
            return nil
        }
    }
}
