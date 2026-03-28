import Foundation
import SwiftUI
import SwiftData

@MainActor @Observable
class StoriesViewModel {
    var stories: [Story] = []
    var filteredStories: [Story] = []
    var isLoading = false
    var errorMessage: String?

    var searchText = "" {
        didSet { debounceRecompute() }
    }
    var selectedTagFilter: StoryTagType? {
        didSet { recomputeFilteredStories() }
    }
    var selectedTagValue: String? {
        didSet { recomputeFilteredStories() }
    }
    var selectedStageFilter: StoryStage? {
        didSet { recomputeFilteredStories() }
    }
    var dateFilterStart: Date? {
        didSet { recomputeFilteredStories() }
    }
    var dateFilterEnd: Date? {
        didSet { recomputeFilteredStories() }
    }
    var favoritesOnly: Bool = false {
        didSet { recomputeFilteredStories() }
    }
    var sortOrder: StorySortOrder = .updatedAt {
        didSet { recomputeFilteredStories() }
    }

    var hasActiveFilters: Bool {
        selectedTagFilter != nil || selectedTagValue != nil ||
        selectedStageFilter != nil || dateFilterStart != nil ||
        favoritesOnly || sortOrder != .updatedAt
    }

    let taggingService = StoryTaggingService()

    private var modelContext: ModelContext?
    private var hasConfigured = false
    private var searchDebounceTask: Task<Void, Never>?

    func configure(with context: ModelContext) {
        guard !hasConfigured else { return }
        hasConfigured = true
        self.modelContext = context
        Task {
            await loadStories()
        }
    }

    // MARK: - Load

    func loadStories() async {
        guard let context = modelContext else { return }
        isLoading = true
        defer { isLoading = false }

        let descriptor = FetchDescriptor<Story>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        do {
            stories = try context.fetch(descriptor)
            recomputeFilteredStories()
        } catch {
            errorMessage = "Failed to load stories: \(error.localizedDescription)"
        }
    }

    // MARK: - Filtering & Sorting

    private func debounceRecompute() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            recomputeFilteredStories()
        }
    }

    func recomputeFilteredStories() {
        var result = stories

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { story in
                story.title.lowercased().contains(query) ||
                story.content.lowercased().contains(query) ||
                story.tags.contains { $0.value.lowercased().contains(query) }
            }
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
    }

    func applyTagFilter(_ tag: StoryTag) {
        selectedTagFilter = tag.type
        selectedTagValue = tag.value

        if tag.type == .date, let parsed = tag.parsedDate {
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .month, value: -1, to: parsed) ?? parsed
            let end = calendar.date(byAdding: .month, value: 1, to: parsed) ?? parsed
            dateFilterStart = start
            dateFilterEnd = end
        }
    }

    // MARK: - CRUD

    @discardableResult
    func createStory(
        title: String,
        content: String,
        tags: [StoryTag] = [],
        inputMethod: String = "typed",
        stage: StoryStage = .spark,
        occasion: StoryOccasion? = nil
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
            estimatedDurationSeconds: estimatedSeconds
        )
        context.insert(story)

        do {
            try context.save()
            stories.insert(story, at: 0)
            recomputeFilteredStories()

            WidgetDataProvider.updateLatestStory(
                title: title.isEmpty ? "Untitled Spark" : title,
                preview: story.contentPreview
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
        } catch {
            errorMessage = "Failed to update story: \(error.localizedDescription)"
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
        stories.removeAll { $0.id == story.id }
        recomputeFilteredStories()

        do {
            try context.save()
        } catch {
            errorMessage = "Failed to delete story: \(error.localizedDescription)"
        }
    }

    func toggleFavorite(_ story: Story) {
        guard let context = modelContext else { return }

        story.isFavorite.toggle()
        story.updatedAt = Date()

        do {
            try context.save()
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

    // MARK: - Text Formatting

    func formatDictatedText(_ text: String, llmService: LLMService) async -> String? {
        guard llmService.isAvailable, !text.isEmpty else { return nil }

        let truncated = String(text.prefix(3000))

        let systemPrompt = """
        You are a text formatter. Given raw dictated speech text, improve it by:
        1. Adding proper paragraph breaks where topics change
        2. Fixing capitalization for proper nouns and sentence starts
        3. Adding missing punctuation (periods, commas, question marks)
        4. Removing false starts and repeated words
        Do NOT change the meaning, add new content, or rewrite sentences.
        Return ONLY the formatted text with no explanations.
        """

        let userPrompt = "Format this dictated text:\n\n\(truncated)"
        return await llmService.generateText(prompt: userPrompt, systemPrompt: systemPrompt)
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

    // MARK: - Practice Count

    func incrementPracticeCount(for storyId: UUID) {
        guard let context = modelContext else { return }

        let targetId = storyId
        var descriptor = FetchDescriptor<Story>()
        descriptor.predicate = #Predicate<Story> { $0.id == targetId }

        do {
            if let story = try context.fetch(descriptor).first {
                story.practiceCount += 1
                story.lastPracticeDate = Date()
                story.updatedAt = Date()
                try context.save()
            }
        } catch {
            print("Failed to increment practice count: \(error)")
        }
    }

    func updateBestScore(for storyId: UUID, score: Int) {
        guard let context = modelContext else { return }

        let targetId = storyId
        var descriptor = FetchDescriptor<Story>()
        descriptor.predicate = #Predicate<Story> { $0.id == targetId }

        do {
            if let story = try context.fetch(descriptor).first, score > story.bestScore {
                story.bestScore = score
                try context.save()
            }
        } catch {
            print("Failed to update best score: \(error)")
        }
    }
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
