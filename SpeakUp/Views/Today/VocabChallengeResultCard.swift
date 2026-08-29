import SwiftUI
import SwiftData

// MARK: - Session result

struct VocabChallengeResultCard: View {
    let challenge: DailyVocabChallenge
    let evaluation: VocabChallengeEvaluation

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: evaluation.isComplete ? "checkmark.seal.fill" : "character.book.closed")
                        .foregroundStyle(evaluation.isComplete ? AppColors.success : AppColors.categorySage)
                    Text(evaluation.isComplete ? "Word Workout Complete" : "Word Workout")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(evaluation.used.count)/\(challenge.words.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                FlowLayout(spacing: 6) {
                    ForEach(challenge.words) { word in
                        let used = evaluation.used.contains { $0.caseInsensitiveCompare(word.text) == .orderedSame }
                        Text(word.text)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(used ? AppColors.success : .white.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                Capsule()
                                    .fill((used ? AppColors.success : Color.white).opacity(0.12))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(
                                                (used ? AppColors.success : Color.white).opacity(0.25),
                                                lineWidth: 0.5
                                            )
                                    }
                            }
                    }
                }

                if !evaluation.isComplete, !evaluation.missed.isEmpty {
                    Text("Optional words for next time: \(evaluation.missed.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            evaluation.isComplete
                ? "Word Workout Complete"
                : "Word Workout \(evaluation.used.count) of \(challenge.words.count)"
        )
    }
}
