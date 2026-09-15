import SwiftUI
import SwiftData

struct ReadAloudSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    @State private var viewModel = ReadAloudViewModel()
    @State private var showingSession = false
    @State private var showingComposer = false
    @State private var composerInitialText = ""
    @State private var editingSavedText: String?
    @State private var pendingPracticePassage: ReadAloudPassage?
    @State private var passagePendingDeletion: ReadAloudPassage?
    @State private var shadowMode = false
    @State private var didStartInitialPractice = false

    var presentation: ToolPresentation = .sheet

    /// A line handed in by another screen to rehearse immediately — today,
    /// a word-swap rewrite from the recording detail. The session opens
    /// straight away; the list underneath is where the user lands afterwards.
    var initialPracticeText: String?

    private var longestPassageWords: Double {
        Double(viewModel.passages.map(\.wordCount).max() ?? 0)
    }

    // MARK: - Saved passage state

    private var settings: UserSettings? { userSettings.first }

    /// Stored text to passage, in stored (newest first) order. The id is derived
    /// from the text, so rows keep their identity across renders.
    private var savedPassages: [ReadAloudPassage] {
        (settings?.savedReadAloudTexts ?? []).compactMap { ReadAloudPassage.saved(from: $0) }
    }

    private func deleteSaved(_ passage: ReadAloudPassage) {
        guard let settings else { return }
        settings.removeSavedReadAloudText(passage.text)
        try? modelContext.save()
        Haptics.light()
    }

    private func practice(_ passage: ReadAloudPassage) {
        Haptics.medium()
        viewModel.isShadowMode = shadowMode
        viewModel.selectedPassage = passage
        showingSession = true
    }

    var body: some View {
        ToolPage(tool: .readAloud, presentation: presentation) {
            customEntrySection

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

            GlassSectionHeader("Passage Library", icon: "books.vertical.fill")

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
        .task {
            guard !didStartInitialPractice,
                  let initialPracticeText,
                  let passage = ReadAloudPassage.custom(from: initialPracticeText)
            else { return }

            didStartInitialPractice = true
            viewModel.isShadowMode = false
            viewModel.selectedPassage = passage
            showingSession = true
        }
        .sheet(isPresented: $showingComposer, onDismiss: startPendingPractice) {
            ReadAloudComposerSheet(
                initialText: composerInitialText,
                isEditing: editingSavedText != nil,
                onCancel: {
                    showingComposer = false
                },
                onSave: { text in
                    saveCustomText(text)
                    showingComposer = false
                },
                onPractice: { text in
                    saveCustomText(text)
                    pendingPracticePassage = ReadAloudPassage.saved(from: text)
                    showingComposer = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete this passage?",
            isPresented: Binding(
                get: { passagePendingDeletion != nil },
                set: { if !$0 { passagePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Passage", role: .destructive) {
                if let passagePendingDeletion {
                    deleteSaved(passagePendingDeletion)
                }
                passagePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                passagePendingDeletion = nil
            }
        } message: {
            Text("This removes the passage from your saved list.")
        }
    }

    // MARK: - Custom entry

    private var customEntrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Your Passages", icon: "person.text.rectangle")

            Button {
                presentComposer()
            } label: {
                GlassCard(padding: 13) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppColors.toolReadAloud)
                            .frame(width: 38, height: 38)
                            .background {
                                Circle().fill(AppColors.toolReadAloud.opacity(0.14))
                            }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Add Your Own Passage")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Paste, type, or import TXT, RTF, or PDF")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppColors.toolReadAloud)
                    }
                }
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Add your own passage. Paste, type, or import a document.")
        }
    }

    // MARK: - Yours

    @ViewBuilder
    private var savedSection: some View {
        let saved = savedPassages
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Saved", icon: "bookmark.fill") {
                    Text("\(saved.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(saved) { passage in
                            savedPassageCard(passage)
                                .frame(width: 292)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func savedPassageCard(_ passage: ReadAloudPassage) -> some View {
        GlassCard(padding: 0) {
            HStack(spacing: 0) {
                Button {
                    practice(passage)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Image(systemName: "bookmark.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.toolReadAloud)
                            Text(passage.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }

                        Text(passage.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        Text("\(passage.wordCount) words · \(Self.estimatedTime(passage.wordCount))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.difficultyColor(passage.difficulty))
                    }
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                    .padding(13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(passage.title). \(passage.wordCount) words. \(passage.text)"
                )

                Menu {
                    Button {
                        presentComposer(editing: passage)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        passagePendingDeletion = passage
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Passage actions")
                .padding(.trailing, 4)
            }
        }
    }

    // MARK: - Composer

    private func presentComposer(editing passage: ReadAloudPassage? = nil) {
        composerInitialText = passage?.text ?? ""
        editingSavedText = passage?.text
        showingComposer = true
        Haptics.light()
    }

    private func saveCustomText(_ text: String) {
        guard let settings,
              let normalized = ReadAloudPassage.normalizedCustomText(text) else { return }

        if let editingSavedText,
           editingSavedText.caseInsensitiveCompare(normalized) != .orderedSame {
            settings.removeSavedReadAloudText(editingSavedText)
        }
        settings.addSavedReadAloudText(normalized)
        try? modelContext.save()
        Haptics.success()
    }

    private func startPendingPractice() {
        defer {
            pendingPracticePassage = nil
            editingSavedText = nil
            composerInitialText = ""
        }
        guard let pendingPracticePassage else { return }
        practice(pendingPracticePassage)
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
