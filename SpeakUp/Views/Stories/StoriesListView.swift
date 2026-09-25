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
                    title: "No stories yet",
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
        .alert(StoryDeleteCopy.title, isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let story = storyToDelete {
                    storyToDelete = nil
                    viewModel.deleteStory(story)
                    Haptics.warning()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(StoryDeleteCopy.message)
        }
        .storiesErrorAlert(viewModel)
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
                GlassSectionHeader("Pinned")
                ForEach(pinned) { story in
                    storyRow(story)
                }
            }

            if !unpinned.isEmpty {
                GlassSectionHeader(pinned.isEmpty ? "All stories" : "Stories")
                    .padding(.top, pinned.isEmpty ? 0 : 8)
                ForEach(unpinned) { story in
                    storyRow(story)
                }
            }
        }
    }

    /// Row actions live in the context menu. `.swipeActions` only works on
    /// `List` rows, and these are `LazyVStack` children, so the swipe
    /// actions that used to sit here never fired.
    private func storyRow(_ story: Story) -> some View {
        Button {
            selectedStory = story
        } label: {
            CompactStoryRow(story: story, preview: viewModel.contentPreview(for: story))
        }
        .buttonStyle(GlassPressStyle())
        .contextMenu {
            if let onStartPractice {
                Button {
                    onStartPractice(story, story.practiceDuration)
                } label: {
                    Label("Practice", systemImage: "mic.fill")
                }
            }

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
            // A Picker, so the current order wears the system checkmark. A
            // checkmark Image inside a menu button's label was dropped, and
            // the current sort showed nowhere.
            Picker(selection: Binding(
                get: { viewModel.sortOrder },
                set: { order in
                    Haptics.light()
                    viewModel.setSortOrder(order)
                }
            )) {
                ForEach(StorySortOrder.allCases) { order in
                    Label(order.rawValue, systemImage: order.icon)
                        .tag(order)
                }
            } label: {
                Text("Sort")
            }
            .pickerStyle(.inline)

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
        .accessibilityValue("Sorted by \(viewModel.sortOrder.rawValue)")
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

// MARK: - Shared Copy

/// One confirmation wherever a story is deleted - the list, its page and the
/// editor had three different messages for the same act.
enum StoryDeleteCopy {
    static let title = "Delete Story?"
    static let message = "This story will be permanently deleted. Its practice recordings are kept."
}

// MARK: - Error Alert

/// Shows `StoriesViewModel.errorMessage`, which no Stories view presented:
/// failed saves, moves and deletes were silent. Only the surface on screen
/// presents it, so the list under a pushed story page does not race the
/// page for the same alert.
struct StoriesErrorAlert: ViewModifier {
    let viewModel: StoriesViewModel
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { isOnScreen && viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
    }
}

extension View {
    func storiesErrorAlert(_ viewModel: StoriesViewModel) -> some View {
        modifier(StoriesErrorAlert(viewModel: viewModel))
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
                            .font(.caption2)
                            .foregroundStyle(AppColors.warning)
                            .accessibilityLabel("Pinned")
                    }
                    Text(story.title.isEmpty ? "Untitled" : story.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(story.updatedAt, format: .relative(presentation: .numeric))
                        .foregroundStyle(.secondary)

                    if !preview.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(preview)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.footnote)

                if !tags.isEmpty {
                    tagStrip(tags)
                }
            }

            Spacer(minLength: 8)

            if story.bestScore > 0 {
                Text("\(story.bestScore)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.scoreColor(for: story.bestScore))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(AppColors.scoreColor(for: story.bestScore).opacity(0.15))
                    }
                    .accessibilityLabel("Best score \(story.bestScore)")
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                    .accessibilityLabel("\(overflow) more tags")
            }
        }
    }
}

// MARK: - Story Tag Pill (kept here for reuse by editor/detail)

struct StoryTagPill: View {
    let tag: StoryTag
    var size: TagSize = .regular
    /// Editor: the whole pill removes the tag; its ✕ is the hint. A separate
    /// 7pt ✕ was too small to hit and had no VoiceOver name.
    var onRemove: (() -> Void)?
    /// Detail: filters the list by this tag.
    var onTap: (() -> Void)?

    enum TagSize {
        case small, regular
    }

    var body: some View {
        if let onRemove {
            Button(action: onRemove) {
                pill(showsRemove: true)
                    .frame(minHeight: AppLayout.minHitTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Remove tag \(tag.value)")
        } else if let onTap {
            Button(action: onTap) {
                pill(showsRemove: false)
                    .frame(minHeight: AppLayout.minHitTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityHint("Shows stories with this tag")
        } else {
            pill(showsRemove: false)
        }
    }

    private func pill(showsRemove: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tag.type.icon)
            Text(tag.value)
                .lineLimit(1)
            if showsRemove {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .font(size == .small ? .caption2.weight(.medium) : .caption.weight(.medium))
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
        case .friend: return AppColors.categoryIndigo
        case .date: return AppColors.categoryAmber
        case .location: return AppColors.categorySage
        case .topic: return AppColors.categoryPlum
        case .custom: return AppColors.accent
        }
    }
}
