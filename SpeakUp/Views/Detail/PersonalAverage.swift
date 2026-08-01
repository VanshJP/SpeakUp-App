import Foundation
import SwiftData

/// The baseline a session score is read against.
///
/// A score with nothing to compare it against is trivia — 78 means nothing
/// until you know your average is 72. Both the reveal and the detail hero need
/// this number within a second of each other, so it lives in one place.
///
/// Bounded to a rolling window rather than all-time: decoding every `analysis`
/// blob would make the cost grow without limit, and a rolling baseline is the
/// more useful comparison anyway — "better than I've been lately" beats "better
/// than I was a year ago".
// Opt out of default MainActor isolation — baselines decode off-main in
// `Task.detached`, so window / Baselines must be callable from any isolation.
nonisolated enum PersonalAverage {

    static let window = 20

    /// Rolling means for everything the results screen compares against.
    /// Each field is nil when no prior session supplied that metric.
    struct Baselines: Sendable {
        var score: Int?
        var wordsPerMinute: Int?
        var fillerCount: Int?
        var pauseCount: Int?
        var totalWords: Int?
        /// Highest overall score among the prior sessions in the window.
        var best: Int?
        /// How many prior scored sessions the window actually found. Below
        /// `window` it means we've seen the user's whole history, so a new high
        /// can honestly be called all-time.
        var priorSessionCount: Int = 0

        // Phrasing lives here so every tile words the comparison identically.
        var paceLabel: String? { Self.format(wordsPerMinute) }
        var fillerLabel: String? { Self.format(fillerCount) }
        var pauseLabel: String? { Self.format(pauseCount) }
        var wordsLabel: String? { Self.format(totalWords) }

        /// Names a new high, scoped to what was actually measured. Claiming an
        /// all-time best off a 20-session window would be a lie for anyone with
        /// a longer history, so the copy narrows once the window is full.
        func personalBestLabel(for score: Int) -> String? {
            guard let best, score > best else { return nil }
            return priorSessionCount < window ? "Your best yet" : "Best in \(window) sessions"
        }

        /// "vs 132 avg", or nil when there is no baseline to show.
        private static func format(_ value: Int?) -> String? {
            value.map { "vs \($0) avg" }
        }
    }

    /// One fetch, one decode pass, every baseline the screen needs.
    ///
    /// Runs off the main actor: `Recording.analysis` is a Codable blob and
    /// decoding a window of them in a view body would stutter.
    static func all(excluding currentID: UUID, container: ModelContainer) async -> Baselines {
        await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            // One extra row so excluding the current session still leaves a
            // full window.
            descriptor.fetchLimit = window + 1

            guard let recent = try? context.fetch(descriptor) else { return Baselines() }

            let analyses = recent
                .filter { $0.id != currentID && !$0.isDeleted }
                .prefix(window)
                .compactMap(\.analysis)
                // A session that scored 0 hit the zero-word gate — a silent or
                // failed capture, not a measurement of how the user speaks.
                // Averaging those in produced baselines like "vs 5 avg" for
                // pace and deltas like "62 above your average", which read as
                // broken rather than encouraging.
                .filter { $0.speechScore.overall > 0 }

            guard !analyses.isEmpty else { return Baselines() }

            func mean(_ values: [Double]) -> Int? {
                guard !values.isEmpty else { return nil }
                return Int((values.reduce(0, +) / Double(values.count)).rounded())
            }

            let scores = analyses.map(\.speechScore.overall)

            return Baselines(
                score: mean(scores.map(Double.init)),
                wordsPerMinute: mean(analyses.map(\.wordsPerMinute)),
                fillerCount: mean(analyses.map { Double($0.totalFillerCount) }),
                pauseCount: mean(analyses.map { Double($0.pauseCount) }),
                totalWords: mean(analyses.map { Double($0.totalWords) }),
                best: scores.max(),
                priorSessionCount: analyses.count
            )
        }.value
    }
}
