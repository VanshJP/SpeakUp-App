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

private struct ScoreCardView: View {
    let recording: Recording
    let analysis: SpeechAnalysis

    var body: some View {
        VStack(spacing: 20) {
            // App branding
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)
                Text("SpeakUp")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }

            // Overall score ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 10)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: Double(analysis.speechScore.overall) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(analysis.speechScore.overall)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(scoreColor)
                    Text("/ 100")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Subscore bars
            VStack(spacing: 8) {
                SubscoreBar(label: "Clarity", value: analysis.speechScore.subscores.clarity, color: .blue)
                SubscoreBar(label: "Pace", value: analysis.speechScore.subscores.pace, color: .green)
                SubscoreBar(label: "Filler Usage", value: analysis.speechScore.subscores.fillerUsage, color: .orange)
                SubscoreBar(label: "Pauses", value: analysis.speechScore.subscores.pauseQuality, color: .purple)
            }

            // Stats row
            HStack(spacing: 24) {
                StatPill(label: "WPM", value: "\(Int(analysis.wordsPerMinute))")
                StatPill(label: "Words", value: "\(analysis.totalWords)")
                StatPill(label: "Fillers", value: "\(analysis.totalFillerCount)")
            }

            // Prompt text
            if let prompt = recording.prompt {
                Text("\"\(prompt.text)\"")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
            }

            // Date
            Text(recording.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(32)
        .frame(width: 360)
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.15, blue: 0.2), Color(red: 0.02, green: 0.08, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var scoreColor: Color {
        AppColors.scoreColor(for: analysis.speechScore.overall)
    }
}

private struct SubscoreBar: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 80, alignment: .trailing)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: max(0, 160 * CGFloat(value) / 100), height: 6)
            }
            .frame(width: 160, height: 6, alignment: .leading)

            Text("\(value)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 30, alignment: .leading)
        }
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
