import SwiftUI

struct ReadAloudResultView: View {
    let result: ReadAloudResult
    let onRetry: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Session Complete")
                            .font(.title2.bold())

                        Text(result.passage.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    // Score ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 12)
                            .frame(width: 140, height: 140)

                        Circle()
                            .trim(from: 0, to: Double(result.score) / 100.0)
                            .stroke(
                                LinearGradient(
                                    colors: scoreGradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .frame(width: 140, height: 140)
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 2) {
                            Text("\(result.score)%")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(scoreColor)
                            Text("Accuracy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Stats row
                    HStack(spacing: 12) {
                        StatBadge(
                            icon: "checkmark.circle.fill",
                            value: "\(result.matchedWords)",
                            label: "Matched",
                            color: .green
                        )

                        StatBadge(
                            icon: "xmark.circle.fill",
                            value: "\(result.mismatchedWords)",
                            label: "Missed",
                            color: .red
                        )

                        StatBadge(
                            icon: "clock.fill",
                            value: formattedTime,
                            label: "Time",
                            color: .blue
                        )

                        StatBadge(
                            icon: "text.word.spacing",
                            value: "\(result.totalWords)",
                            label: "Words",
                            color: .purple
                        )
                    }

                    // Word review
                    wordReviewSection

                    // Action buttons
                    VStack(spacing: 12) {
                        GlassButton(title: "Try Again", icon: "arrow.clockwise", style: .primary) {
                            Haptics.medium()
                            onRetry()
                        }

                        GlassButton(title: "Done", icon: "checkmark", style: .secondary) {
                            Haptics.light()
                            onDone()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Word Review

    private var wordReviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Word Review", systemImage: "doc.text.magnifyingglass")
                .font(.headline)

            GlassCard {
                WrappingHStack(alignment: .leading, spacing: 6, lineSpacing: 10) {
                    ForEach(Array(result.passage.words.enumerated()), id: \.offset) { index, word in
                        Text(word)
                            .font(.system(size: 16))
                            .foregroundStyle(reviewWordColor(for: index))
                            .padding(.vertical, 1)
                    }
                }
            }

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .green, label: "Matched")
                legendItem(color: .red, label: "Mismatched")
                legendItem(color: .orange, label: "Skipped")
                legendItem(color: .white.opacity(0.4), label: "Not reached")
            }
            .font(.caption2)
        }
    }

    private func reviewWordColor(for index: Int) -> Color {
        guard index < result.wordStates.count else { return .white.opacity(0.4) }
        switch result.wordStates[index] {
        case .matched: return .green
        case .mismatched: return .red
        case .skipped: return .orange
        case .upcoming: return .white.opacity(0.4)
        case .current: return .white.opacity(0.4)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let minutes = Int(result.timeTaken) / 60
        let seconds = Int(result.timeTaken) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var scoreColor: Color {
        AppColors.scoreColor(for: result.score)
    }

    private var scoreGradientColors: [Color] {
        if result.score >= 80 { return [.green, .cyan] }
        if result.score >= 60 { return [.yellow, .orange] }
        return [.orange, .red]
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        GlassCard(cornerRadius: 12, tint: color.opacity(0.08), padding: 10) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)

                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
