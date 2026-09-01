import SwiftUI

struct ReadAloudSelectionView: View {
    @State private var viewModel = ReadAloudViewModel()
    @State private var showingSession = false
    @State private var showingComposer = false
    @State private var customText = ""
    @State private var shadowMode = false

    /// How this list is hosted. See `ToolPresentation` / `ToolPage`.
    var presentation: ToolPresentation = .sheet

    /// Denominator for each row's arc, scoped to what the filters leave
    /// visible — within one set the relative lengths are what's worth reading.
    private var longestPassageWords: Double {
        Double(viewModel.passages.map(\.wordCount).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .readAloud, presentation: presentation) {
            // Practice anything — type a word, sentence, or paragraph.
            Button {
                Haptics.light()
                showingComposer = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "pencil.line")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColors.toolReadAloud)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppColors.toolReadAloud.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice anything")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Type a word, sentence, or paragraph")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Practice anything")
            .accessibilityHint("Opens a text field to practice your own words")

            Toggle(isOn: $shadowMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shadow mode")
                        .font(.subheadline.weight(.semibold))
                    Text("Hear the model line, then speak it back")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(AppColors.toolReadAloud)
            .padding(.horizontal, 4)

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

                ForEach(ReadAloudCategory.allCases) { category in
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
                            viewModel.isShadowMode = shadowMode
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
        .sheet(isPresented: $showingComposer) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Type a word, sentence, or short paragraph to practice.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $customText)
                        .frame(minHeight: 140)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                    Toggle(isOn: $shadowMode) {
                        Text("Shadow mode")
                    }
                    .tint(AppColors.toolReadAloud)
                    Spacer()
                }
                .padding()
                .background(AppBackground(style: .subtle))
                .navigationTitle("Practice anything")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingComposer = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start") {
                            let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            Haptics.medium()
                            viewModel.isShadowMode = shadowMode
                            viewModel.selectedPassage = ReadAloudPassage.custom(text: trimmed)
                            showingComposer = false
                            showingSession = true
                        }
                        .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
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
