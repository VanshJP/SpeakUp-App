import SwiftUI

struct SessionWordsRow: View {
    var workout: DailyVocabChallenge?
    var bankWords: [String] = []
    var onSkip: ((VocabChallengeWord) -> Void)?
    var onAddToBank: ((VocabChallengeWord) -> Void)?

    private let chipHeight: CGFloat = 44

    var body: some View {
        if let workout, !workout.words.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Rectangle()
                    .fill(AppColors.cardStroke)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                FlowLayout(spacing: 6) {
                    Text("USE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(height: chipHeight)
                        .accessibilityHidden(true)

                    ForEach(workout.words) { word in
                        wordChip(word, used: workout.isUsed(word))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Words

    private func wordChip(_ word: VocabChallengeWord, used: Bool) -> some View {
        let tint: Color = used ? AppColors.success : .white
        let isNew = word.source == .introduced
            && !bankWords.contains { $0.caseInsensitiveCompare(word.text) == .orderedSame }

        return Menu {
            if let gloss = word.gloss, !gloss.isEmpty {
                Section(word.text) { Text(gloss) }
            }

            if isNew, let onAddToBank {
                Button("Add to word bank", systemImage: "plus") {
                    Haptics.success()
                    onAddToBank(word)
                }
            }

            if !used, let onSkip {
                Button("Swap for another word", systemImage: "arrow.triangle.2.circlepath") {
                    Haptics.light()
                    onSkip(word)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if isNew, !used {
                    Circle()
                        .fill(AppColors.categorySage)
                        .frame(width: 5, height: 5)
                }

                Text(word.text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(used ? AppColors.success : Color.white.opacity(0.9))

                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(used ? AppColors.success.opacity(0.6) : Color.white.opacity(0.4))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(tint.opacity(0.15))
                    .overlay {
                        Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: chipHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Work in the word \(word.text)\(isNew ? ", new word" : ""), \(used ? "used" : "not used yet")")
        .accessibilityHint(word.gloss ?? word.coachLine)
        .accessibilityAddTraits(.isButton)
    }
}
