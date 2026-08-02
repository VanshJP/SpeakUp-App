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
    var hasError: Bool = false
    let storyId: UUID?
    let promptCategory: String?
    let overallScore: Int?
    let wpm: Double?
    let fillerCount: Int?
    let searchableText: String

    var formattedDuration: String {
        actualDuration.minutesSeconds
    }
}

nonisolated struct VocabCount: Hashable, Sendable {
    let word: String
    let count: Int
}

@MainActor @Observable
class HistoryViewModel {
    var summaries: [RecordingSummary] = []
    var isLoading = true

    /// Vocab-word usage totals, the one derived stat the History screen still
    /// renders. Streak / average / per-day counts moved out with the stats
    /// strip and contribution graph — no view read them any more.
    var aggregatedVocab: [VocabCount] = []

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
        self.aggregatedVocab = result.aggregatedVocab
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
            var vocabCounts: [String: Int] = [:]

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
                        hasError: r.lastProcessingError != nil,
                        storyId: r.storyId,
                        promptCategory: r.prompt?.category,
                        overallScore: score,
                        wpm: wpm,
                        fillerCount: fillerCount,
                        searchableText: searchable
                    )
                )

                if let usage = r.analysis?.vocabWordsUsed {
                    for item in usage {
                        vocabCounts[item.word, default: 0] += item.count
                    }
                }
            }

            let aggregatedVocab = vocabCounts
                .sorted { $0.value > $1.value }
                .map { VocabCount(word: $0.key, count: $0.value) }

            return LoadResult(summaries: summaries, aggregatedVocab: aggregatedVocab)
        }.value
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

        summaries.removeAll { $0.id == id }

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
                hasError: s.hasError,
                storyId: s.storyId,
                promptCategory: s.promptCategory,
                overallScore: s.overallScore,
                wpm: s.wpm,
                fillerCount: s.fillerCount,
                searchableText: s.searchableText
            )
        }
    }
}

nonisolated private struct LoadResult: Sendable {
    var summaries: [RecordingSummary] = []
    var aggregatedVocab: [VocabCount] = []
}
