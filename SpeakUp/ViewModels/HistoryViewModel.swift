import Foundation
import SwiftUI
import SwiftData

/// Lightweight row-level projection of a Recording. Populated on a background
/// ModelContext so the History tab never fully hydrates transcripts/analyses.
nonisolated struct RecordingSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let actualDuration: TimeInterval
    let displayTitle: String
    let isFavorite: Bool
    let isProcessing: Bool
    let storyId: UUID?
    let promptCategory: String?
    let overallScore: Int?
    let wpm: Double?
    let fillerCount: Int?
    let searchableText: String

    var formattedDuration: String {
        let minutes = Int(actualDuration) / 60
        let seconds = Int(actualDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

nonisolated struct VocabCount: Hashable, Sendable {
    let word: String
    let count: Int
}

@MainActor @Observable
class HistoryViewModel {
    var summaries: [RecordingSummary] = []
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var isLoading = true

    // Derived stats precomputed once per load.
    var averageScore: Int?
    var totalPracticeTimeSeconds: TimeInterval = 0
    var aggregatedVocab: [VocabCount] = []
    var filterCounts: [HistoryFilter: Int] = [:]
    var recordingCountByDay: [Date: Int] = [:]
    var contributionIntensityByDay: [Date: Double] = [:]

    var analyzedCount: Int { summaries.reduce(0) { $0 + ($1.overallScore != nil ? 1 : 0) } }

    private var modelContext: ModelContext?
    private var container: ModelContainer?

    nonisolated init() {}

    func configure(with context: ModelContext) {
        self.modelContext = context
        self.container = context.container
        Task {
            await loadData()
        }
    }

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        guard let container else { return }

        let result = await Self.fetchSummaries(container: container)

        self.summaries = result.summaries
        self.averageScore = result.averageScore
        self.totalPracticeTimeSeconds = result.totalPracticeTimeSeconds
        self.aggregatedVocab = result.aggregatedVocab
        self.filterCounts = result.filterCounts
        self.recordingCountByDay = result.recordingCountByDay
        self.contributionIntensityByDay = result.contributionIntensityByDay
        self.currentStreak = result.currentStreak
        self.longestStreak = result.longestStreak
    }

    // MARK: - Background Load

    nonisolated private static func fetchSummaries(container: ModelContainer) async -> LoadResult {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )

            guard let recordings = try? context.fetch(descriptor) else {
                return LoadResult()
            }

            var summaries: [RecordingSummary] = []
            summaries.reserveCapacity(recordings.count)
            var scoreSum = 0
            var scoreCount = 0
            var totalDuration: TimeInterval = 0
            var vocabCounts: [String: Int] = [:]
            var filterCounts: [HistoryFilter: Int] = [:]
            var countByDay: [Date: Int] = [:]
            let calendar = Calendar.current
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)

            for r in recordings {
                if r.isDeleted { continue }

                let score = r.analysis?.speechScore.overall
                let wpm = r.analysis?.wordsPerMinute
                let fillerCount = r.analysis?.totalFillerCount

                let promptText = r.prompt?.text ?? ""
                let category = r.prompt?.category ?? ""
                let storyTitle = r.storyTitle ?? ""
                // Intentionally skip r.transcriptionText — decoding large transcript
                // blobs for every summary made History load O(total transcript size).
                let searchable = "\(promptText) \(category) \(storyTitle)"

                let displayTitle: String = {
                    if let ct = r.customTitle, !ct.isEmpty { return ct }
                    if !storyTitle.isEmpty { return storyTitle }
                    return promptText.isEmpty ? "Practice Session" : promptText
                }()

                summaries.append(
                    RecordingSummary(
                        id: r.id,
                        date: r.date,
                        actualDuration: r.actualDuration,
                        displayTitle: displayTitle,
                        isFavorite: r.isFavorite,
                        isProcessing: r.isProcessing,
                        storyId: r.storyId,
                        promptCategory: r.prompt?.category,
                        overallScore: score,
                        wpm: wpm,
                        fillerCount: fillerCount,
                        searchableText: searchable
                    )
                )

                totalDuration += r.actualDuration

                if let score {
                    scoreSum += score
                    scoreCount += 1
                    if score >= 80 {
                        filterCounts[.highScore, default: 0] += 1
                    }
                }
                if r.isFavorite { filterCounts[.favorites, default: 0] += 1 }
                if r.storyId != nil { filterCounts[.stories, default: 0] += 1 }
                if r.date >= weekAgo { filterCounts[.recent, default: 0] += 1 }

                let day = calendar.startOfDay(for: r.date)
                countByDay[day, default: 0] += 1

                if let usage = r.analysis?.vocabWordsUsed {
                    for item in usage {
                        vocabCounts[item.word, default: 0] += item.count
                    }
                }
            }

            let contributionIntensity = countByDay.mapValues(Self.intensityLevel(for:))
            let aggregatedVocab = vocabCounts
                .sorted { $0.value > $1.value }
                .map { VocabCount(word: $0.key, count: $0.value) }
            let averageScore = scoreCount > 0 ? scoreSum / scoreCount : nil

            let dates = summaries.map(\.date)
            let currentStreak = Date.calculateStreak(from: dates)
            let longestStreak = Self.calculateLongestStreak(from: dates)

            return LoadResult(
                summaries: summaries,
                currentStreak: currentStreak,
                longestStreak: longestStreak,
                averageScore: averageScore,
                totalPracticeTimeSeconds: totalDuration,
                aggregatedVocab: aggregatedVocab,
                filterCounts: filterCounts,
                recordingCountByDay: countByDay,
                contributionIntensityByDay: contributionIntensity
            )
        }.value
    }

    nonisolated private static func intensityLevel(for count: Int) -> Double {
        switch count {
        case 0: return 0
        case 1: return 0.25
        case 2: return 0.5
        case 3: return 0.75
        default: return 1.0
        }
    }

    nonisolated private static func calculateLongestStreak(from dates: [Date]) -> Int {
        guard !dates.isEmpty else { return 0 }

        let uniqueDays = Set(dates.map { Calendar.current.startOfDay(for: $0) })
        let sortedDays = uniqueDays.sorted()

        var maxStreak = 1
        var currentStreakCount = 1

        for i in 1..<sortedDays.count {
            let previousDay = sortedDays[i - 1]
            let currentDay = sortedDays[i]

            if Calendar.current.isDate(currentDay, inSameDayAs: previousDay.adding(days: 1)) {
                currentStreakCount += 1
                maxStreak = max(maxStreak, currentStreakCount)
            } else {
                currentStreakCount = 1
            }
        }

        return maxStreak
    }

    // MARK: - Mutations

    func deleteRecording(id: UUID) async {
        guard let context = modelContext else { return }

        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1

        guard let recording = (try? context.fetch(descriptor))?.first else { return }

        if let audioURL = recording.resolvedAudioURL {
            ICloudStorageService.shared.removeFile(at: audioURL)
        }
        if let videoURL = recording.resolvedVideoURL {
            ICloudStorageService.shared.removeFile(at: videoURL)
        }
        if let thumbnailURL = recording.resolvedThumbnailURL {
            ICloudStorageService.shared.removeFile(at: thumbnailURL)
        }

        let day = Calendar.current.startOfDay(for: recording.date)
        summaries.removeAll { $0.id == id }
        if let existing = recordingCountByDay[day] {
            let newCount = max(0, existing - 1)
            recordingCountByDay[day] = newCount
            contributionIntensityByDay[day] = Self.intensityLevel(for: newCount)
        }

        context.delete(recording)

        do {
            try context.save()
        } catch {
            print("Error deleting recording: \(error)")
        }
    }

    func toggleFavorite(id: UUID) async {
        guard let context = modelContext else { return }

        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1

        guard let recording = (try? context.fetch(descriptor))?.first else { return }

        recording.isFavorite.toggle()

        do {
            try context.save()
        } catch {
            print("Error toggling favorite: \(error)")
        }

        if let idx = summaries.firstIndex(where: { $0.id == id }) {
            let s = summaries[idx]
            summaries[idx] = RecordingSummary(
                id: s.id,
                date: s.date,
                actualDuration: s.actualDuration,
                displayTitle: s.displayTitle,
                isFavorite: !s.isFavorite,
                isProcessing: s.isProcessing,
                storyId: s.storyId,
                promptCategory: s.promptCategory,
                overallScore: s.overallScore,
                wpm: s.wpm,
                fillerCount: s.fillerCount,
                searchableText: s.searchableText
            )

            let wasAlreadyFavorite = s.isFavorite
            let delta = wasAlreadyFavorite ? -1 : 1
            filterCounts[.favorites, default: 0] = max(0, (filterCounts[.favorites] ?? 0) + delta)
        }
    }

    // MARK: - Contribution Graph Helpers

    func activityLevel(for date: Date) -> Double {
        let day = Calendar.current.startOfDay(for: date)
        return contributionIntensityByDay[day] ?? 0
    }

    func summariesForDate(_ date: Date) -> [RecordingSummary] {
        summaries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
}

nonisolated private struct LoadResult: Sendable {
    var summaries: [RecordingSummary] = []
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var averageScore: Int?
    var totalPracticeTimeSeconds: TimeInterval = 0
    var aggregatedVocab: [VocabCount] = []
    var filterCounts: [HistoryFilter: Int] = [:]
    var recordingCountByDay: [Date: Int] = [:]
    var contributionIntensityByDay: [Date: Double] = [:]
}
