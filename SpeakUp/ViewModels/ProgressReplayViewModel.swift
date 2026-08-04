import Foundation
import SwiftData

@Observable
class ProgressReplayViewModel {
    var earliestRecording: Recording?
    var latestRecording: Recording?
    var scoreImprovement: Int = 0
    var isLoaded = false
    /// Scored sessions behind the comparison. Shown on the share card so a
    /// jump in score reads as practice rather than luck.
    var analyzedSessionCount = 0

    /// The share card for this comparison. Nil until both sides are scored.
    var progressCard: ProgressCardData? {
        guard let earliestRecording, let latestRecording else { return nil }
        return ProgressCardData.make(
            first: earliestRecording.analysis,
            firstDate: earliestRecording.date,
            latest: latestRecording.analysis,
            latestDate: latestRecording.date,
            sessionCount: analyzedSessionCount
        )
    }

    @MainActor
    func loadRecordings(context: ModelContext) {
        let descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        guard let recordings = try? context.fetch(descriptor) else { return }

        let analyzed = recordings.filter { $0.analysis != nil }
        guard analyzed.count >= 2 else { return }

        earliestRecording = analyzed.first
        latestRecording = analyzed.last
        analyzedSessionCount = analyzed.count

        let earlyScore = earliestRecording?.analysis?.speechScore.overall ?? 0
        let lateScore = latestRecording?.analysis?.speechScore.overall ?? 0
        scoreImprovement = lateScore - earlyScore
        isLoaded = true
    }
}
