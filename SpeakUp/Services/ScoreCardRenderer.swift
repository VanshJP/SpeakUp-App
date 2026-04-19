import SwiftUI

@MainActor
enum ScoreCardRenderer {
    /// Render a branded score card image at @3x resolution.
    static func render(recording: Recording) -> UIImage? {
        guard let analysis = recording.analysis else { return nil }

        let view = ScoreCardView(recording: recording, analysis: analysis)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        return renderer.uiImage
    }
}

// MARK: - Score Card SwiftUI View (rendered to image)
//
// Focused, single-color share card. Emphasises the overall SpeakUp Score and
// three headline metrics from the speech algorithm — Clarity, Pace, Fillers.
// Consistent teal branding and generous whitespace; no rainbow of per-metric
// colors. Rendered at @3x by ScoreCardRenderer.

private struct ScoreCardView: View {
    let recording: Recording
    let analysis: SpeechAnalysis

    private var scoreColor: Color {
        AppColors.scoreColor(for: analysis.speechScore.overall)
    }

    var body: some View {
        VStack(spacing: 36) {
            brandRow
            scoreHero
            metricsRow
            if let prompt = recording.prompt {
                promptCaption(prompt.text)
            }
            footerRow
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 44)
        .frame(width: 400)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
        }
    }

    // MARK: - Sections

    private var brandRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.title3)
                .foregroundStyle(.teal)
            Text("SpeakUp")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text(recording.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var scoreHero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    .frame(width: 168, height: 168)

                Circle()
                    .trim(from: 0, to: Double(analysis.speechScore.overall) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 168, height: 168)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(analysis.speechScore.overall)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("/ 100")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Text("SpeakUp Score")
                .font(.caption.weight(.medium))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 0) {
            ScoreCardMetric(
                label: "Clarity",
                value: "\(analysis.speechScore.subscores.clarity)"
            )
            metricDivider
            ScoreCardMetric(
                label: "Pace",
                value: "\(Int(analysis.wordsPerMinute))",
                unit: "WPM"
            )
            metricDivider
            ScoreCardMetric(
                label: "Fillers",
                value: "\(analysis.totalFillerCount)"
            )
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.75, height: 40)
    }

    private func promptCaption(_ text: String) -> some View {
        Text("\u{201C}\(text)\u{201D}")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 12)
    }

    private var footerRow: some View {
        Text("speakup.app")
            .font(.caption2.weight(.medium))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.3))
    }

    // MARK: - Background

    private var cardBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.04, blue: 0.09),
                    Color(red: 0.02, green: 0.03, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.teal.opacity(0.10), .clear],
                center: UnitPoint(x: 0.5, y: 0.28),
                startRadius: 20,
                endRadius: 260
            )
        }
    }
}

// MARK: - Score Card Metric

private struct ScoreCardMetric: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if let unit {
                    Text(unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            Text(label)
                .font(.caption.weight(.medium))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}
