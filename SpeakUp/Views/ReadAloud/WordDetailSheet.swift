import SwiftUI

// MARK: - Word Detail

struct WordDetail: Identifiable {
    let id = UUID()
    let word: String
    let index: Int
    let state: WordMatchState
    /// The consonant that separates the word from what was heard in its
    /// place, read once when the word is tapped. Only a miss has one.
    let slip: ConsonantSlip?

    init(word: String, index: Int, state: WordMatchState) {
        self.word = word
        self.index = index
        self.state = state
        if case .mismatched(let spoken) = state {
            slip = ConsonantAnalyzer.slip(target: PronunciationService.stripPunctuation(word), heard: spoken)
        } else {
            slip = nil
        }
    }
}

// MARK: - Word Detail Sheet

struct WordDetailSheet: View {
    let detail: WordDetail
    let pronunciationService: PronunciationService
    /// Plays the word. The live session passes one that holds the mic first -
    /// a live recogniser would score the synthesiser as the reader - and
    /// brings it back when the word ends, exactly as "Hear it" does. Nil
    /// plays it straight away: the result screen has no mic to hold.
    var onHear: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showingDictionary = false

    private var cleanedWord: String {
        PronunciationService.stripPunctuation(detail.word)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                // Scrolls: at large text sizes the slip's tip outgrew the
                // fixed-height sheet it used to sit in.
                PageScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        GlassCard {
                            VStack(spacing: 14) {
                                HStack(spacing: 16) {
                                    MarkedWordText.make(
                                        cleanedWord,
                                        marking: detail.slip?.letters,
                                        base: .white,
                                        mark: AppColors.error
                                    )
                                    .font(.system(size: 36, weight: .bold, design: .rounded))

                                    speakerButton
                                }

                                stateIndicator

                                if let slip = detail.slip {
                                    slipExplanation(slip)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        if PronunciationService.canDefine(detail.word) {
                            GlassButton(
                                title: "Full definition",
                                icon: "book.fill",
                                style: .secondary,
                                fullWidth: true
                            ) {
                                Haptics.light()
                                showingDictionary = true
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(cleanedWord)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingDictionary) {
            DictionaryView(term: detail.word)
        }
        .onDisappear {
            pronunciationService.stop()
        }
    }

    // MARK: - Speaker

    private var speakerButton: some View {
        Button {
            Haptics.light()
            if let onHear {
                onHear()
            } else {
                pronunciationService.speak(word: detail.word)
            }
        } label: {
            Image(systemName: pronunciationService.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                .font(.system(size: 26))
                .foregroundStyle(AppColors.primary)
                .frame(width: 50, height: 50)
                .symbolSwap(pronunciationService.isSpeaking)
                // Painted, not glass: this sits on a GlassCard (rule 13b).
                .background { Circle().fill(Color.white.opacity(0.10)) }
                .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
        }
        .buttonStyle(GlassPressStyle())
        .disabled(pronunciationService.isSpeaking)
        .accessibilityLabel("Hear \(cleanedWord)")
    }

    // MARK: - Consonant

    private func slipExplanation(_ slip: ConsonantSlip) -> some View {
        VStack(spacing: 6) {
            Text(slip.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(slip.tip)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        switch detail.state {
        case .mismatched(let spoken):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppColors.error)
                Text("You said: \(Text(spoken).bold().foregroundStyle(AppColors.error))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

        case .skipped:
            HStack(spacing: 6) {
                Image(systemName: "forward.fill")
                    .foregroundStyle(AppColors.warning)
                Text("Skipped")
                    .foregroundStyle(AppColors.warning)
                    .bold()
            }
            .font(.subheadline)

        case .matched:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                Text("Matched")
                    .foregroundStyle(AppColors.success)
                    .bold()
            }
            .font(.subheadline)

        default:
            EmptyView()
        }
    }
}
