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
                    if !viewModel.stories.isEmpty {
                        statsCard
                    }

                    tagFilterSection
                    activeFiltersRow

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
                                    StoryCardRow(story: story) { tag in
                                        Haptics.light()
                                        withAnimation(.spring(response: 0.3)) {
                                            viewModel.applyTagFilter(tag)
                                        }
                                    }
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
            ToolbarItem(placement: .topBarLeading) {
                toolbarFilterMenu
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.medium()
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
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

    // MARK: - Toolbar Filter Menu

    private var toolbarFilterMenu: some View {
        Menu {
            Section("Sort") {
                Picker("Sort", selection: $viewModel.sortOrder) {
                    ForEach(StorySortOrder.allCases) { order in
                        Label(order.rawValue, systemImage: order.icon).tag(order)
                    }
                }
            }

            Section("Tag Type") {
                Button {
                    withAnimation { viewModel.selectedTagFilter = nil }
                    Haptics.light()
                } label: {
                    HStack {
                        Label("All Types", systemImage: "square.grid.2x2")
                        if viewModel.selectedTagFilter == nil { Spacer(); Image(systemName: "checkmark") }
                    }
                }

                ForEach(StoryTagType.allCases) { tagType in
                    Button {
                        withAnimation { viewModel.selectedTagFilter = tagType }
                        Haptics.light()
                    } label: {
                        HStack {
                            Label(tagType.displayName, systemImage: tagType.icon)
                            if viewModel.selectedTagFilter == tagType { Spacer(); Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            Section("Show") {
                Button {
                    withAnimation { viewModel.favoritesOnly.toggle() }
                    Haptics.light()
                } label: {
                    HStack {
                        Label("Favorites Only", systemImage: "star")
                        if viewModel.favoritesOnly { Spacer(); Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.body.weight(.semibold))
                .symbolVariant(viewModel.hasActiveFilters ? .fill : .none)
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 0) {
                PromptStatItem(
                    icon: "book.pages",
                    value: "\(viewModel.stories.count)",
                    label: "Stories",
                    color: AppColors.primary
                )

                statsCardDivider

                PromptStatItem(
                    icon: "mic",
                    value: "\(totalPracticeCount)",
                    label: "Practiced",
                    color: .orange
                )

                statsCardDivider

                PromptStatItem(
                    icon: "tag",
                    value: "\(totalTagCount)",
                    label: "Tags",
                    color: .purple
                )

                statsCardDivider

                PromptStatItem(
                    icon: "star.fill",
                    value: "\(favoriteCount)",
                    label: "Favorites",
                    color: .yellow
                )
            }
        }
    }

    private var statsCardDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 40)
    }

    private var totalPracticeCount: Int {
        viewModel.stories.reduce(0) { $0 + $1.practiceCount }
    }

    private var totalTagCount: Int {
        viewModel.stories.reduce(0) { $0 + $1.tags.count }
    }

    private var favoriteCount: Int {
        viewModel.stories.filter(\.isFavorite).count
    }

    // MARK: - Tag Filter Pills

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
            withAnimation(.spring(response: 0.3)) {
                viewModel.selectedTagFilter = type
                if type == nil {
                    viewModel.selectedTagValue = nil
                    viewModel.dateFilterStart = nil
                    viewModel.dateFilterEnd = nil
                }
            }
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

    // MARK: - Active Filters Row

    @ViewBuilder
    private var activeFiltersRow: some View {
        if viewModel.hasActiveFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if viewModel.sortOrder != .updatedAt {
                        activeFilterTag(
                            icon: viewModel.sortOrder.icon,
                            label: "Sort: \(viewModel.sortOrder.rawValue)",
                            color: AppColors.primary
                        ) {
                            viewModel.sortOrder = .updatedAt
                        }
                    }

                    if let tagType = viewModel.selectedTagFilter {
                        activeFilterTag(
                            icon: tagType.icon,
                            label: tagType.displayName,
                            color: tagTypeColor(tagType)
                        ) {
                            viewModel.selectedTagFilter = nil
                            viewModel.selectedTagValue = nil
                            viewModel.dateFilterStart = nil
                            viewModel.dateFilterEnd = nil
                        }
                    }

                    if let tagValue = viewModel.selectedTagValue {
                        activeFilterTag(
                            icon: "tag.fill",
                            label: tagValue,
                            color: .blue
                        ) {
                            viewModel.selectedTagValue = nil
                            viewModel.dateFilterStart = nil
                            viewModel.dateFilterEnd = nil
                        }
                    }

                    if viewModel.favoritesOnly {
                        activeFilterTag(
                            icon: "star.fill",
                            label: "Favorites",
                            color: .yellow
                        ) {
                            viewModel.favoritesOnly = false
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func activeFilterTag(icon: String, label: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3)) {
                onRemove()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(color.opacity(0.12))
            }
        }
    }

    private func tagTypeColor(_ type: StoryTagType) -> Color {
        switch type {
        case .friend: return .blue
        case .date: return .orange
        case .location: return .green
        case .topic: return .purple
        case .custom: return .gray
        }
    }
}

// MARK: - Story Card Row

private struct StoryCardRow: View {
    let story: Story
    var onTagTapped: ((StoryTag) -> Void)?

    var body: some View {
        GlassCard(tint: story.inputMethod == "dictated" ? AppColors.primary.opacity(0.05) : nil) {
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

                    Text(story.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !story.contentPreview.isEmpty {
                    Text(story.contentPreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    // Input method badge
                    HStack(spacing: 3) {
                        Image(systemName: story.inputMethod == "dictated" ? "waveform" : "keyboard")
                        Text(story.inputMethod == "dictated" ? "Dictated" : "Typed")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background { Capsule().fill(AppColors.primary.opacity(0.15)) }

                    Label("\(story.wordCount) words", systemImage: "text.word.spacing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if story.practiceCount > 0 {
                        Label("\(story.practiceCount)", systemImage: "mic")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(story.tags.prefix(3)) { tag in
                        StoryTagPill(tag: tag, size: .small, onTap: onTagTapped != nil ? {
                            onTagTapped?(tag)
                        } : nil)
                    }

                    if story.tags.count > 3 {
                        Text("+\(story.tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
    var onTap: (() -> Void)?

    enum TagSize {
        case small, regular
    }

    var body: some View {
        let content = HStack(spacing: 4) {
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
