import SwiftUI
import SwiftData

struct StoryDetailView: View {
    var story: Story
    var viewModel: StoriesViewModel
    var onStartPractice: ((Story) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var userSettings: [UserSettings]

    @State private var showingEditor = false
    @State private var showingWordPicker = false
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
                    statsGrid
                    contentSection
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

                    Button {
                        showingWordPicker = true
                    } label: {
                        Label("Add to Word Bank", systemImage: "text.badge.plus")
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
        .sheet(isPresented: $showingWordPicker) {
            NavigationStack {
                StoryWordPickerSheet(
                    content: story.content,
                    viewModel: viewModel
                )
            }
            .presentationDetents([.medium, .large])
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
                    HStack(spacing: 5) {
                        Image(systemName: story.inputMethod == "dictated" ? "waveform" : "keyboard")
                            .font(.caption2.weight(.semibold))
                        Text(story.inputMethod == "dictated" ? "Dictated" : "Typed")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(AppColors.primary.opacity(0.15))
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

                if !story.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(story.tags.prefix(5)) { tag in
                                StoryTagPill(tag: tag, size: .small, onTap: {
                                    Haptics.light()
                                    viewModel.applyTagFilter(tag)
                                    dismiss()
                                })
                            }
                            if story.tags.count > 5 {
                                Text("+\(story.tags.count - 5)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 0) {
                PromptStatItem(
                    icon: "text.word.spacing",
                    value: "\(story.wordCount)",
                    label: "Words",
                    color: AppColors.primary
                )

                statsGridDivider

                PromptStatItem(
                    icon: "mic",
                    value: "\(story.practiceCount)",
                    label: "Practiced",
                    color: .orange
                )

                statsGridDivider

                PromptStatItem(
                    icon: "clock",
                    value: storyAge,
                    label: "Age",
                    color: .blue
                )
            }
        }
    }

    private var statsGridDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 40)
    }

    private var storyAge: String {
        let now = Date()
        let components = Calendar.current.dateComponents([.month, .day, .hour], from: story.createdAt, to: now)
        if let months = components.month, months >= 1 {
            return "\(months)mo"
        } else if let days = components.day, days >= 1 {
            return "\(days)d"
        } else if let hours = components.hour, hours >= 1 {
            return "\(hours)h"
        }
        return "Today"
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
                Text(story.content.isEmpty ? "No content yet." : story.content)
                    .font(.body)
                    .foregroundStyle(story.content.isEmpty ? Color.secondary : Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Practice

    @ViewBuilder
    private var practiceSection: some View {
        if let onStartPractice {
            GlassButton(title: "Practice This Story", icon: "mic.fill", style: .primary, size: .large, fullWidth: true) {
                Haptics.heavy()
                onStartPractice(story)
            }
        }
    }

    // MARK: - Practice History

    private var recordingsSection: some View {
        Group {
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
                                GlassCard {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                            Text(recording.formattedDuration)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if let score = recording.analysis?.speechScore.overall {
                                            Text("\(score)")
                                                .font(.system(size: 24, weight: .bold, design: .rounded))
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
    }

    private var averageScore: Int? {
        let scores = linkedRecordings.compactMap { $0.analysis?.speechScore.overall }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }
}
