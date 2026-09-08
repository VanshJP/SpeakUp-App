import SwiftUI
import UIKit

@MainActor
enum ScoreCardRenderer {
    static func render(
        recording: Recording,
        includePromptText: Bool = false,
        theme: ScoreCardTheme = .midnight
    ) -> UIImage? {
        guard let analysis = recording.analysis else { return nil }

        let view = ScoreCardView(
            recording: recording,
            analysis: analysis,
            includePromptText: includePromptText,
            theme: theme
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        return renderer.uiImage
    }

    static func promptCaption(for recording: Recording) -> String? {
        recording.prompt?.text ?? recording.storyTitle
    }
}

// MARK: - Score Card Theme

enum ScoreCardTheme: Int, Codable, CaseIterable, Identifiable {
    case midnight = 0
    case aurora = 1
    case slate = 2
    case spotlight = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .midnight: return "Midnight"
        case .aurora: return "Aurora"
        case .slate: return "Slate"
        case .spotlight: return "Spotlight"
        }
    }

    @ViewBuilder
    var background: some View {
        switch self {
        case .midnight:
            AppBackground(style: .subtle)

        case .aurora:
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.13, blue: 0.16),
                    Color(red: 0.06, green: 0.07, blue: 0.14),
                    Color(red: 0.13, green: 0.07, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .slate:
            Color(red: 0.071, green: 0.075, blue: 0.086)

        case .spotlight:
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.05)
                RadialGradient(
                    colors: [AppColors.primary.opacity(0.35), .clear],
                    center: .init(x: 0.5, y: 0.18),
                    startRadius: 10,
                    endRadius: 420
                )
            }
        }
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
    let theme: ScoreCardTheme

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
            theme.background

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
