import Foundation
import SwiftData

@Observable
class ProgressReplayViewModel {
    var earliestRecording: Recording?
    var latestRecording: Recording?
    var scoreImprovement: Int = 0
    var isLoaded = false

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

        let earlyScore = earliestRecording?.analysis?.speechScore.overall ?? 0
        let lateScore = latestRecording?.analysis?.speechScore.overall ?? 0
        scoreImprovement = lateScore - earlyScore
        isLoaded = true
    }
}
