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
// Mirrors recording detail: context strip (prompt as the title) sitting above
// the same hero body the user just saw. Materials do not survive ImageRenderer,
// so the panel is an opaque stand-in for GlassCard rather than a second layout.

private struct ScoreCardView: View {
    let recording: Recording
    let analysis: SpeechAnalysis
    let includePromptText: Bool

    private var axes: [SubscoreRadarChart.Axis] {
        SubscoreRadarChart.Axis.from(
            subscores: analysis.speechScore.subscores,
            isPromptRelevance: analysis.promptRelevanceScore != nil && recording.prompt != nil
        )
    }

    private var emphasis: (strongest: String?, weakest: String?) {
        SubscoreRadarChart.Axis.emphasisIDs(in: axes)
    }

    private var score: Int { analysis.speechScore.overall }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            VStack(alignment: .leading, spacing: 20) {
                brandRow
                contextBlock
                heroPanel
                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
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

    /// Same information architecture as `DetailContextStrip`: meta line, then
    /// the prompt as the only large text.
    private var contextBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: contextIcon)
                    .font(.system(size: 10, weight: .semibold))
                Text(contextMetaLine)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.45))

            if includePromptText, let text = ScoreCardRenderer.promptCaption(for: recording) {
                Text(text)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroPanel: some View {
        ScoreHeroBody(
            score: score,
            axes: axes,
            strongestAxisID: emphasis.strongest,
            weakestAxisID: emphasis.weakest,
            showsWeightsButton: false,
            showsPersonalContext: false,
            animate: false,
            interactive: false,
            radarHeight: 260
        )
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColors.cardStroke, lineWidth: 0.5)
                }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: includePromptText ? "bolt.fill" : "mic.fill")
                .font(.caption.weight(.semibold))
            Text(includePromptText ? "Think you can beat this?" : "Practised on device with Big Talk")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.45))
        .frame(maxWidth: .infinity)
    }

    private var contextIcon: String {
        if recording.storyId != nil { return "book.pages" }
        if let category = recording.prompt?.category {
            return PromptCategory(rawValue: category)?.iconName ?? "text.bubble"
        }
        return "waveform"
    }

    private var contextMetaLine: String {
        var parts: [String] = []
        if recording.storyId != nil {
            parts.append(recording.storyTitle ?? "Story Practice")
        } else if let category = recording.prompt?.category {
            parts.append(PromptCategory(rawValue: category)?.shortName ?? category)
        } else {
            parts.append("Free Practice")
        }
        if let difficulty = recording.prompt?.difficulty {
            parts.append(difficulty.displayName)
        }
        parts.append(recording.formattedDuration)
        return parts.joined(separator: " · ")
    }
}
