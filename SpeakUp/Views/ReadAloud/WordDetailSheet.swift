import SwiftUI

// MARK: - Word Detail

struct WordDetail: Identifiable {
    let id = UUID()
    let word: String
    let index: Int
    let state: WordMatchState
}

// MARK: - Word Detail Sheet

struct WordDetailSheet: View {
    let detail: WordDetail
    let pronunciationService: PronunciationService
    var micActive: Bool = false

    @State private var showingDictionary = false

    private var cleanedWord: String {
        PronunciationService.stripPunctuation(detail.word)
    }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            VStack(spacing: 20) {
                // Word + inline speaker button
                GlassCard {
                    VStack(spacing: 14) {
                        HStack(spacing: 16) {
                            Text(cleanedWord)
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            if !micActive {
                                Button {
                                    Haptics.light()
                                    pronunciationService.speak(word: detail.word)
                                } label: {
                                    Image(systemName: pronunciationService.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(AppColors.primary)
                                        .frame(width: 50, height: 50)
                                        .background {
                                            Circle().fill(.ultraThinMaterial)
                                        }
                                }
                                .disabled(pronunciationService.isSpeaking)
                            }
                        }

                        if micActive {
                            HStack(spacing: 6) {
                                Image(systemName: "mic.slash")
                                    .font(.caption)
                                Text("Stop session to hear pronunciation")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }

                        stateIndicator
                    }
                    .frame(maxWidth: .infinity)
                }

                // Definition button
                if PronunciationService.canDefine(detail.word) {
                    GlassButton(
                        title: "View Definition",
                        icon: "book.fill",
                        style: .secondary
                    ) {
                        Haptics.light()
                        showingDictionary = true
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingDictionary) {
            DictionaryView(term: detail.word)
        }
        .onDisappear {
            pronunciationService.stop()
        }
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        switch detail.state {
        case .mismatched(let spoken):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("You said: ")
                    .foregroundStyle(.secondary) +
                Text(spoken)
                    .foregroundStyle(.red)
                    .bold()
            }
            .font(.subheadline)

        case .skipped:
            HStack(spacing: 6) {
                Image(systemName: "forward.fill")
                    .foregroundStyle(.orange)
                Text("Skipped")
                    .foregroundStyle(.orange)
                    .bold()
            }
            .font(.subheadline)

        case .matched:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Matched")
                    .foregroundStyle(.green)
                    .bold()
            }
            .font(.subheadline)

        default:
            EmptyView()
        }
    }
}
