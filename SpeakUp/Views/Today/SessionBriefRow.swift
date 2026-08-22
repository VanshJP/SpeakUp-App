import SwiftUI

/// The spec for the take you are about to record: today's spotlight words, on
/// one line, directly above the start button.
///
/// These used to be a full card at the bottom of Today — below the start
/// button, which is where nobody looks, and framed as separate homework. They
/// are not homework: recording is the only way they complete. So they sit with
/// the prompt as the brief for this session.
///
/// Skip and add-to-bank hang off each chip as a tap `Menu`, not a sheet and not
/// a long-press. A sheet was a whole screen of chrome for two rare verbs and it
/// covered the prompt; a context menu hid them completely. The chevron on each
/// chip is the affordance, and a dot marks the words that are new today.
struct SessionBriefRow: View {
    let workout: DailyVocabChallenge?
    var bankWords: [String] = []
    var onSkip: ((VocabChallengeWord) -> Void)?
    var onAddToBank: ((VocabChallengeWord) -> Void)?

    var body: some View {
        if !(workout?.words.isEmpty ?? true) {
            VStack(alignment: .leading, spacing: 8) {
                if let workout, !workout.words.isEmpty {
                    wordRow(workout)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.surfaceLift)
                    }
            }
        }
    }

    // MARK: - Words

    private func wordRow(_ workout: DailyVocabChallenge) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 6)

            FlowLayout(spacing: 6) {
                ForEach(workout.words) { word in
                    wordChip(word, used: workout.isUsed(word))
                }
            }

            Spacer(minLength: 0)
        }
    }

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(word.text)\(isNew ? ", new word" : ""), \(used ? "used" : "not used yet")")
        .accessibilityHint(word.gloss ?? word.coachLine)
        .accessibilityAddTraits(.isButton)
    }

}
