import Foundation
import SwiftUI
import SwiftData

/// Value projection of one recording for the comparison screen — decoded once
/// on a background context so picker redraws never touch an analysis blob.
nonisolated struct ComparisonRecordingPoint: Identifiable {
    let id: UUID
    let date: Date
    /// Overall score; nil when the take was never analyzed.
    let score: Int?
    let wpm: Double
    let fillerCount: Int
    let clarity: Int
    let pace: Int
    let pauseQuality: Int

    var hasAnalysis: Bool { score != nil }
}

@Observable
class ComparisonViewModel {
    var summaries: [ComparisonRecordingPoint] = []
    var selectionA: UUID? {
        didSet { rebuildDerivedState() }
    }
    var selectionB: UUID? {
        didSet { rebuildDerivedState() }
    }

    /// Plain-value snapshots consumed directly in bodies — rebuilt only when a
    /// picker selection changes, never per redraw.
    private(set) var progressCard: ProgressCardData?
    private(set) var deltas: [Delta] = []

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

    var scoreA: Int { point(for: selectionA)?.score ?? 0 }
    var scoreB: Int { point(for: selectionB)?.score ?? 0 }

    private func point(for id: UUID?) -> ComparisonRecordingPoint? {
        guard let id else { return nil }
        return summaries.first { $0.id == id }
    }

    func configure(with context: ModelContext) {
        // Once-configured: refetching on every onAppear would reset the
        // user's A/B picks and flash zeros mid-interaction.
        guard summaries.isEmpty else { return }

        let container = context.container
        Task { [weak self] in
            let points = await Task.detached(priority: .userInitiated) { () -> [ComparisonRecordingPoint] in
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<Recording>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
                let recordings = (try? context.fetch(descriptor)) ?? []

                return recordings.map { recording -> ComparisonRecordingPoint in
                    guard let analysis = recording.analysis else {
                        return ComparisonRecordingPoint(
                            id: recording.id,
                            date: recording.date,
                            score: nil,
                            wpm: 0,
                            fillerCount: 0,
                            clarity: 0,
                            pace: 0,
                            pauseQuality: 0
                        )
                    }
                    return ComparisonRecordingPoint(
                        id: recording.id,
                        date: recording.date,
                        score: analysis.speechScore.overall,
                        wpm: analysis.wordsPerMinute,
                        fillerCount: analysis.totalFillerCount,
                        clarity: analysis.speechScore.subscores.clarity,
                        pace: analysis.speechScore.subscores.pace,
                        pauseQuality: analysis.speechScore.subscores.pauseQuality
                    )
                }
            }.value

            guard let self else { return }
            summaries = points

            // Auto-select oldest vs latest, matching the previous behavior.
            if points.count >= 2 {
                selectionA = points.last?.id // oldest
                selectionB = points.first?.id // newest
            } else {
                selectionA = nil
                selectionB = nil
            }
        }
    }

    /// Rebuilds every body-facing value from cached points — pure arithmetic,
    /// no SwiftData, no blob decoding.
    private func rebuildDerivedState() {
        guard let a = point(for: selectionA), let b = point(for: selectionB),
              a.hasAnalysis, b.hasAnalysis else {
            progressCard = nil
            deltas = []
            return
        }

        progressCard = ProgressCardData(
            firstDate: a.date,
            latestDate: b.date,
            firstScore: a.score ?? 0,
            latestScore: b.score ?? 0,
            sessionCount: summaries.filter(\.hasAnalysis).count,
            rows: [
                .init(label: "Clarity", before: a.clarity, after: b.clarity, lowerIsBetter: false),
                .init(label: "Pace", before: a.pace, after: b.pace, lowerIsBetter: false),
                .init(label: "Pauses", before: a.pauseQuality, after: b.pauseQuality, lowerIsBetter: false),
                .init(label: "Fillers", before: a.fillerCount, after: b.fillerCount, lowerIsBetter: true)
            ]
        )

        deltas = [
            Delta(label: "Score", valueA: "\(a.score ?? 0)", valueB: "\(b.score ?? 0)",
                  improved: (b.score ?? 0) > (a.score ?? 0)),
            Delta(label: "WPM", valueA: "\(Int(a.wpm))", valueB: "\(Int(b.wpm))",
                  improved: nil),
            Delta(label: "Fillers", valueA: "\(a.fillerCount)", valueB: "\(b.fillerCount)",
                  improved: b.fillerCount < a.fillerCount),
            Delta(label: "Clarity", valueA: "\(a.clarity)", valueB: "\(b.clarity)",
                  improved: b.clarity > a.clarity),
            Delta(label: "Pace", valueA: "\(a.pace)", valueB: "\(b.pace)",
                  improved: b.pace > a.pace),
            Delta(label: "Pauses", valueA: "\(a.pauseQuality)", valueB: "\(b.pauseQuality)",
                  improved: b.pauseQuality > a.pauseQuality),
        ]
    }
}
