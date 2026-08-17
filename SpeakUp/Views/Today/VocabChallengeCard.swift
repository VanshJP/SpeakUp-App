import SwiftUI
import SwiftData

struct VocabChallengeCard: View {
    let challenge: DailyVocabChallenge
    var bankWords: [String] = []
    var onSkip: ((VocabChallengeWord) -> Void)?
    var onAddToBank: ((VocabChallengeWord) -> Void)?

    var body: some View {
        GlassCard(cornerRadius: 14, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if challenge.words.isEmpty {
                    emptyState
                } else {
                    wordList
                    if !challenge.isCompleted {
                        Text("Use each one in a sentence today.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var header: some View {
        HStack(spacing: 11) {
            stateMark

            VStack(alignment: .leading, spacing: 1) {
                Text(challenge.isCompleted ? "Word workout done" : "Word workout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(challenge.isCompleted ? Color.secondary : Color.white)
                    .lineLimit(1)

                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "character.book.closed")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var statusLine: String {
        if challenge.words.isEmpty {
            return "Add words or turn on new-word intros"
        }
        if challenge.isCompleted {
            return "Every spotlight word showed up"
        }
        if challenge.usedCount == 0 {
            return "Today's words"
        }
        return "\(challenge.usedCount) of \(challenge.words.count) used"
    }

    private var stateMark: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    challenge.isCompleted ? AppColors.success : Color.white.opacity(0.25),
                    lineWidth: 1.5
                )
                .frame(width: 19, height: 19)

            if challenge.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColors.success)
            } else if challenge.usedCount > 0 {
                Text("\(challenge.usedCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var emptyState: some View {
        Text("Turn on New words in Settings → Words, or add a few to your bank.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var wordList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(challenge.words) { word in
                wordRow(word)
            }
        }
    }

    private func wordRow(_ word: VocabChallengeWord) -> some View {
        let used = challenge.isUsed(word)
        let inBank = bankWords.contains { $0.caseInsensitiveCompare(word.text) == .orderedSame }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: used ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(used ? AppColors.success : .white.opacity(0.35))

                Text(word.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(used ? Color.secondary : Color.white)
                    .strikethrough(used, color: .white.opacity(0.25))

                sourceBadge(word.source)

                Spacer(minLength: 0)

                if word.source == .introduced, !inBank, let onAddToBank {
                    Button("Add") {
                        Haptics.success()
                        onAddToBank(word)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(word.text) to word bank")
                }

                if !used, let onSkip {
                    Button {
                        Haptics.light()
                        onSkip(word)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip \(word.text)")
                }
            }

            if let gloss = word.gloss, !used {
                Text(gloss)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
            }

            if !used {
                Text(word.coachLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 24)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.text), \(used ? "used" : "not used yet")")
    }

    private func sourceBadge(_ source: VocabChallengeWord.Source) -> some View {
        Text(sourceLabel(source))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(.white.opacity(0.06))
            }
    }

    private func sourceLabel(_ source: VocabChallengeWord.Source) -> String {
        switch source {
        case .bank: return "Bank"
        case .dictionary: return "Dict"
        case .introduced: return "New"
        }
    }

    private var accessibilitySummary: String {
        if challenge.words.isEmpty {
            return "Word workout, no words yet"
        }
        let names = challenge.words.map(\.text).joined(separator: ", ")
        let state = challenge.isCompleted ? "completed" : "\(challenge.usedCount) of \(challenge.words.count) used"
        return "Word workout: \(names). \(state)"
    }
}

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
                    Text(evaluation.isComplete ? "Word workout complete" : "Word workout")
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
                    Text("Still to use: \(evaluation.missed.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            evaluation.isComplete
                ? "Word workout complete"
                : "Word workout \(evaluation.used.count) of \(challenge.words.count)"
        )
    }
}
