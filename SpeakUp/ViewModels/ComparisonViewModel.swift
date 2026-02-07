import Foundation
import SwiftUI
import SwiftData

@Observable
class ComparisonViewModel {
    var recordingA: Recording?
    var recordingB: Recording?
    var allRecordings: [Recording] = []

    private var modelContext: ModelContext?

    func configure(with context: ModelContext) {
        self.modelContext = context
        loadRecordings()
    }

    private func loadRecordings() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        allRecordings = (try? context.fetch(descriptor)) ?? []

        // Auto-select first vs latest
        if allRecordings.count >= 2 {
            recordingA = allRecordings.last  // oldest
            recordingB = allRecordings.first // newest
        }
    }

    struct Delta {
        let label: String
        let valueA: String
        let valueB: String
        let improved: Bool?

        var arrowIcon: String {
            guard let improved else { return "arrow.right" }
            return improved ? "arrow.up.right" : "arrow.down.right"
        }

        var arrowColor: Color {
            guard let improved else { return .secondary }
            return improved ? .green : .red
        }
    }

    var deltas: [Delta] {
        guard let a = recordingA?.analysis, let b = recordingB?.analysis else { return [] }
        return [
            Delta(label: "Score", valueA: "\(a.speechScore.overall)", valueB: "\(b.speechScore.overall)",
                  improved: b.speechScore.overall > a.speechScore.overall),
            Delta(label: "WPM", valueA: "\(Int(a.wordsPerMinute))", valueB: "\(Int(b.wordsPerMinute))",
                  improved: nil),
            Delta(label: "Fillers", valueA: "\(a.totalFillerCount)", valueB: "\(b.totalFillerCount)",
                  improved: b.totalFillerCount < a.totalFillerCount),
            Delta(label: "Clarity", valueA: "\(a.speechScore.subscores.clarity)", valueB: "\(b.speechScore.subscores.clarity)",
                  improved: b.speechScore.subscores.clarity > a.speechScore.subscores.clarity),
            Delta(label: "Pace", valueA: "\(a.speechScore.subscores.pace)", valueB: "\(b.speechScore.subscores.pace)",
                  improved: b.speechScore.subscores.pace > a.speechScore.subscores.pace),
            Delta(label: "Pauses", valueA: "\(a.speechScore.subscores.pauseQuality)", valueB: "\(b.speechScore.subscores.pauseQuality)",
                  improved: b.speechScore.subscores.pauseQuality > a.speechScore.subscores.pauseQuality),
        ]
    }
}
