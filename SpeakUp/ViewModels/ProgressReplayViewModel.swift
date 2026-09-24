import Foundation
import SwiftData

/// Value snapshot of one side of the comparison - decoded once at load so
/// card bodies never read a `Recording.analysis` blob.
nonisolated struct ReplaySessionSnapshot {
    let date: Date
    let score: Int?
    let wpm: Double
    let fillerCount: Int
    let wordCount: Int
}

@Observable
class ProgressReplayViewModel {
    var earliestRecording: Recording?
    var latestRecording: Recording?
    private(set) var earliestSnapshot: ReplaySessionSnapshot?
    private(set) var latestSnapshot: ReplaySessionSnapshot?
    /// Plain-value share card, built once at load instead of per redraw.
    private(set) var progressCard: ProgressCardData?
    var scoreImprovement: Int = 0
    var isLoaded = false
    /// Scored sessions behind the comparison. Shown on the share card so a
    /// jump in score reads as practice rather than luck.
    var analyzedSessionCount = 0

    @MainActor
    func loadRecordings(context: ModelContext) {
        // A count and two small fetches on the transcript proxy (gotcha §2).
        // This used to decode the analysis of every take ever recorded, on the
        // main thread, as the sheet opened - to use the first and the last.
        let analyzed = #Predicate<Recording> { $0.transcriptionText != nil }
        let analyzedCount = (try? context.fetchCount(FetchDescriptor<Recording>(predicate: analyzed))) ?? 0

        guard analyzedCount >= 2,
              let first = Self.edgeAnalyzed(in: context, matching: analyzed, order: .forward),
              let last = Self.edgeAnalyzed(in: context, matching: analyzed, order: .reverse),
              first.recording.id != last.recording.id else { return }

        earliestRecording = first.recording
        latestRecording = last.recording
        analyzedSessionCount = analyzedCount
        earliestSnapshot = Self.snapshot(first.analysis, date: first.recording.date)
        latestSnapshot = Self.snapshot(last.analysis, date: last.recording.date)
        scoreImprovement = (latestSnapshot?.score ?? 0) - (earliestSnapshot?.score ?? 0)

        progressCard = ProgressCardData.make(
            first: first.analysis,
            firstDate: first.recording.date,
            latest: last.analysis,
            latestDate: last.recording.date,
            sessionCount: analyzedSessionCount
        )
        isLoaded = true
    }

    /// The earliest (`.forward`) or latest (`.reverse`) take with an analysis.
    /// Looks a few rows in, in case a transcript ever landed without one.
    private static func edgeAnalyzed(
        in context: ModelContext,
        matching predicate: Predicate<Recording>,
        order: SortOrder
    ) -> (recording: Recording, analysis: SpeechAnalysis)? {
        var descriptor = FetchDescriptor<Recording>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: order)]
        )
        descriptor.fetchLimit = 5
        for recording in (try? context.fetch(descriptor)) ?? [] {
            if let analysis = recording.analysis { return (recording, analysis) }
        }
        return nil
    }

    private static func snapshot(_ analysis: SpeechAnalysis, date: Date) -> ReplaySessionSnapshot {
        ReplaySessionSnapshot(
            date: date,
            score: analysis.speechScore.overall,
            wpm: analysis.wordsPerMinute,
            fillerCount: analysis.totalFillerCount,
            wordCount: analysis.totalWords
        )
    }
}
