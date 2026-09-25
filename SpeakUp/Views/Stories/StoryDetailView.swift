import SwiftUI
import SwiftData
import UIKit

struct StoryDetailView: View {
    var story: Story
    var viewModel: StoriesViewModel
    var onStartPractice: ((Story, RecordingDuration) -> Void)?
    var onSendToWarmUp: ((Story) -> Void)?
    var onSendToDrill: ((Story) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    @State private var showingDeleteAlert = false
    @State private var showCopied = false
    @State private var recordingSummaries: [PracticeRecordingSummary] = []
    @State private var chartPoints: [PracticeDataPoint] = []
    @State private var showingMoveSheet = false
    @State private var showingEditor = false
    @State private var toastMessage: String?
    @State private var isDeleted = false
    @State private var displayCache = StoryDisplayCache()

    private var settings: UserSettings? { settingsList.first }

    /// Decoded content + word stats for the current `updatedAt`.
    private var display: StoryDisplayCache { displayCache.refreshed(for: story) }

    /// Deleted from this page or from the editor sheet on top of it. Once
    /// true, nothing here reads the story again: its attributes went with the
    /// row, and the page still renders through the pop animation - the same
    /// guard `RecordingDetailView.deleteRecording` keeps. `isDeleted` and
    /// `modelContext` are safe to read on a deleted model; attributes are not.
    private var storyIsGone: Bool {
        isDeleted || story.isDeleted || story.modelContext == nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground(style: .subtle)

            if !storyIsGone {
                liveContent
            }
        }
        // A fixed title: `story.title` here would be read during the pop
        // that follows a delete.
        .navigationTitle("Story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if !storyIsGone {
                ToolbarItem(placement: .topBarTrailing) {
                    detailMenu
                }
            }
        }
        .sheet(isPresented: $showingMoveSheet) {
            NavigationStack {
                StoryMoveFolderSheet(viewModel: viewModel, story: story)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            // The editor can delete the story. Leaving this page up would
            // show a story that no longer exists, one tap from a crash.
            if storyIsGone {
                dismiss()
            } else {
                reloadRecordings()
            }
        }) {
            NavigationStack {
                StoryEditorView(viewModel: viewModel, existingStory: story)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert(StoryDeleteCopy.title, isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                isDeleted = true
                Haptics.warning()
                dismiss()
                viewModel.deleteStory(story)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(StoryDeleteCopy.message)
        }
        .storiesErrorAlert(viewModel)
        .onAppear {
            viewModel.surfaceAppeared()
            guard !storyIsGone else { return }
            reloadRecordings()
        }
        .onDisappear {
            viewModel.surfaceDisappeared()
        }
    }

    private var liveContent: some View {
        ZStack(alignment: .top) {
            PageScrollView {
                VStack(spacing: 20) {
                    heroHeader
                    primaryActions
                    // The script is what you came to rehearse, so it sits under
                    // the actions and progress follows. Below the metrics and
                    // chart it started ~600pt down once a story had takes.
                    contentSection
                    tagsSection
                    if !recordingSummaries.isEmpty {
                        metricsSection
                        practiceChartSection
                    }
                    recordingsSection
                }
                .padding(.horizontal, AppLayout.pageHorizontal)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)

            if let toastMessage {
                toast(toastMessage)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func reloadRecordings() {
        Task {
            let summaries = await viewModel.linkedTakeSummaries(for: story)
            recordingSummaries = summaries
            chartPoints = PracticeDataPoint.from(summaries: summaries)
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    StoryFolderChip(folder: currentFolder) {
                        showingMoveSheet = true
                    }

                    Spacer(minLength: 8)

                    Text(story.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(story.title.isEmpty ? "Untitled" : story.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Stage used to be write-only: set from a menu, shown nowhere.
                HStack(spacing: 8) {
                    StatusPill(
                        text: currentStage.displayName,
                        color: stageColor,
                        glyph: .icon(currentStage.icon)
                    )
                    if story.isFavorite {
                        StatusPill(text: "Pinned", color: AppColors.warning, glyph: .icon("pin.fill"))
                    }
                }

                HStack(spacing: 12) {
                    Label("\(display.wordCount) words", systemImage: "text.word.spacing")
                    Label(display.readingTime, systemImage: "clock")
                    Label(
                        story.inputMethod == "dictated" ? "Dictated" : "Typed",
                        systemImage: story.inputMethod == "dictated" ? "waveform" : "keyboard"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var currentFolder: StoryFolder? {
        guard let id = story.folderId else { return nil }
        return viewModel.folders.first { $0.id == id }
    }

    private var currentStage: StoryStage { story.resolvedStage }

    private var stageColor: Color {
        switch currentStage {
        case .spark: return AppColors.accent
        case .draft: return AppColors.info
        case .polished: return AppColors.success
        }
    }

    // MARK: - Primary Actions grid

    private var primaryActions: some View {
        VStack(spacing: 10) {
            GlassButton(
                title: "Practice this story",
                icon: "mic.fill",
                style: .primary,
                size: .large,
                fullWidth: true
            ) {
                guard let onStartPractice else { return }
                Haptics.heavy()
                onStartPractice(story, story.practiceDuration)
            }

            HStack(spacing: 10) {
                GlassButton(
                    title: "Warm up",
                    icon: "flame.fill",
                    style: .secondary,
                    fullWidth: true
                ) {
                    guard let onSendToWarmUp else { return }
                    Haptics.medium()
                    onSendToWarmUp(story)
                }

                GlassButton(
                    title: "Drill",
                    icon: "bolt.fill",
                    style: .secondary,
                    fullWidth: true
                ) {
                    guard let onSendToDrill else { return }
                    Haptics.medium()
                    onSendToDrill(story)
                }
            }
        }
    }

    // MARK: - Metrics + chart

    private var metricsSection: some View {
        PracticeMetricsRow(recordings: recordingSummaries)
    }

    @ViewBuilder
    private var practiceChartSection: some View {
        if !chartPoints.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Practice progress")
                PracticeHistoryChart(
                    dataPoints: chartPoints,
                    accentColor: AppColors.primary
                )
            }
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Content") {
                copyButton
                editButton
            }

            Button {
                Haptics.light()
                showingEditor = true
            } label: {
                GlassCard {
                    let text = display.text
                    if text.length > 0 {
                        AttributedTextView(attributedText: text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Tap to start writing…")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityHint("Opens the editor")
        }
    }

    private var editButton: some View {
        Button {
            Haptics.light()
            showingEditor = true
        } label: {
            Image(systemName: "pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Edit story")
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = story.content
            Haptics.success()
            showCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCopied = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                if showCopied { Text("Copied") }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(showCopied ? AppColors.success : .secondary)
            .padding(.horizontal, 10)
            .frame(minWidth: AppLayout.minHitTarget, minHeight: AppLayout.minHitTarget)
            .contentShape(.rect)
            .animation(.easeInOut(duration: 0.2), value: showCopied)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(showCopied ? "Copied" : "Copy text")
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        // Bind once: each `tags` read decodes the Codable column.
        let tags = story.tags
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Tags") {
                    tagActionsMenu
                }

                GlassCard {
                    FlowLayout(spacing: 8) {
                        ForEach(tags) { tag in
                            StoryTagPill(tag: tag, onTap: {
                                Haptics.light()
                                viewModel.applyTagFilter(tag)
                                dismiss()
                            })
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var tagActionsMenu: some View {
        Menu {
            Button {
                pushTagsToVocab()
            } label: {
                Label("Add Words to Vocab", systemImage: "book.closed")
            }
            Button {
                pushTagsToDictation()
            } label: {
                Label("Add Words to Dictation Bank", systemImage: "waveform")
            }
        } label: {
            Image(systemName: "text.badge.plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(.rect)
        }
        .accessibilityLabel("Add tag words to your word banks")
    }

    private func pushTagsToVocab() {
        guard let settings else { return }
        let words = tagWordsForBank()
        guard !words.isEmpty else { return }
        viewModel.addWordsToVocab(words: words, settings: settings)
        showToast("Added \(words.count) to vocab")
    }

    private func pushTagsToDictation() {
        guard let settings else { return }
        let words = tagWordsForBank()
        guard !words.isEmpty else { return }
        viewModel.addWordsToDictation(words: words, settings: settings)
        showToast("Added \(words.count) to dictation")
    }

    private func tagWordsForBank() -> [String] {
        story.tags
            .filter { $0.type != .date }
            .map { $0.value.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func showToast(_ message: String) {
        Haptics.success()
        UIAccessibility.post(notification: .announcement, argument: message)
        withAnimation(.spring(response: 0.3)) { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.25)) { toastMessage = nil }
        }
    }

    /// The glass capsule `LessonDetailView` confirms with. This was the one
    /// opaque teal toast in the app.
    private func toast(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.success)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    // MARK: - Recordings

    @ViewBuilder
    private var recordingsSection: some View {
        if !recordingSummaries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Practice history") {
                    if let avgScore = averageScore {
                        Text("Avg \(avgScore)")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.scoreColor(for: avgScore))
                    }
                }

                // One plate of rows, like History's weeks - not a card per take.
                GlassRowGroup(dividerInset: 14) {
                    ForEach(recordingSummaries) { summary in
                        NavigationLink {
                            RecordingDetailView(
                                recordingId: summary.id.uuidString,
                                source: .story,
                                onPracticeAgain: { recording in
                                    let duration = RecordingDuration(rawValue: recording.targetDuration) ?? .sixty
                                    onStartPractice?(story, duration)
                                }
                            )
                        } label: {
                            takeRow(summary)
                                .padding(14)
                                .contentShape(.rect)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
            }
        }
    }

    private func takeRow(_ summary: PracticeRecordingSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Text(summary.duration.minutesSeconds)
                    if summary.wpm > 0 {
                        Text("\(Int(summary.wpm)) wpm")
                    }
                    if summary.fillerCount > 0 {
                        Text("\(summary.fillerCount) fillers")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let score = summary.score {
                Text("\(score)")
                    .font(.statValue)
                    .foregroundStyle(AppColors.scoreColor(for: score))
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var averageScore: Int? {
        let scores = recordingSummaries.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }

    // MARK: - Menu

    private var detailMenu: some View {
        Menu {
            Button {
                viewModel.toggleFavorite(story)
                Haptics.light()
            } label: {
                Label(
                    story.isFavorite ? "Unpin" : "Pin",
                    systemImage: story.isFavorite ? "pin.slash" : "pin"
                )
            }

            Button {
                showingMoveSheet = true
            } label: {
                Label("Move to Folder…", systemImage: "folder")
            }

            // A Picker, so the current stage wears the system checkmark.
            Picker(selection: Binding(
                get: { story.resolvedStage },
                set: { newStage in
                    viewModel.updateStage(story, stage: newStage)
                    Haptics.light()
                }
            )) {
                ForEach(StoryStage.allCases) { stage in
                    Label(stage.displayName, systemImage: stage.icon)
                        .tag(stage)
                }
            } label: {
                Label("Stage", systemImage: "flag")
            }
            .pickerStyle(.menu)

            Divider()

            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }
}

// MARK: - Display Cache

/// The content card's styled RTFD and word stats, rebuilt only when
/// `updatedAt` moves (every content write bumps it). A reference box held in
/// `@State` so body fills it synchronously: first paint already has the styled
/// text, and later passes (toast flips, a take's Story writes) reuse it
/// without decoding again or writing view state mid-update.
private final class StoryDisplayCache {
    private var stamp: Date?
    private(set) var text = NSAttributedString()
    private(set) var wordCount = 0
    private(set) var readingTime = ""

    func refreshed(for story: Story) -> StoryDisplayCache {
        guard stamp != story.updatedAt else { return self }
        stamp = story.updatedAt
        text = Self.styledForDisplay(story.attributedContent)
        wordCount = story.wordCount
        readingTime = Story.readingTime(words: wordCount)
        return self
    }

    private static func styledForDisplay(_ attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let range = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.foregroundColor, in: range, options: []) { value, subRange, _ in
            if value == nil {
                mutable.addAttribute(.foregroundColor, value: UIColor.white, range: subRange)
            }
        }
        return mutable
    }
}
