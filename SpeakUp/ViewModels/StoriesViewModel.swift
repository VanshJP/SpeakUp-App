import Foundation
import SwiftUI
import SwiftData
import CoreData

@MainActor @Observable
class StoriesViewModel {
    var stories: [Story] = []
    var folders: [StoryFolder] = []
    var filteredStories: [Story] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Filters (no per-property didSet — use setFilter/clearAllFilters)

    private(set) var searchText = ""
    private(set) var selectedTagFilter: StoryTagType?
    private(set) var selectedTagValue: String?
    private(set) var selectedStageFilter: StoryStage?
    private(set) var dateFilterStart: Date?
    private(set) var dateFilterEnd: Date?
    private(set) var favoritesOnly: Bool = false
    private(set) var sortOrder: StorySortOrder = .updatedAt
    private(set) var selectedEntryTypeFilter: StoryEntryType?

    /// Selected folder scope. `nil` = All Notes. Pinned pseudo-folder uses `folderSelection`.
    var folderSelection: FolderSelection = .all

    var hasActiveFilters: Bool {
        selectedTagFilter != nil || selectedTagValue != nil ||
        selectedStageFilter != nil || dateFilterStart != nil ||
        favoritesOnly || sortOrder != .updatedAt ||
        selectedEntryTypeFilter != nil
    }

    // MARK: - Pinned split

    var pinnedStories: [Story] {
        filteredStories.filter { $0.isFavorite }
    }

    var unpinnedStories: [Story] {
        filteredStories.filter { !$0.isFavorite }
    }

    private let taggingService = StoryTaggingService()

    private var modelContext: ModelContext?
    private var hasConfigured = false
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var remoteChangeObservationTask: Task<Void, Never>?
    @ObservationIgnored private var remoteChangeRefreshTask: Task<Void, Never>?

    func configure(with context: ModelContext) {
        if !hasConfigured {
            hasConfigured = true
            self.modelContext = context
            startRemoteChangeObservation()
        }
        Task {
            loadStories()
        }
    }

    // MARK: - Load

    func loadStories() {
        guard let context = modelContext else { return }
        isLoading = true
        defer { isLoading = false }

        let descriptor = FetchDescriptor<Story>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let folderDescriptor = FetchDescriptor<StoryFolder>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )

        do {
            stories = try context.fetch(descriptor)
            folders = try context.fetch(folderDescriptor)
            recomputeFilteredStories()
        } catch {
            errorMessage = "Failed to load stories: \(error.localizedDescription)"
        }
    }

    private func startRemoteChangeObservation() {
        remoteChangeObservationTask?.cancel()
        remoteChangeObservationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                guard !Task.isCancelled, let self else { break }
                self.scheduleRemoteRefresh()
            }
        }
    }

    /// Debounce CloudKit notification bursts: each incoming notification resets
    /// a 250ms timer and only the final trailing edge triggers a reload.
    private func scheduleRemoteRefresh() {
        remoteChangeRefreshTask?.cancel()
        remoteChangeRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.loadStories()
        }
    }

    // MARK: - Folder CRUD

    @discardableResult
    func createFolder(name: String, systemImage: String = "folder.fill", colorHex: String = "#0D8488") -> StoryFolder? {
        guard let context = modelContext else { return nil }
        let order = (folders.map(\.sortOrder).max() ?? -1) + 1
        let folder = StoryFolder(name: name, systemImage: systemImage, colorHex: colorHex, sortOrder: order)
        context.insert(folder)

        do {
            try context.save()
            folders.append(folder)
            return folder
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
            return nil
        }
    }

    func updateFolder(_ folder: StoryFolder, name: String? = nil, systemImage: String? = nil, colorHex: String? = nil) {
        guard let context = modelContext else { return }
        if let name { folder.name = name }
        if let systemImage { folder.systemImage = systemImage }
        if let colorHex { folder.colorHex = colorHex }

        do {
            try context.save()
        } catch {
            errorMessage = "Failed to update folder: \(error.localizedDescription)"
        }
    }

    func deleteFolder(_ folder: StoryFolder) {
        guard let context = modelContext else { return }

        let targetId = folder.id
        for story in stories where story.folderId == targetId {
            story.folderId = nil
        }
        context.delete(folder)

        do {
            try context.save()
            folders.removeAll { $0.id == targetId }
            if case .folder(let id) = folderSelection, id == targetId {
                folderSelection = .all
            }
            recomputeFilteredStories()
        } catch {
            errorMessage = "Failed to delete folder: \(error.localizedDescription)"
        }
    }

    func moveStory(_ story: Story, toFolder folderId: UUID?) {
        guard let context = modelContext else { return }
        story.folderId = folderId
        story.updatedAt = Date()

        do {
            try context.save()
            recomputeFilteredStories()
        } catch {
            errorMessage = "Failed to move story: \(error.localizedDescription)"
        }
    }

    func countForFolder(_ selection: FolderSelection) -> Int {
        switch selection {
        case .all:
            return stories.count
        case .pinned:
            return stories.filter { $0.isFavorite }.count
        case .folder(let id):
            return stories.filter { $0.folderId == id }.count
        }
    }

    func setFolderSelection(_ selection: FolderSelection) {
        folderSelection = selection
        recomputeFilteredStories()
    }

    // MARK: - Filter Setters (batched — single recompute per call)

    func setSearch(_ text: String) {
        searchText = text
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            recomputeFilteredStories()
        }
    }

    func setEntryTypeFilter(_ type: StoryEntryType?) {
        selectedEntryTypeFilter = type
        selectedStageFilter = nil
        selectedTagFilter = nil
        selectedTagValue = nil
        recomputeFilteredStories()
    }

    func setStageFilter(_ stage: StoryStage?) {
        selectedStageFilter = stage
        selectedTagFilter = nil
        selectedTagValue = nil
        recomputeFilteredStories()
    }

    func setTagFilter(_ type: StoryTagType?) {
        selectedTagFilter = type
        selectedStageFilter = nil
        if type == nil { selectedTagValue = nil }
        recomputeFilteredStories()
    }

    func setTagValue(_ value: String?) {
        selectedTagValue = value
        recomputeFilteredStories()
    }

    func setSortOrder(_ order: StorySortOrder) {
        sortOrder = order
        recomputeFilteredStories()
    }

    func toggleFavoritesOnly() {
        favoritesOnly.toggle()
        recomputeFilteredStories()
    }

    // MARK: - Filtering & Sorting

    func recomputeFilteredStories() {
        var result = stories

        switch folderSelection {
        case .all:
            break
        case .pinned:
            result = result.filter { $0.isFavorite }
        case .folder(let id):
            result = result.filter { $0.folderId == id }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { story in
                if story.title.range(of: query, options: .caseInsensitive) != nil { return true }
                if story.content.range(of: query, options: .caseInsensitive) != nil { return true }
                return story.tags.contains { $0.value.range(of: query, options: .caseInsensitive) != nil }
            }
        }

        if let entryTypeFilter = selectedEntryTypeFilter {
            result = result.filter { $0.resolvedEntryType == entryTypeFilter }
        }

        if let stageFilter = selectedStageFilter {
            result = result.filter { $0.resolvedStage == stageFilter }
        }

        if let filter = selectedTagFilter {
            result = result.filter { story in
                story.tags.contains { $0.type == filter }
            }
        }

        if let tagValue = selectedTagValue {
            let lower = tagValue.lowercased()
            result = result.filter { story in
                story.tags.contains { $0.value.lowercased() == lower }
            }
        }

        if let start = dateFilterStart, let end = dateFilterEnd {
            result = result.filter { story in
                story.tags.contains { tag in
                    guard tag.type == .date, let parsed = tag.parsedDate else { return false }
                    return parsed >= start && parsed <= end
                }
            }
        }

        if favoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        switch sortOrder {
        case .updatedAt:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .createdAt:
            result.sort { $0.createdAt > $1.createdAt }
        case .alphabetical:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .mostPracticed:
            result.sort { $0.practiceCount > $1.practiceCount }
        }

        filteredStories = result
    }

    func clearAllFilters() {
        selectedTagFilter = nil
        selectedTagValue = nil
        selectedStageFilter = nil
        dateFilterStart = nil
        dateFilterEnd = nil
        favoritesOnly = false
        sortOrder = .updatedAt
        selectedEntryTypeFilter = nil
        recomputeFilteredStories()
    }

    func applyTagFilter(_ tag: StoryTag) {
        selectedTagFilter = tag.type
        selectedTagValue = tag.value

        if tag.type == .date, let parsed = tag.parsedDate {
            let calendar = Calendar.current
            dateFilterStart = calendar.date(byAdding: .month, value: -1, to: parsed) ?? parsed
            dateFilterEnd = calendar.date(byAdding: .month, value: 1, to: parsed) ?? parsed
        }
        recomputeFilteredStories()
    }

    // MARK: - CRUD

    @discardableResult
    func createStory(
        title: String,
        content: String,
        tags: [StoryTag] = [],
        inputMethod: String = "typed",
        stage: StoryStage = .spark,
        occasion: StoryOccasion? = nil,
        entryType: StoryEntryType = .story,
        folderId: UUID? = nil
    ) -> Story? {
        guard let context = modelContext else { return nil }

        let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let estimatedSeconds = max(0, words * 60 / 150)

        let story = Story(
            title: title,
            content: content,
            tags: tags,
            inputMethod: inputMethod,
            storyStage: stage.rawValue,
            occasion: occasion?.rawValue,
            estimatedDurationSeconds: estimatedSeconds,
            entryType: entryType.rawValue,
            folderId: folderId
        )
        context.insert(story)

        do {
            try context.save()
            stories.insert(story, at: 0)
            recomputeFilteredStories()

            WidgetDataProvider.updateLatestStory(
                title: title.isEmpty ? "Untitled Spark" : title
            )

            return story
        } catch {
            errorMessage = "Failed to save story: \(error.localizedDescription)"
            return nil
        }
    }

    func updateStory(
        _ story: Story,
        title: String,
        content: String,
        tags: [StoryTag],
        stage: StoryStage? = nil,
        occasion: StoryOccasion? = nil
    ) {
        guard let context = modelContext else { return }

        story.title = title
        story.content = content
        story.tags = tags
        story.updatedAt = Date()
        if let stage { story.storyStage = stage.rawValue }
        story.occasion = occasion?.rawValue
        let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        story.estimatedDurationSeconds = max(0, words * 60 / 150)

        do {
            try context.save()
            recomputeFilteredStories()
        } catch {
            errorMessage = "Failed to update story: \(error.localizedDescription)"
        }
    }

    /// Auto-save draft changes during editing. Writes the title plus the full
    /// attributed (rich text) content; `Story.attributedContent` keeps the
    /// plain `content` mirror in sync transparently.
    func autoSave(_ story: Story, title: String, attributed: NSAttributedString) {
        guard let context = modelContext else { return }

        story.title = title
        story.attributedContent = attributed
        story.updatedAt = Date()
        let words = attributed.string.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        story.estimatedDurationSeconds = max(0, words * 60 / 150)

        do {
            try context.save()
        } catch {
            // best-effort
        }
    }

    /// Merge newly extracted tags
    func appendTags(to story: Story, tags newTags: [StoryTag]) {
        guard let context = modelContext, !newTags.isEmpty else { return }

        var merged = story.tags
        for tag in newTags where !merged.contains(where: {
            $0.type == tag.type && $0.value.lowercased() == tag.value.lowercased()
        }) {
            merged.append(tag)
        }

        guard merged.count != story.tags.count else { return }

        story.tags = merged
        story.updatedAt = Date()

        do {
            try context.save()
            recomputeFilteredStories()
        } catch {
            errorMessage = "Failed to update tags: \(error.localizedDescription)"
        }
    }

    func updateStage(_ story: Story, stage: StoryStage) {
        guard let context = modelContext else { return }

        story.storyStage = stage.rawValue
        story.updatedAt = Date()

        do {
            try context.save()
            recomputeFilteredStories()
        } catch {
            errorMessage = "Failed to update story stage: \(error.localizedDescription)"
        }
    }

    func deleteStory(_ story: Story) {
        guard let context = modelContext else { return }

        context.delete(story)

        do {
            try context.save()
            stories.removeAll { $0.id == story.id }
            recomputeFilteredStories()
        } catch {
            context.rollback()
            errorMessage = "Failed to delete story: \(error.localizedDescription)"
        }
    }

    /// Delete a story only if it has no meaningful content (used for empty draft cleanup).
    func deleteIfEmpty(_ story: Story) {
        let trimmedTitle = story.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = story.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty && trimmedContent.isEmpty else { return }
        deleteStory(story)
    }

    func toggleFavorite(_ story: Story) {
        guard let context = modelContext else { return }

        story.isFavorite.toggle()
        story.updatedAt = Date()

        do {
            try context.save()
            recomputeFilteredStories()
        } catch {
            errorMessage = "Failed to update story: \(error.localizedDescription)"
        }
    }

    // MARK: - Linked Recordings

    func linkedRecordings(for story: Story) -> [Recording] {
        guard let context = modelContext else { return [] }

        let targetId = story.id
        var descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.predicate = #Predicate<Recording> { recording in
            recording.storyId == targetId
        }

        do {
            return try context.fetch(descriptor)
        } catch {
            return []
        }
    }

    // MARK: - Tag Extraction

    func autoExtractTags(from text: String, llmService: LLMService) async -> [StoryTag] {
        await taggingService.extractTags(from: text, using: llmService)
    }

    // MARK: - Word Bank

    func addWordsToVocab(words: [String], settings: UserSettings) {
        guard let context = modelContext else { return }

        for word in words {
            settings.addVocabWord(word)
        }

        do {
            try context.save()
        } catch {
            errorMessage = "Failed to save vocabulary words: \(error.localizedDescription)"
        }
    }

    func addWordsToDictation(words: [String], settings: UserSettings) {
        guard let context = modelContext else { return }

        for word in words {
            settings.addDictationBiasWord(word)
        }

        do {
            try context.save()
        } catch {
            errorMessage = "Failed to save dictation words: \(error.localizedDescription)"
        }
    }

}

// MARK: - Folder Selection

enum FolderSelection: Equatable, Hashable {
    case all
    case pinned
    case folder(UUID)
}

// MARK: - Sort Order

enum StorySortOrder: String, CaseIterable, Identifiable {
    case updatedAt = "Recent"
    case createdAt = "Created"
    case alphabetical = "A-Z"
    case mostPracticed = "Practiced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .updatedAt: return "clock"
        case .createdAt: return "calendar"
        case .alphabetical: return "textformat.abc"
        case .mostPracticed: return "mic"
        }
    }
}
