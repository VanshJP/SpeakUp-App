import SwiftUI

/// Today's words, inside the prompt card under a hairline the row draws itself
/// — so a day with no workout ends the card at the prompt text, no stray rule.
///
/// Duration does not belong on this line. It sat here until the three-word cap
/// pushed the last chip onto a second row directly beneath the pill, orphaned
/// next to a control it has nothing to do with — and the width the pill took is
/// what forced that wrap. It lives in the card header now.
///
/// Skip and add-to-bank hang off each chip as a tap `Menu`: a sheet was a whole
/// screen of chrome for two rare verbs and it covered the prompt, a
/// `contextMenu` hid them completely. The chevron is the affordance and the
/// sage dot marks a word introduced today.
struct SessionWordsRow: View {
    var workout: DailyVocabChallenge?
    var bankWords: [String] = []
    var onSkip: ((VocabChallengeWord) -> Void)?
    var onAddToBank: ((VocabChallengeWord) -> Void)?

    /// `FlowLayout` top-aligns a line, so children of mixed height come out
    /// ragged. One height for every chip is the whole fix.
    private let chipHeight: CGFloat = 44

    var body: some View {
        if let workout, !workout.words.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Rectangle()
                    .fill(AppColors.cardStroke)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                // `USE` is the label these chips spent their whole life
                // without — two bare words explain nothing on their own.
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
            // A `Rectangle` has no ideal width, so the `VStack` would otherwise
            // size to the chips and the rule would stop short of the card edge.
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
                // New words earn the one dot of colour in this row — it is the
                // only state a chip has that the user cannot infer from reading.
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
        // Visual capsule stays compact; the Menu gets a full HIG-sized target.
        .frame(minHeight: chipHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Work in the word \(word.text)\(isNew ? ", new word" : ""), \(used ? "used" : "not used yet")")
        .accessibilityHint(word.gloss ?? word.coachLine)
        .accessibilityAddTraits(.isButton)
    }
}
