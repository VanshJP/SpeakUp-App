import SwiftUI
import SwiftData

struct ReadAloudSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    @State private var viewModel = ReadAloudViewModel()
    @State private var showingSession = false
    @State private var customText = ""
    @State private var shadowMode = false
    @State private var pronunciationService = PronunciationService()
    @State private var showingDictionary = false
    @FocusState private var customFieldFocused: Bool

    var presentation: ToolPresentation = .sheet

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

    // MARK: - Saved passage state

    private var settings: UserSettings? { userSettings.first }

    /// Stored text → passage, in stored (newest first) order. The id is derived
    /// from the text, so rows keep their identity across renders.
    private var savedPassages: [ReadAloudPassage] {
        (settings?.savedReadAloudTexts ?? []).compactMap { ReadAloudPassage.saved(from: $0) }
    }

    private var isCurrentTextSaved: Bool {
        settings?.hasSavedReadAloudText(customText) ?? false
    }

    /// Normalize once: the stored text is capped and trimmed, so removing has to
    /// match on the same string the save wrote, not on the raw field.
    private func toggleSaveCustom() {
        guard let settings,
              let text = ReadAloudPassage.normalizedCustomText(customText) else { return }
        if settings.hasSavedReadAloudText(text) {
            settings.removeSavedReadAloudText(text)
            Haptics.light()
        } else {
            settings.addSavedReadAloudText(text)
            Haptics.success()
        }
        try? modelContext.save()
    }

    private func deleteSaved(_ passage: ReadAloudPassage) {
        guard let settings else { return }
        settings.removeSavedReadAloudText(passage.text)
        try? modelContext.save()
        Haptics.light()
    }

    private func practice(_ passage: ReadAloudPassage) {
        Haptics.medium()
        customFieldFocused = false
        pronunciationService.stop()
        viewModel.isShadowMode = shadowMode
        viewModel.selectedPassage = passage
        showingSession = true
    }

    var body: some View {
        ToolPage(tool: .readAloud, presentation: presentation) {
            customPracticeCard

            savedSection

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
                            practice(passage)
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

                    Spacer(minLength: 0)

                    keepButton
                }

                Text("Type a word, sentence, or short paragraph. Hear it, then say it back — keep it to practice again later.")
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
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }

                // `GlassButton` rather than two hand-rolled tinted rectangles:
                // same capsule language, same 44pt minimum, same press feedback
                // as every other secondary action in the app.
                HStack(spacing: 10) {
                    GlassButton(
                        title: pronunciationService.isSpeaking ? "Playing" : "Hear it",
                        icon: pronunciationService.isSpeaking
                            ? "speaker.wave.3.fill"
                            : "speaker.wave.2.fill",
                        style: .secondary,
                        size: .small,
                        fullWidth: true
                    ) {
                        Haptics.light()
                        customFieldFocused = false
                        pronunciationService.speak(word: trimmedCustomText)
                    }
                    .disabled(!canPracticeCustom || pronunciationService.isSpeaking)
                    .opacity(canPracticeCustom ? 1 : 0.45)
                    .accessibilityLabel("Hear pronunciation")

                    if canDefineCustom {
                        GlassButton(
                            title: "Define",
                            icon: "book.fill",
                            style: .secondary,
                            size: .small,
                            fullWidth: true
                        ) {
                            Haptics.light()
                            pronunciationService.stop()
                            showingDictionary = true
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

    /// Keep / un-keep whatever is in the field. Disabled until the text is long
    /// enough to be a passage, which is the same gate as Practice.
    private var keepButton: some View {
        Button {
            toggleSaveCustom()
        } label: {
            Image(systemName: isCurrentTextSaved ? "bookmark.fill" : "bookmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isCurrentTextSaved ? AppColors.toolReadAloud : .secondary)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .disabled(!canPracticeCustom)
        .opacity(canPracticeCustom ? 1 : 0.4)
        .accessibilityLabel(isCurrentTextSaved ? "Remove from your passages" : "Keep this passage")
    }

    // MARK: - Yours

    /// Your own passages, above the catalog. They read as ordinary passage rows
    /// — same `PracticeItemRow`, same scoring path — because that is what they
    /// are; the only difference is that you wrote them.
    @ViewBuilder
    private var savedSection: some View {
        let saved = savedPassages
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Yours", icon: "bookmark.fill") {
                    Text("\(saved.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ForEach(saved) { passage in
                    PracticeItemRow(
                        title: passage.title,
                        subtitle: passage.text,
                        icon: ReadAloudCategory.custom.icon,
                        tint: AppColors.difficultyColor(passage.difficulty),
                        durationFraction: PracticeItemRow.fraction(
                            Double(passage.wordCount),
                            longest: max(longestPassageWords, Double(passage.wordCount))
                        ),
                        durationLabel: Self.estimatedTime(passage.wordCount),
                        tag: "Yours · \(passage.wordCount) words"
                    ) {
                        practice(passage)
                    }
                    .contextMenu {
                        Button {
                            customText = passage.text
                            customFieldFocused = true
                        } label: {
                            Label("Edit in Practice anything", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            deleteSaved(passage)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func startCustomPractice() {
        guard let passage = ReadAloudPassage.custom(from: customText) else { return }
        practice(passage)
    }
}

// MARK: - Cost

extension ReadAloudSelectionView {
    static func estimatedTime(_ wordCount: Int) -> String {
        let minutes = Double(wordCount) / 150.0
        if minutes < 1 { return "<1m" }
        return "\(Int(minutes.rounded()))m"
    }
}
