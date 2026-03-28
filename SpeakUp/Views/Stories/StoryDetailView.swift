import SwiftUI
import SwiftData

struct StoryDetailView: View {
    var story: Story
    var viewModel: StoriesViewModel
    var onStartPractice: ((Story) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditor = false
    @State private var showingDeleteAlert = false
    @State private var showCopied = false
    @State private var linkedRecordings: [Recording] = []

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    heroHeader
                    practiceSection
                    metricsSection
                    practiceChartSection
                    contentSection
                    tagsSection
                    recordingsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button {
                        viewModel.toggleFavorite(story)
                        Haptics.light()
                    } label: {
                        Label(
                            story.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: story.isFavorite ? "star.slash" : "star"
                        )
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
                        Label("Set Stage", systemImage: "arrow.right.circle")
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
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                StoryEditorView(viewModel: viewModel, existingStory: story)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete Story?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                viewModel.deleteStory(story)
                Haptics.warning()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This story will be permanently deleted.")
        }
        .onAppear {
            linkedRecordings = viewModel.linkedRecordings(for: story)
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    stageBadge
                    if let occasion = story.resolvedOccasion {
                        occasionBadge(occasion)
                    }

                    if story.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    Spacer()

                    Text(story.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(story.title.isEmpty ? "Untitled Story" : story.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    Label("\(story.wordCount) words", systemImage: "text.word.spacing")
                    Label(story.estimatedReadingTime, systemImage: "clock")
                    Label(story.inputMethod == "dictated" ? "Dictated" : "Typed",
                          systemImage: story.inputMethod == "dictated" ? "waveform" : "keyboard")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var stageBadge: some View {
        let stage = story.resolvedStage
        return HStack(spacing: 4) {
            Image(systemName: stage.icon)
                .font(.caption2.weight(.semibold))
            Text(stage.displayName)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(stageColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background { Capsule().fill(stageColor.opacity(0.15)) }
    }

    private func occasionBadge(_ occasion: StoryOccasion) -> some View {
        HStack(spacing: 4) {
            Image(systemName: occasion.icon)
                .font(.caption2.weight(.semibold))
            Text(occasion.rawValue)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background { Capsule().fill(.ultraThinMaterial) }
    }

    private var stageColor: Color {
        switch story.resolvedStage {
        case .spark: return .yellow
        case .draft: return AppColors.primary
        case .polished: return AppColors.success
        }
    }

    // MARK: - Practice Section

    @ViewBuilder
    private var practiceSection: some View {
        if let onStartPractice {
            GlassButton(title: "Practice This Story", icon: "mic.fill", style: .primary, size: .large, fullWidth: true) {
                Haptics.heavy()
                onStartPractice(story)
            }
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        PracticeMetricsRow(recordings: linkedRecordings)
    }

    // MARK: - Practice Chart

    @ViewBuilder
    private var practiceChartSection: some View {
        if !linkedRecordings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Practice Progress", icon: "chart.line.uptrend.xyaxis")
                PracticeHistoryChart(
                    dataPoints: PracticeDataPoint.from(recordings: linkedRecordings),
                    accentColor: stageColor
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
                        if showCopied {
                            Text("Copied")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(showCopied ? AppColors.success : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().fill(showCopied ? AppColors.success.opacity(0.1) : .clear)
                    }
                    .animation(.easeInOut(duration: 0.2), value: showCopied)
                }
            }

            GlassCard {
                Text(story.content.isEmpty ? "No content yet. Tap edit to add your story." : story.content)
                    .font(.body)
                    .foregroundStyle(story.content.isEmpty ? Color.secondary : Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        if !story.tags.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Tags", icon: "tag")

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

    // MARK: - Practice History

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
}
