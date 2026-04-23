import SwiftUI
import SwiftData
import UIKit

struct StoryDetailView: View {
    var story: Story
    var viewModel: StoriesViewModel
    var onStartPractice: ((Story) -> Void)?
    var onSendToWarmUp: ((Story) -> Void)?
    var onSendToDrill: ((Story) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    @State private var showingDeleteAlert = false
    @State private var showCopied = false
    @State private var linkedRecordings: [Recording] = []
    @State private var showingMoveSheet = false
    @State private var showingEditor = false
    @State private var toastMessage: String?

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    heroHeader
                    primaryActions
                    if !linkedRecordings.isEmpty {
                        metricsSection
                        practiceChartSection
                    }
                    contentSection
                    tagsSection
                    recordingsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            if let toastMessage {
                Text(toastMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        Capsule().fill(AppColors.primary.opacity(0.9))
                    }
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                detailMenu
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
            linkedRecordings = viewModel.linkedRecordings(for: story)
        }) {
            NavigationStack {
                StoryEditorView(
                    viewModel: viewModel,
                    existingStory: story,
                    onStartPractice: onStartPractice,
                    onSendToWarmUp: onSendToWarmUp,
                    onSendToDrill: onSendToDrill
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete Note?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                viewModel.deleteStory(story)
                Haptics.warning()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This note will be permanently deleted.")
        }
        .onAppear {
            linkedRecordings = viewModel.linkedRecordings(for: story)
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    folderChip
                    if story.isFavorite {
                        HStack(spacing: 3) {
                            Image(systemName: "pin.fill")
                            Text("Pinned")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(Color.yellow.opacity(0.15)) }
                    }

                    Spacer()

                    Text(story.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(story.title.isEmpty ? "Untitled" : story.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Label("\(story.wordCount) words", systemImage: "text.word.spacing")
                    Label(story.estimatedReadingTime, systemImage: "clock")
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

    private var folderChip: some View {
        Button {
            showingMoveSheet = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: currentFolder?.systemImage ?? "tray.full")
                    .font(.system(size: 10, weight: .semibold))
                Text(currentFolder?.name ?? "All Notes")
                    .font(.caption2.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(folderColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background { Capsule().fill(folderColor.opacity(0.15)) }
        }
        .buttonStyle(.plain)
    }

    private var currentFolder: StoryFolder? {
        guard let id = story.folderId else { return nil }
        return viewModel.folders.first { $0.id == id }
    }

    private var folderColor: Color {
        if let folder = currentFolder {
            return Color(hex: folder.colorHex)
        }
        return AppColors.primary
    }

    // MARK: - Primary Actions grid

    private var primaryActions: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return LazyVGrid(columns: columns, spacing: 10) {
            PracticeToolCard(
                icon: "mic.fill",
                title: "Practice",
                subtitle: "Record from this note",
                color: AppColors.primary
            ) {
                guard let onStartPractice else { return }
                Haptics.heavy()
                onStartPractice(story)
            }

            PracticeToolCard(
                icon: "flame.fill",
                title: "Warm-Up",
                subtitle: "Prep your voice",
                color: .orange
            ) {
                guard let onSendToWarmUp else { return }
                Haptics.medium()
                onSendToWarmUp(story)
            }

            PracticeToolCard(
                icon: "bolt.fill",
                title: "Drill",
                subtitle: "Impromptu sprint",
                color: .indigo
            ) {
                guard let onSendToDrill else { return }
                Haptics.medium()
                onSendToDrill(story)
            }

            PracticeToolCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "Score",
                subtitle: story.bestScore > 0 ? "Best: \(story.bestScore)" : "No practice yet",
                color: story.bestScore > 0 ? AppColors.scoreColor(for: story.bestScore) : .gray
            ) {}
        }
    }

    // MARK: - Metrics + chart

    private var metricsSection: some View {
        PracticeMetricsRow(recordings: linkedRecordings)
    }

    @ViewBuilder
    private var practiceChartSection: some View {
        if !linkedRecordings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Practice Progress", icon: "chart.line.uptrend.xyaxis")
                PracticeHistoryChart(
                    dataPoints: PracticeDataPoint.from(recordings: linkedRecordings),
                    accentColor: AppColors.primary
                )
            }
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GlassSectionHeader("Content", icon: "doc.text")
                Spacer()
                copyButton
                Button {
                    Haptics.light()
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }

            Button {
                Haptics.light()
                showingEditor = true
            } label: {
                GlassCard {
                    if story.attributedContent.length > 0 {
                        AttributedTextView(attributedText: styledForDisplay(story.attributedContent))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Tap to start writing…")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)
        }
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
            .padding(.vertical, 5)
            .animation(.easeInOut(duration: 0.2), value: showCopied)
        }
    }

    /// Force white base color on read-only render so dark mode text is legible.
    private func styledForDisplay(_ attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let range = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.foregroundColor, in: range, options: []) { value, subRange, _ in
            if value == nil {
                mutable.addAttribute(.foregroundColor, value: UIColor.white, range: subRange)
            }
        }
        return mutable
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        if !story.tags.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    GlassSectionHeader("Tags", icon: "tag")
                    Spacer()
                    tagActionsMenu
                }

                GlassCard {
                    FlowLayout(spacing: 8) {
                        ForEach(story.tags) { tag in
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
            Image(systemName: "arrow.up.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(6)
        }
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
        withAnimation(.spring(response: 0.3)) { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.25)) { toastMessage = nil }
        }
    }

    // MARK: - Recordings

    @ViewBuilder
    private var recordingsSection: some View {
        if !linkedRecordings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    GlassSectionHeader("Practice History", icon: "waveform")
                    Spacer()
                    if let avgScore = averageScore {
                        Text("Avg \(avgScore)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColors.scoreColor(for: avgScore))
                    }
                }

                LazyVStack(spacing: 10) {
                    ForEach(linkedRecordings) { recording in
                        NavigationLink {
                            RecordingDetailView(recordingId: recording.id.uuidString)
                        } label: {
                            GlassCard(padding: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                        HStack(spacing: 8) {
                                            Text(recording.formattedDuration)
                                            if let wpm = recording.analysis?.wordsPerMinute, wpm > 0 {
                                                Text("\(Int(wpm)) wpm")
                                            }
                                            let fillerCount = recording.analysis?.totalFillerCount ?? 0
                                            if fillerCount > 0 {
                                                Text("\(fillerCount) fillers")
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if let score = recording.analysis?.speechScore.overall {
                                        Text("\(score)")
                                            .font(.system(size: 22, weight: .bold, design: .rounded))
                                            .foregroundStyle(AppColors.scoreColor(for: score))
                                    }

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var averageScore: Int? {
        let scores = linkedRecordings.compactMap { $0.analysis?.speechScore.overall }
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

            Menu {
                ForEach(StoryStage.allCases) { stage in
                    Button {
                        viewModel.updateStage(story, stage: stage)
                        Haptics.light()
                    } label: {
                        Label(stage.displayName, systemImage: stage.icon)
                    }
                }
            } label: {
                Label("Stage", systemImage: "flag")
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .frame(width: 28, height: 28)
        }
    }
}
