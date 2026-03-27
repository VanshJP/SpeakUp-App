import SwiftUI
import SwiftData

struct StoriesListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = StoriesViewModel()
    @State private var showingEditor = false
    @State private var selectedStory: Story?
    @State private var showingDeleteAlert = false
    @State private var storyToDelete: Story?

    var onStartPractice: ((Story) -> Void)?

    var body: some View {
        ZStack {
            AppBackground(style: .primary)

            ScrollView {
                VStack(spacing: 16) {
                    tagFilterSection

                    if viewModel.stories.isEmpty {
                        EmptyStateCard(
                            icon: "book.pages",
                            title: "No Stories Yet",
                            message: "Store stories and scripts you want to remember and practice telling."
                        )
                        .padding(.top, 20)
                    } else if viewModel.filteredStories.isEmpty {
                        EmptyStateCard(
                            icon: "magnifyingglass",
                            title: "No Matches",
                            message: "Try a different search term or filter."
                        )
                        .padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.filteredStories) { story in
                                Button {
                                    selectedStory = story
                                } label: {
                                    StoryCardRow(story: story)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        viewModel.toggleFavorite(story)
                                    } label: {
                                        Label(
                                            story.isFavorite ? "Unfavorite" : "Favorite",
                                            systemImage: story.isFavorite ? "star.slash" : "star"
                                        )
                                    }

                                    if let onStartPractice {
                                        Button {
                                            onStartPractice(story)
                                        } label: {
                                            Label("Practice", systemImage: "mic")
                                        }
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        storyToDelete = story
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Stories")
        .searchable(text: $viewModel.searchText, prompt: "Search stories...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(StorySortOrder.allCases) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if viewModel.sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }

                    Button {
                        Haptics.medium()
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                StoryEditorView(viewModel: viewModel)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $selectedStory) { story in
            StoryDetailView(
                story: story,
                viewModel: viewModel,
                onStartPractice: onStartPractice
            )
        }
        .alert("Delete Story?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let story = storyToDelete {
                    viewModel.deleteStory(story)
                    Haptics.warning()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This story and its tags will be permanently deleted. Practice recordings will not be affected.")
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }

    // MARK: - Subviews

    private var tagFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagFilterPill(label: "All", type: nil)
                ForEach(StoryTagType.allCases) { tagType in
                    tagFilterPill(label: tagType.displayName, type: tagType)
                }
            }
        }
    }

    private func tagFilterPill(label: String, type: StoryTagType?) -> some View {
        let isSelected = viewModel.selectedTagFilter == type
        return Button {
            Haptics.light()
            viewModel.selectedTagFilter = type
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        Capsule().fill(AppColors.primary)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
        }
    }
}

// MARK: - Story Card Row

private struct StoryCardRow: View {
    let story: Story

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if story.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    Text(story.title.isEmpty ? "Untitled Story" : story.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Text(story.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !story.contentPreview.isEmpty {
                    Text(story.contentPreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !story.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(story.tags.prefix(5)) { tag in
                                StoryTagPill(tag: tag, size: .small)
                            }
                            if story.tags.count > 5 {
                                Text("+\(story.tags.count - 5)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Label("\(story.practiceCount)", systemImage: "mic")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Label(story.inputMethod == "dictated" ? "Dictated" : "Typed", systemImage: story.inputMethod == "dictated" ? "waveform" : "keyboard")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Story Tag Pill

struct StoryTagPill: View {
    let tag: StoryTag
    var size: TagSize = .regular
    var onRemove: (() -> Void)?

    enum TagSize {
        case small, regular
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tag.type.icon)
            Text(tag.value)
            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
            }
        }
        .font(size == .small ? .system(size: 10, weight: .medium) : .caption.weight(.medium))
        .foregroundStyle(tagColor.opacity(0.9))
        .padding(.horizontal, size == .small ? 8 : 10)
        .padding(.vertical, size == .small ? 4 : 5)
        .background {
            Capsule()
                .fill(tagColor.opacity(0.15))
        }
    }

    private var tagColor: Color {
        switch tag.type {
        case .friend: return .blue
        case .date: return .orange
        case .location: return .green
        case .topic: return .purple
        case .custom: return .gray
        }
    }
}
