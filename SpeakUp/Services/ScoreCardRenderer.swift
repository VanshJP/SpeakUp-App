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

    var body: some View {
        ZStack {
            AppBackground(style: .primary)

            VStack(spacing: 36) {
                brandRow

                let axes = SubscoreRadarChart.Axis.from(
                    subscores: analysis.speechScore.subscores,
                    isPromptRelevance: analysis.promptRelevanceScore != nil && recording.prompt != nil
                )

                SubscoreRadarChart(
                    axes: axes,
                    overallScore: analysis.speechScore.overall,
                    animate: false
                )
                .frame(height: 300)

                if let text = recording.prompt?.text ?? recording.storyTitle {
                    promptCaption(text)
                }

                footerRow
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 44)
        }
        .frame(width: 400)
    }

    private var brandRow: some View {
        HStack(spacing: 10) {
            Image("SpeakUpOrb")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text("SpeakUp")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text(recording.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func promptCaption(_ text: String) -> some View {
        Text("\u{201C}\(text)\u{201D}")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 12)
    }

    private var footerRow: some View {
        Text("speakup.app")
            .font(.caption2.weight(.medium))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.3))
    }

}
