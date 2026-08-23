import Foundation
import SwiftData

/// Value snapshot of one side of the comparison — decoded once at load so
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
        let descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        guard let recordings = try? context.fetch(descriptor) else { return }

        // Single decode pass: earliest/latest snapshots, improvement, and the
        // share card all come out of this loop.
        var earliest: (recording: Recording, analysis: SpeechAnalysis)?
        var latest: (recording: Recording, analysis: SpeechAnalysis)?
        var analyzedCount = 0

        for recording in recordings {
            guard let analysis = recording.analysis else { continue }
            analyzedCount += 1
            if earliest == nil { earliest = (recording, analysis) }
            latest = (recording, analysis)
        }

        guard analyzedCount >= 2, let first = earliest, let last = latest else { return }

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
