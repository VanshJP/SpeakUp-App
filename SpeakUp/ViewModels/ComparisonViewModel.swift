import Foundation
import SwiftUI
import SwiftData

/// Value projection of one recording for the comparison screen - decoded once
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
    /// Scored takes, newest first.
    var summaries: [ComparisonRecordingPoint] = []
    /// False until the first fetch lands, so the page shows a loader rather
    /// than flashing its not-enough-takes state on every open.
    private(set) var isLoaded = false
    var selectionA: UUID? {
        didSet { rebuildDerivedState() }
    }
    var selectionB: UUID? {
        didSet { rebuildDerivedState() }
    }

    /// Plain-value snapshots consumed directly in bodies - rebuilt only when a
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

        /// Amber for a drop, never red - the Progress pages' one colour for slipping.
        var arrowColor: Color {
            guard let improved else { return .secondary }
            return improved ? AppColors.success : AppColors.warning
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

                // Scored takes only. A processing or failed take as a default
                // side showed "Latest 0" and a phantom drop of the whole score,
                // and in the menus it read "0 pts".
                return recordings.compactMap { recording -> ComparisonRecordingPoint? in
                    guard let analysis = recording.analysis else { return nil }
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
            isLoaded = true

            // Auto-select the oldest and newest scored takes.
            if points.count >= 2 {
                selectionA = points.last?.id // oldest
                selectionB = points.first?.id // newest
            } else {
                selectionA = nil
                selectionB = nil
            }
        }
    }

    /// Rebuilds every body-facing value from cached points - pure arithmetic,
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
                  improved: Self.improvement(from: a.score ?? 0, to: b.score ?? 0)),
            Delta(label: "WPM", valueA: "\(Int(a.wpm))", valueB: "\(Int(b.wpm))",
                  improved: nil),
            Delta(label: "Fillers", valueA: "\(a.fillerCount)", valueB: "\(b.fillerCount)",
                  improved: Self.improvement(from: a.fillerCount, to: b.fillerCount, lowerIsBetter: true)),
            Delta(label: "Clarity", valueA: "\(a.clarity)", valueB: "\(b.clarity)",
                  improved: Self.improvement(from: a.clarity, to: b.clarity)),
            Delta(label: "Pace", valueA: "\(a.pace)", valueB: "\(b.pace)",
                  improved: Self.improvement(from: a.pace, to: b.pace)),
            Delta(label: "Pauses", valueA: "\(a.pauseQuality)", valueB: "\(b.pauseQuality)",
                  improved: Self.improvement(from: a.pauseQuality, to: b.pauseQuality)),
        ]
    }

    /// Nil when nothing moved. A tie used to count as "not improved", so an
    /// unchanged metric - Fillers 0 → 0 - wore a red down arrow.
    private static func improvement(from before: Int, to after: Int, lowerIsBetter: Bool = false) -> Bool? {
        guard before != after else { return nil }
        return lowerIsBetter ? after < before : after > before
    }
}
