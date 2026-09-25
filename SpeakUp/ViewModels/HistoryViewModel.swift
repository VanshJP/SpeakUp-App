import Foundation
import os
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
    private let logger = Logger.app("History")
    var summaries: [RecordingSummary] = []
    var isLoading = true

    /// Vocab-word usage totals, the one derived stat the History screen still
    /// renders. Streak / average / per-day counts moved out with the stats
    /// strip and contribution graph - no view read them any more.
    var aggregatedVocab: [VocabCount] = []

    /// Takes that carry a score. Compare and Listen back need two: counting
    /// every summary let a processing or failed take open them onto a zero
    /// score or an empty sheet.
    var scoredTakeCount: Int {
        summaries.reduce(0) { $0 + ($1.overallScore == nil ? 0 : 1) }
    }

    /// Changes when a take is added, removed, or finishes scoring. The
    /// Progress charts reload on a change instead of on every appearance.
    var progressFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(summaries.count)
        hasher.combine(scoredTakeCount)
        hasher.combine(summaries.first?.id)
        hasher.combine(summaries.first?.overallScore)
        return hasher.finalize()
    }

    private var modelContext: ModelContext?
    private var container: ModelContainer?
    /// The reload in flight, if any. History appears after every take and on
    /// every tab switch, and each appearance used to start another full scan
    /// (one analysis decode per take) beside the one already running.
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// An appearance landed mid-reload, so run once more when it finishes.
    @ObservationIgnored private var reloadRequested = false

    nonisolated init() {}

    func configure(with context: ModelContext) {
        self.modelContext = context
        self.container = context.container
        guard loadTask == nil else {
            reloadRequested = true
            return
        }
        loadTask = Task {
            repeat {
                reloadRequested = false
                await loadData()
            } while reloadRequested
            loadTask = nil
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

                // Bind once: each `r.analysis` access re-decodes the Codable blob.
                // Prefer the denormalized `overallScore` projection when present
                // (legacy rows stay nil - fall back to the blob; see gotchas §18).
                let analysis = r.analysis
                let score = r.overallScore ?? analysis?.speechScore.overall
                let wpm = analysis?.wordsPerMinute
                let fillerCount = analysis?.totalFillerCount

                let promptText = r.prompt?.text ?? ""
                let category = r.prompt?.category ?? ""
                let storyTitle = r.storyTitle ?? ""
                // Intentionally skip r.transcriptionText - decoding large transcript
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

                if let usage = analysis?.vocabWordsUsed {
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

    private static let logger = Logger.app("History")

    func deleteRecording(id: UUID) async {
        guard let context = modelContext else { return }

        // Stop any in-flight analysis before the row disappears.
        RecordingProcessingCoordinator.shared.cancelProcessing(recordingID: id)

        var descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1

        guard let recording = (try? context.fetch(descriptor))?.first else { return }

        // Capture media locations before deleting - the row is invalid after save.
        let audioURL = recording.resolvedAudioURL
        let videoURL = recording.resolvedVideoURL
        let thumbnailURL = recording.resolvedThumbnailURL

        // Delete the row first, files second: a crash in between strands an
        // orphan file (sweepable) rather than a dangling row pointing at
        // deleted media (fatal).
        context.delete(recording)

        do {
            try context.save()
        } catch {
            logger.error("Failed to delete recording row: \(error.localizedDescription, privacy: .private(mask: .hash))")
            return
        }

        summaries.removeAll { $0.id == id }

        if let audioURL {
            ICloudStorageService.shared.removeFile(at: audioURL)
        }
        if let videoURL {
            ICloudStorageService.shared.removeFile(at: videoURL)
        }
        if let thumbnailURL {
            ICloudStorageService.shared.removeFile(at: thumbnailURL)
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
            logger.error("Error toggling favorite: \(error.localizedDescription, privacy: .private(mask: .hash))")
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
