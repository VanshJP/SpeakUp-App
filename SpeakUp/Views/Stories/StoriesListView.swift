import SwiftUI
import SwiftData

struct StoriesListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = StoriesViewModel()
    @State private var showingEditor = false
    @State private var selectedStory: Story?
    @State private var showingDeleteAlert = false
    @State private var storyToDelete: Story?
    @State private var showingQuickCapture = false

    var onStartPractice: ((Story) -> Void)?

    var body: some View {
        ZStack {
            AppBackground(style: .primary)

            ScrollView {
                VStack(spacing: 16) {
                    quickCaptureCard

                    if !viewModel.stories.isEmpty {
                        statsCard
                    }

                    stageFilterSection
                    activeFiltersRow

                    if viewModel.stories.isEmpty {
                        EmptyStateCard(
                            icon: "text.book.closed",
                            title: "Your Speaking Journal",
                            message: "Write speech drafts, capture quick ideas, and reflect on practice sessions. Tap the mic to dictate or type to get started."
                        )
                        .padding(.top, 20)
                    } else if viewModel.filteredStories.isEmpty {
                        EmptyStateCard(
                            icon: "magnifyingglass",
                            title: "No Matches",
                            message: "Try a different search or filter."
                        )
                        .padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.filteredStories) { story in
                                Button {
                                    selectedStory = story
                                } label: {
                                    StoryCardRow(
                                        story: story,
                                        onStartPractice: onStartPractice != nil ? {
                                            Haptics.heavy()
                                            onStartPractice?(story)
                                        } : nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        advanceStage(story)
                                    } label: {
                                        let next = nextStage(for: story)
                                        Label(next.displayName, systemImage: next.icon)
                                    }
                                    .tint(AppColors.primary)

                                    Button(role: .destructive) {
                                        storyToDelete = story
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        viewModel.toggleFavorite(story)
                                        Haptics.light()
                                    } label: {
                                        Label(
                                            story.isFavorite ? "Unfavorite" : "Favorite",
                                            systemImage: story.isFavorite ? "star.slash" : "star"
                                        )
                                    }
                                    .tint(.yellow)
                                }
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
                                        Label("Move to…", systemImage: "arrow.right.circle")
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
        .navigationTitle("Journal")
        .toolbarBackground(.hidden, for: .navigationBar)
        .searchable(text: $viewModel.searchText, prompt: "Search journal...")
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
        .sheet(isPresented: $showingQuickCapture) {
            NavigationStack {
                QuickCaptureView(viewModel: viewModel)
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

    // MARK: - Quick Capture Card

    private var quickCaptureCard: some View {
        Button {
            Haptics.medium()
            showingQuickCapture = true
        } label: {
            FeaturedGlassCard(gradientColors: [AppColors.glassTintPrimary, AppColors.glassTintAccent]) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppColors.primary.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: "mic.badge.plus")
                            .font(.title3)
                            .foregroundStyle(AppColors.primary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Quick Entry")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Capture a thought, draft, or reflection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
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

            Section("Stage") {
                Button {
                    withAnimation { viewModel.selectedStageFilter = nil }
                    Haptics.light()
                } label: {
                    HStack {
                        Label("All Stages", systemImage: "square.grid.2x2")
                        if viewModel.selectedStageFilter == nil { Spacer(); Image(systemName: "checkmark") }
                    }
                }

                ForEach(StoryStage.allCases) { stage in
                    Button {
                        withAnimation { viewModel.selectedStageFilter = stage }
                        Haptics.light()
                    } label: {
                        HStack {
                            Label(stage.displayName, systemImage: stage.icon)
                            if viewModel.selectedStageFilter == stage { Spacer(); Image(systemName: "checkmark") }
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
                    icon: "lightbulb",
                    value: "\(sparkCount)",
                    label: "Ideas",
                    color: .yellow
                )

                statsCardDivider

                PromptStatItem(
                    icon: "checkmark.circle",
                    value: "\(polishedCount)",
                    label: "Ready",
                    color: AppColors.success
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

    private var sparkCount: Int {
        viewModel.stories.filter { $0.resolvedStage == .spark }.count
    }

    private var polishedCount: Int {
        viewModel.stories.filter { $0.resolvedStage == .polished }.count
    }

    // MARK: - Filter Pills

    private var stageFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Entry type filters
                entryTypeFilterPill(label: "All", type: nil, icon: "square.grid.2x2")
                ForEach(StoryEntryType.allCases) { entryType in
                    entryTypeFilterPill(label: entryType.displayName, type: entryType, icon: entryType.icon)
                }

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                // Stage filters
                ForEach(StoryStage.allCases) { stage in
                    stageFilterPill(label: stage.displayName, stage: stage, icon: stage.icon)
                }

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                ForEach(StoryTagType.allCases) { tagType in
                    tagFilterPill(label: tagType.displayName, type: tagType)
                }
            }
        }
    }

    private func entryTypeFilterPill(label: String, type: StoryEntryType?, icon: String) -> some View {
        let isSelected = viewModel.selectedEntryTypeFilter == type && viewModel.selectedStageFilter == nil && viewModel.selectedTagFilter == nil
        return Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3)) {
                viewModel.selectedEntryTypeFilter = type
                viewModel.selectedStageFilter = nil
                viewModel.selectedTagFilter = nil
                viewModel.selectedTagValue = nil
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(AppColors.primary.opacity(0.8))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func stageFilterPill(label: String, stage: StoryStage?, icon: String) -> some View {
        let isSelected = viewModel.selectedStageFilter == stage && viewModel.selectedTagFilter == nil
        return Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3)) {
                viewModel.selectedStageFilter = stage
                viewModel.selectedTagFilter = nil
                viewModel.selectedTagValue = nil
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.medium))
            }
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

    private func tagFilterPill(label: String, type: StoryTagType) -> some View {
        let isSelected = viewModel.selectedTagFilter == type
        return Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3)) {
                viewModel.selectedTagFilter = isSelected ? nil : type
                viewModel.selectedStageFilter = nil
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: type.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule().fill(tagTypeColor(type))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
        }
    }

    // MARK: - Active Filters Row

    @ViewBuilder
    private var activeFiltersRow: some View {
        let hasExtrasOnly = viewModel.sortOrder != .updatedAt || viewModel.favoritesOnly || viewModel.selectedTagValue != nil
        if hasExtrasOnly {
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

                    if let tagValue = viewModel.selectedTagValue {
                        activeFilterTag(
                            icon: "tag.fill",
                            label: tagValue,
                            color: .blue
                        ) {
                            viewModel.selectedTagValue = nil
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

    private func nextStage(for story: Story) -> StoryStage {
        switch story.resolvedStage {
        case .spark: return .draft
        case .draft: return .polished
        case .polished: return .spark
        }
    }

    private func advanceStage(_ story: Story) {
        let next = nextStage(for: story)
        viewModel.updateStage(story, stage: next)
        Haptics.medium()
    }
}

// MARK: - Story Card Row

private struct StoryCardRow: View {
    let story: Story
    var onStartPractice: (() -> Void)?

    var body: some View {
        GlassCard(tint: stageColor.opacity(0.04)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if story.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }

                            Text(story.title.isEmpty ? "Untitled Story" : story.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        HStack(spacing: 6) {
                            stageBadge
                            if let occasion = story.resolvedOccasion {
                                Text(occasion.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background { Capsule().fill(.ultraThinMaterial) }
                            }
                        }
                    }

                    Spacer()

                    if let onStartPractice {
                        Button {
                            onStartPractice()
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.caption)
                                .foregroundStyle(AppColors.primary)
                                .padding(8)
                                .background {
                                    Circle().fill(AppColors.primary.opacity(0.15))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !story.contentPreview.isEmpty {
                    Text(story.contentPreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Label("\(story.wordCount)w", systemImage: "text.word.spacing")
                    Label(story.estimatedReadingTime, systemImage: "clock")
                    if story.practiceCount > 0 {
                        Label("\(story.practiceCount)×", systemImage: "mic")
                    }
                    if story.bestScore > 0 {
                        Label("\(story.bestScore)", systemImage: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(AppColors.scoreColor(for: story.bestScore))
                    }

                    Spacer()

                    Text(story.updatedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if !story.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(story.tags.prefix(4)) { tag in
                                StoryTagPill(tag: tag, size: .small)
                            }
                            if story.tags.count > 4 {
                                Text("+\(story.tags.count - 4)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var stageBadge: some View {
        let stage = story.resolvedStage
        return HStack(spacing: 3) {
            Image(systemName: stage.icon)
            Text(stage.displayName)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(stageColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background { Capsule().fill(stageColor.opacity(0.15)) }
    }

    private var stageColor: Color {
        switch story.resolvedStage {
        case .spark: return .yellow
        case .draft: return AppColors.primary
        case .polished: return AppColors.success
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
