import SwiftUI
import SwiftData

struct StoriesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: StoriesViewModel
    @State private var showingEditor = false
    @State private var editingStory: Story?
    @State private var selectedStory: Story?
    @State private var showingDeleteAlert = false
    @State private var storyToDelete: Story?
    @State private var searchBinding = ""
    @State private var folderEditorPresentation: FolderEditorPresentation?
    @State private var movingStory: Story?

    var onStartPractice: ((Story) -> Void)?
    var onSendToWarmUp: ((Story) -> Void)?
    var onSendToDrill: ((Story) -> Void)?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppBackground(style: .primary)

            ScrollView {
                VStack(spacing: 16) {
                    StoryFolderBar(
                        viewModel: viewModel,
                        onCreateFolder: {
                            folderEditorPresentation = .create
                        },
                        onEditFolder: { folder in
                            folderEditorPresentation = .edit(folder)
                        }
                    )
                    .padding(.horizontal, 20)

                    if viewModel.stories.isEmpty {
                        EmptyStateCard(
                            icon: "note.text",
                            title: "Your Notebook",
                            message: "Jot drafts, capture quick ideas, and reflect on practice sessions. Tap + to start."
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    } else if viewModel.filteredStories.isEmpty {
                        EmptyStateCard(
                            icon: "magnifyingglass",
                            title: "Nothing Here",
                            message: "No notes match this filter. Try another folder or search."
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    } else {
                        storyList
                            .padding(.horizontal, 20)
                    }

                    Color.clear.frame(height: 88) // FAB breathing room
                }
                .padding(.vertical, 16)
            }

            floatingActionButton
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
        .navigationTitle("Notes")
        .toolbarBackground(.hidden, for: .navigationBar)
        .searchable(text: $searchBinding, prompt: "Search notes…")
        .onChange(of: searchBinding) { _, newValue in
            viewModel.setSearch(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbarSortMenu
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                StoryEditorView(
                    viewModel: viewModel,
                    existingStory: editingStory,
                    initialFolderId: currentFolderId,
                    onStartPractice: onStartPractice,
                    onSendToWarmUp: onSendToWarmUp,
                    onSendToDrill: onSendToDrill
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
        .navigationDestination(item: $selectedStory) { story in
            StoryDetailView(
                story: story,
                viewModel: viewModel,
                onStartPractice: onStartPractice,
                onSendToWarmUp: onSendToWarmUp,
                onSendToDrill: onSendToDrill
            )
        }
        .alert("Delete Note?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let story = storyToDelete {
                    viewModel.deleteStory(story)
                    Haptics.warning()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This note and its tags will be permanently deleted. Linked recordings will not be removed.")
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await viewModel.loadStories()
            }
        }
    }

    // MARK: - Story List

    private var storyList: some View {
        LazyVStack(spacing: 16, pinnedViews: []) {
            if !viewModel.pinnedStories.isEmpty {
                section(title: "Pinned", icon: "pin.fill", stories: viewModel.pinnedStories)
            }

            if !viewModel.unpinnedStories.isEmpty {
                section(
                    title: viewModel.pinnedStories.isEmpty ? "All Notes" : "Notes",
                    icon: "note.text",
                    stories: viewModel.unpinnedStories
                )
            }
        }
    }

    private func section(title: String, icon: String, stories: [Story]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(stories) { story in
                    storyRow(story)
                }
            }
        }
    }

    private func storyRow(_ story: Story) -> some View {
        Button {
            selectedStory = story
        } label: {
            CompactStoryRow(story: story)
        }
        .buttonStyle(.plain)
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
            .tint(.yellow)
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
                    onStartPractice(story)
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

    // MARK: - Floating Action Button

    private var floatingActionButton: some View {
        Button {
            Haptics.heavy()
            editingStory = nil
            showingEditor = true
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background {
                    Circle()
                        .fill(AppColors.primary)
                        .shadow(color: AppColors.primary.opacity(0.4), radius: 12, y: 4)
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toolbar

    private var toolbarSortMenu: some View {
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
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.body.weight(.semibold))
        }
    }

    // MARK: - Helpers

    private var currentFolderId: UUID? {
        if case .folder(let id) = viewModel.folderSelection { return id }
        return nil
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if story.isFavorite {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                    Text(story.title.isEmpty ? "Untitled" : story.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(story.updatedAt, format: .relative(presentation: .numeric))
                        .foregroundStyle(.secondary)

                    if !story.contentPreview.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(story.contentPreview)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 13))

                if !story.tags.isEmpty {
                    tagStrip
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                }
        }
    }

    private var tagStrip: some View {
        let visible = Array(story.tags.prefix(3))
        let overflow = story.tags.count - visible.count
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
        case .friend: return .blue
        case .date: return .orange
        case .location: return .green
        case .topic: return .purple
        case .custom: return .gray
        }
    }
}
