import SwiftUI
import UIKit

@MainActor
enum ScoreCardRenderer {
    /// Render a branded score card image at @3x resolution.
    ///
    /// The prompt or story caption is off unless the caller asks for it. What
    /// someone was told to talk about can be a job interview question or the
    /// title of a personal story, and a share card is the one place in this app
    /// where private practice becomes public.
    static func render(recording: Recording, includePromptText: Bool = false) -> UIImage? {
        guard let analysis = recording.analysis else { return nil }

        let view = ScoreCardView(
            recording: recording,
            analysis: analysis,
            includePromptText: includePromptText
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        return renderer.uiImage
    }

    /// The caption text a card *could* carry, or nil when the session has none.
    /// Views use this to decide whether the include-prompt choice is worth
    /// offering at all.
    static func promptCaption(for recording: Recording) -> String? {
        recording.prompt?.text ?? recording.storyTitle
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
    let includePromptText: Bool

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

                if includePromptText, let text = ScoreCardRenderer.promptCaption(for: recording) {
                    promptCaption(text)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 44)
        }
        .frame(width: 400)
    }

    private var brandRow: some View {
        HStack(spacing: 10) {
            Image("BigTalkOrb")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text("Big Talk")
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


}
