import SwiftUI
import SwiftData

struct StoriesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: StoriesViewModel
    @Binding var selectedStory: Story?
    @Binding var searchText: String
    @State private var showingDeleteAlert = false
    @State private var storyToDelete: Story?
    @State private var folderEditorPresentation: FolderEditorPresentation?
    @State private var movingStory: Story?

    var onStartPractice: ((Story, RecordingDuration) -> Void)?
    var onSendToWarmUp: ((Story) -> Void)?
    var onSendToDrill: ((Story) -> Void)?

    init(
        viewModel: StoriesViewModel,
        selectedStory: Binding<Story?>,
        searchText: Binding<String>,
        onStartPractice: ((Story, RecordingDuration) -> Void)? = nil,
        onSendToWarmUp: ((Story) -> Void)? = nil,
        onSendToDrill: ((Story) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self._selectedStory = selectedStory
        self._searchText = searchText
        self.onStartPractice = onStartPractice
        self.onSendToWarmUp = onSendToWarmUp
        self.onSendToDrill = onSendToDrill
    }

    var body: some View {
        VStack(spacing: 16) {
            InlineSearchField(text: $searchText, prompt: "Search stories…") {
                sortMenu
            }

            StoryFolderBar(
                viewModel: viewModel,
                onCreateFolder: {
                    folderEditorPresentation = .create
                },
                onEditFolder: { folder in
                    folderEditorPresentation = .edit(folder)
                }
            )

            if viewModel.stories.isEmpty {
                EmptyStateCard(
                    icon: "note.text",
                    title: "Your stories",
                    message: "Write scripts, capture quick notes, and reflect on practice sessions. Tap + to start."
                )
                .padding(.top, 20)
            } else if viewModel.filteredStories.isEmpty {
                EmptyStateCard(
                    icon: "magnifyingglass",
                    title: "Nothing here",
                    message: "No stories match this filter. Try another folder or search."
                )
                .padding(.top, 20)
            } else {
                storyList
            }
        }
        .sheet(item: $folderEditorPresentation) { presentation in
            NavigationStack {
                StoryFolderEditorSheet(
                    viewModel: viewModel,
                    editing: presentation.folder
                )
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $movingStory) { story in
            NavigationStack {
                StoryMoveFolderSheet(
                    viewModel: viewModel,
                    story: story
                )
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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
            Text("This story and its tags will be permanently deleted. Linked recordings will not be removed.")
        }
        .onAppear {
            viewModel.configure(with: modelContext)
            viewModel.surfaceAppeared()
        }
        .onDisappear {
            viewModel.surfaceDisappeared()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                viewModel.loadStories()
            }
        }
    }

    // MARK: - Story List

    /// Rows are direct children so only on-screen rows build; the extra top
    /// padding keeps the old 16pt gap between the two sections.
    private var storyList: some View {
        let pinned = viewModel.pinnedStories
        let unpinned = viewModel.unpinnedStories
        return LazyVStack(alignment: .leading, spacing: 8) {
            if !pinned.isEmpty {
                GlassSectionHeader("Pinned", icon: "pin.fill")
                ForEach(pinned) { story in
                    storyRow(story)
                }
            }

            if !unpinned.isEmpty {
                GlassSectionHeader(pinned.isEmpty ? "All Stories" : "Stories", icon: "note.text")
                    .padding(.top, pinned.isEmpty ? 0 : 8)
                ForEach(unpinned) { story in
                    storyRow(story)
                }
            }
        }
    }

    private func storyRow(_ story: Story) -> some View {
        Button {
            selectedStory = story
        } label: {
            CompactStoryRow(story: story, preview: viewModel.contentPreview(for: story))
        }
        .buttonStyle(GlassPressStyle())
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                viewModel.toggleFavorite(story)
                Haptics.light()
            } label: {
                Label(
                    story.isFavorite ? "Unpin" : "Pin",
                    systemImage: story.isFavorite ? "pin.slash" : "pin"
                )
            }
            .tint(AppColors.warning)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                storyToDelete = story
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                movingStory = story
            } label: {
                Label("Move", systemImage: "folder")
            }
            .tint(AppColors.primary)
        }
        .contextMenu {
            if let onStartPractice {
                Button {
                    onStartPractice(story, .sixty)
                } label: {
                    Label("Practice", systemImage: "mic.fill")
                }
            }

            Button {
                viewModel.toggleFavorite(story)
            } label: {
                Label(
                    story.isFavorite ? "Unpin" : "Pin",
                    systemImage: story.isFavorite ? "pin.slash" : "pin"
                )
            }

            Button {
                movingStory = story
            } label: {
                Label("Move to Folder…", systemImage: "folder")
            }

            if let onSendToWarmUp {
                Button {
                    onSendToWarmUp(story)
                } label: {
                    Label("Send to Warm-Up", systemImage: "flame")
                }
            }

            if let onSendToDrill {
                Button {
                    onSendToDrill(story)
                } label: {
                    Label("Send to Drill", systemImage: "bolt")
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

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            Section("Sort") {
                ForEach(StorySortOrder.allCases) { order in
                    Button {
                        Haptics.light()
                        viewModel.setSortOrder(order)
                    } label: {
                        HStack {
                            Label(order.rawValue, systemImage: order.icon)
                            if viewModel.sortOrder == order { Spacer(); Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            if viewModel.hasActiveFilters {
                Section {
                    Button {
                        Haptics.light()
                        withAnimation { viewModel.clearAllFilters() }
                    } label: {
                        Label("Clear Filters", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(viewModel.hasActiveFilters ? AppColors.primary : Color.white.opacity(0.75))
                .symbolVariant(viewModel.hasActiveFilters ? .fill : .none)
                .headerIconChrome()
        }
        .accessibilityLabel("Sort and filter stories")
    }

}

// MARK: - Folder Editor Presentation

enum FolderEditorPresentation: Identifiable {
    case create
    case edit(StoryFolder)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let folder): return folder.id.uuidString
        }
    }

    var folder: StoryFolder? {
        if case .edit(let folder) = self { return folder }
        return nil
    }
}

// MARK: - Compact Story Row

private struct CompactStoryRow: View {
    let story: Story
    let preview: String

    var body: some View {
        GlassCard(padding: 14) {
            rowContent
        }
    }

    private var rowContent: some View {
        // Bind once: each `tags` read decodes the Codable column.
        let tags = story.tags
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if story.isFavorite {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.warning)
                    }
                    Text(story.title.isEmpty ? "Untitled" : story.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(story.updatedAt, format: .relative(presentation: .numeric))
                        .foregroundStyle(.secondary)

                    if !preview.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(preview)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 13))

                if !tags.isEmpty {
                    tagStrip(tags)
                }
            }

            Spacer(minLength: 8)

            if story.bestScore > 0 {
                Text("\(story.bestScore)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.scoreColor(for: story.bestScore))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(AppColors.scoreColor(for: story.bestScore).opacity(0.15))
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagStrip(_ tags: [StoryTag]) -> some View {
        let visible = Array(tags.prefix(3))
        let overflow = tags.count - visible.count
        return HStack(spacing: 4) {
            ForEach(visible) { tag in
                StoryTagPill(tag: tag, size: .small)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
            }
        }
    }
}

// MARK: - Story Tag Pill (kept here for reuse by editor/detail)

struct StoryTagPill: View {
    let tag: StoryTag
    var size: TagSize = .regular
    var onRemove: (() -> Void)?
    var onTap: (() -> Void)?

    enum TagSize {
        case small, regular
    }

    var body: some View {
        let content = HStack(spacing: 4) {
            Image(systemName: tag.type.icon)
            Text(tag.value)
                .lineLimit(1)
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

        if let onTap {
            Button {
                onTap()
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var tagColor: Color {
        switch tag.type {
        case .friend: return AppColors.categoryIndigo
        case .date: return AppColors.categoryAmber
        case .location: return AppColors.categorySage
        case .topic: return AppColors.categoryPlum
        case .custom: return AppColors.accent
        }
    }
}
