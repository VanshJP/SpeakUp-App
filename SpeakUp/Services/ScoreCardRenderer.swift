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
        VStack(spacing: 0) {
            // Top section - branding + score
            VStack(spacing: 24) {
                // App branding
                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.teal, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("SpeakUp")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(recording.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                // Score hero
                HStack(spacing: 24) {
                    // Score ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 12)
                            .frame(width: 120, height: 120)

                        Circle()
                            .trim(from: 0, to: Double(analysis.speechScore.overall) / 100)
                            .stroke(
                                AngularGradient(
                                    colors: [scoreColor.opacity(0.5), scoreColor],
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(360 * Double(analysis.speechScore.overall) / 100)
                                ),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 2) {
                            Text("\(analysis.speechScore.overall)")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(scoreColor)
                            Text("/ 100")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    // Subscores
                    VStack(alignment: .leading, spacing: 10) {
                        ShareSubscoreRow(label: "Clarity", value: analysis.speechScore.subscores.clarity, color: .blue)
                        ShareSubscoreRow(label: "Pace", value: analysis.speechScore.subscores.pace, color: .green)
                        ShareSubscoreRow(label: "Fillers", value: analysis.speechScore.subscores.fillerUsage, color: .orange)
                        ShareSubscoreRow(label: "Pauses", value: analysis.speechScore.subscores.pauseQuality, color: .purple)
                        if let delivery = analysis.speechScore.subscores.delivery {
                            ShareSubscoreRow(label: "Delivery", value: delivery, color: .cyan)
                        }
                        if let vocabulary = analysis.speechScore.subscores.vocabulary {
                            ShareSubscoreRow(label: "Vocab", value: vocabulary, color: .teal)
                        }
                        if let structure = analysis.speechScore.subscores.structure {
                            ShareSubscoreRow(label: "Structure", value: structure, color: .indigo)
                        }
                        if let relevance = analysis.speechScore.subscores.relevance {
                            ShareSubscoreRow(label: "Relevance", value: relevance, color: .pink)
                        }
                    }
                }
            }
            .padding(28)

            // Divider line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.15), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Bottom section - stats + prompt
            VStack(spacing: 16) {
                // Stats row
                HStack(spacing: 0) {
                    ShareStatPill(label: "WPM", value: "\(Int(analysis.wordsPerMinute))", color: .blue)
                    ShareStatPill(label: "Words", value: "\(analysis.totalWords)", color: .green)
                    ShareStatPill(label: "Fillers", value: "\(analysis.totalFillerCount)", color: .orange)
                }

                // Prompt text
                if let prompt = recording.prompt {
                    Text("\"\(prompt.text)\"")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                }
            }
            .padding(24)
        }
        .frame(width: 380)
        .background(
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.14, blue: 0.20),
                        Color(red: 0.02, green: 0.08, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Subtle radial glow from score
                RadialGradient(
                    colors: [scoreColor.opacity(0.08), .clear],
                    center: UnitPoint(x: 0.3, y: 0.35),
                    startRadius: 20,
                    endRadius: 200
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
    }

    private var scoreColor: Color {
        AppColors.scoreColor(for: analysis.speechScore.overall)
    }
}

// MARK: - Share Subscore Row

private struct ShareSubscoreRow: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 56, alignment: .trailing)

            // Bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 8)

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.6), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, 100 * CGFloat(value) / 100), height: 8)
            }
            .frame(width: 100, height: 8, alignment: .leading)

            Text("\(value)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, alignment: .leading)
        }
    }
}

// MARK: - Share Stat Pill

private struct ShareStatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}
