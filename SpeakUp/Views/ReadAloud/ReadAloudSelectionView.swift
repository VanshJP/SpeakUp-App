import SwiftUI

struct ReadAloudSelectionView: View {
    @State private var viewModel = ReadAloudViewModel()
    @State private var showingSession = false
    @State private var customText = ""
    @State private var pronunciationService = PronunciationService()
    @State private var showingDictionary = false
    @FocusState private var customFieldFocused: Bool

    /// How this list is hosted. See `ToolPresentation` / `ToolPage`.
    var presentation: ToolPresentation = .sheet

    /// Denominator for each row's arc, scoped to what the filters leave
    /// visible — within one set the relative lengths are what's worth reading.
    private var longestPassageWords: Double {
        Double(viewModel.passages.map(\.wordCount).max() ?? 0)
    }

    private var trimmedCustomText: String {
        customText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canPracticeCustom: Bool {
        ReadAloudPassage.custom(from: customText) != nil
    }

    private var canDefineCustom: Bool {
        PronunciationService.canDefine(trimmedCustomText)
    }

    var body: some View {
        ToolPage(tool: .readAloud, presentation: presentation) {
            customPracticeCard

            // Two axes, one grammar: both rows lead with All, so neither can
            // strand you in a filtered state with no way back.
            ToolFilterBar {
                FilterPill(
                    title: "All",
                    isSelected: viewModel.selectedDifficulty == nil
                ) {
                    withAnimation(AppMotion.slide) { viewModel.selectedDifficulty = nil }
                }

                ForEach(ReadAloudDifficulty.allCases) { difficulty in
                    FilterPill(
                        title: difficulty.displayName,
                        isSelected: viewModel.selectedDifficulty == difficulty,
                        color: AppColors.difficultyColor(difficulty)
                    ) {
                        withAnimation(AppMotion.slide) {
                            viewModel.selectedDifficulty = viewModel.selectedDifficulty == difficulty ? nil : difficulty
                        }
                    }
                }
            }

            ToolFilterBar {
                FilterPill(
                    title: "All",
                    icon: "square.grid.2x2",
                    isSelected: viewModel.selectedCategory == nil
                ) {
                    withAnimation(AppMotion.slide) { viewModel.selectedCategory = nil }
                }

                ForEach(ReadAloudCategory.catalogCases) { category in
                    FilterPill(
                        title: category.displayName,
                        icon: category.icon,
                        isSelected: viewModel.selectedCategory == category
                    ) {
                        withAnimation(AppMotion.slide) {
                            viewModel.selectedCategory = viewModel.selectedCategory == category ? nil : category
                        }
                    }
                }
            }

            if viewModel.selectedDifficulty != nil || viewModel.selectedCategory != nil {
                Text("\(viewModel.passages.count) of \(DefaultReadAloudPassages.all.count) passages")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 12) {
                if viewModel.passages.isEmpty {
                    EmptyStateCard(
                        icon: "text.book.closed",
                        title: "Nothing here",
                        message: "No passages match these filters. Try clearing one.",
                        buttonTitle: "Show All",
                        buttonAction: {
                            withAnimation(AppMotion.slide) {
                                viewModel.selectedDifficulty = nil
                                viewModel.selectedCategory = nil
                            }
                        }
                    )
                } else {
                    ForEach(viewModel.passages) { passage in
                        PracticeItemRow(
                            title: passage.title,
                            // The passage itself is the subtitle: you pick one
                            // by reading a line of it, not by its name.
                            subtitle: passage.text,
                            icon: passage.category.icon,
                            tint: AppColors.difficultyColor(passage.difficulty),
                            durationFraction: PracticeItemRow.fraction(
                                Double(passage.wordCount),
                                longest: longestPassageWords
                            ),
                            durationLabel: Self.estimatedTime(passage.wordCount),
                            tag: "\(passage.difficulty.displayName) · \(passage.wordCount) words"
                        ) {
                            Haptics.medium()
                            customFieldFocused = false
                            pronunciationService.stop()
                            viewModel.selectedPassage = passage
                            showingSession = true
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingSession) {
            if let passage = viewModel.selectedPassage {
                ReadAloudSessionView(viewModel: viewModel, passage: passage)
            }
        }
        .sheet(isPresented: $showingDictionary) {
            DictionaryView(term: trimmedCustomText)
        }
        .onDisappear {
            pronunciationService.stop()
        }
    }

    // MARK: - Custom practice

    /// Type a word, sentence, or short paragraph — hear the model, look it up,
    /// then run the same alignment scoring as a catalog passage.
    private var customPracticeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "text.cursor")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.toolReadAloud)

                    Text("Practice anything")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Text("Type a word, sentence, or short paragraph. Hear it, then say it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "e.g. entrepreneurial — or a full sentence",
                    text: $customText,
                    axis: .vertical
                )
                .lineLimit(2...6)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .focused($customFieldFocused)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))
                }

                HStack(spacing: 10) {
                    Button {
                        Haptics.light()
                        customFieldFocused = false
                        pronunciationService.speak(word: trimmedCustomText)
                    } label: {
                        Label(
                            pronunciationService.isSpeaking ? "Playing" : "Hear it",
                            systemImage: pronunciationService.isSpeaking
                                ? "speaker.wave.3.fill"
                                : "speaker.wave.2.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canPracticeCustom ? AppColors.toolReadAloud : .secondary)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppColors.toolReadAloud.opacity(canPracticeCustom ? 0.15 : 0.06))
                    }
                    .disabled(!canPracticeCustom || pronunciationService.isSpeaking)
                    .accessibilityLabel("Hear pronunciation")

                    if canDefineCustom {
                        Button {
                            Haptics.light()
                            pronunciationService.stop()
                            showingDictionary = true
                        } label: {
                            Label("Define", systemImage: "book.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColors.toolReadAloud)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppColors.toolReadAloud.opacity(0.15))
                        }
                        .accessibilityLabel("View dictionary definition")
                    }
                }

                GlassButton(
                    title: "Practice saying it",
                    icon: "mic.fill",
                    style: .primary,
                    fullWidth: true
                ) {
                    startCustomPractice()
                }
                .disabled(!canPracticeCustom)
                .opacity(canPracticeCustom ? 1 : 0.45)
            }
        }
    }

    private func startCustomPractice() {
        guard let passage = ReadAloudPassage.custom(from: customText) else { return }
        Haptics.medium()
        customFieldFocused = false
        pronunciationService.stop()
        viewModel.selectedPassage = passage
        showingSession = true
    }
}

// MARK: - Cost

extension ReadAloudSelectionView {
    /// Rough cost at a conversational ~150 wpm, so a passage says what it
    /// takes before you commit. Short enough to sit inside the row's dial.
    static func estimatedTime(_ wordCount: Int) -> String {
        let minutes = Double(wordCount) / 150.0
        if minutes < 1 { return "<1m" }
        return "\(Int(minutes.rounded()))m"
    }
}
