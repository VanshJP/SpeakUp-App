import Foundation
import SwiftData

/// The baseline a session score is read against.
/// Bounded to a rolling window rather than all-time: decoding every `analysis`
/// blob would make the cost grow without limit, and a rolling baseline is the
// Opt out of default MainActor isolation — baselines decode off-main in
// `Task.detached`, so window / Baselines must be callable from any isolation.
nonisolated enum PersonalAverage {

    static let window = 20

    struct Baselines: Sendable {
        var score: Int?
        var wordsPerMinute: Int?
        var fillerCount: Int?
        var pauseCount: Int?
        var totalWords: Int?
        var best: Int?
        var priorSessionCount: Int = 0

        // Phrasing lives here so every tile words the comparison identically.
        var paceLabel: String? { Self.format(wordsPerMinute) }
        var fillerLabel: String? { Self.format(fillerCount) }
        var pauseLabel: String? { Self.format(pauseCount) }
        var wordsLabel: String? { Self.format(totalWords) }

        func personalBestLabel(for score: Int) -> String? {
            guard let best, score > best else { return nil }
            return priorSessionCount < window ? "Your best yet" : "Best in \(window) sessions"
        }

        private static func format(_ value: Int?) -> String? {
            value.map { "vs \($0) avg" }
        }
    }

    /// How far back the same-subject scan looks. Deliberately short: this
    /// exists for "I just did that again", not for archaeology, and every extra
    /// row is a materialized blob column.
    static let repeatScanLimit = 40

    struct PreviousTake: Sendable {
        let date: Date
        let overall: Int
        let subscores: SpeechSubscores
        let takeNumber: Int
    }

    struct Snapshot: Sendable {
        var baselines = Baselines()
        var plan: CoachPlan?
        var previousTake: PreviousTake?
        var currentIsInPlanWindow = false
    }

    /// What a session was practising, as one comparable key.
    /// `Prompt` by String — so they are normalised here rather than at the two
    static func repeatSubject(of recording: Recording) -> String? {
        if let storyId = recording.storyId { return storyId.uuidString }
        guard let promptId = recording.prompt?.id, !promptId.isEmpty else { return nil }
        return promptId
    }

    /// The most recent earlier attempt at the same prompt or story.
    ///
    /// Matches on the relationship without decoding anything: `analysis` is
    /// only unwrapped for the single row that matches, so scanning the tail
    /// costs a fault per row rather than a blob decode per row.
    private static func previousTake(
        subject: String?,
        before currentDate: Date,
        excluding currentID: UUID,
        in recordings: [Recording]
    ) -> PreviousTake? {
        guard let subject, !subject.isEmpty else { return nil }

        let sameSubject = recordings.filter {
            $0.id != currentID
                && $0.date < currentDate
                && (Self.repeatSubject(of: $0) == subject)
        }
        guard let latest = sameSubject.first,
              let analysis = latest.analysis,
              analysis.speechScore.overall > 0 else { return nil }

        return PreviousTake(
            date: latest.date,
            overall: analysis.speechScore.overall,
            subscores: analysis.speechScore.subscores,
            takeNumber: sameSubject.count + 1
        )
    }

    /// One fetch, one decode pass, every baseline the screen needs.
    ///
    /// Runs off the main actor: `Recording.analysis` is a Codable blob and
    /// decoding a window of them in a view body would stutter.
    static func all(excluding currentID: UUID, container: ModelContainer) async -> Baselines {
        await snapshot(excluding: currentID, container: container).baselines
    }

    /// Baselines plus the coaching plan, from a single fetch and decode.
    /// itself must be left out, while the plan answers "what am I working on
    static func snapshot(
        excluding currentID: UUID,
        container: ModelContainer,
        weights: ScoreWeights = .defaults,
        repeatSubject: String? = nil,
        currentDate: Date = .distantFuture
    ) async -> Snapshot {
        await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = max(window + 1, repeatSubject == nil ? window + 1 : repeatScanLimit)

            guard let recent = try? context.fetch(descriptor) else { return Snapshot() }

            let live = recent.filter { !$0.isDeleted }
            let planWindow = live.prefix(window)
            let currentIsInPlanWindow = planWindow.contains { $0.id == currentID }
            let previousTake = previousTake(
                subject: repeatSubject,
                before: currentDate,
                excluding: currentID,
                in: live
            )
            // `analysis`, not `fullAnalysis`: the plan only reads subscores,
            // which survive SwiftData's decoder intact. Taking the full mirror
            // here would decode twenty JSON blobs to reach nine integers each.
            let plan = CoachPlanService.plan(
                window: planWindow.compactMap(\.analysis),
                weights: weights
            )

            let analyses = live
                .filter { $0.id != currentID }
                .prefix(window)
                .compactMap(\.analysis)
                .filter { $0.speechScore.overall > 0 }

            guard !analyses.isEmpty else {
                return Snapshot(
                    plan: plan,
                    previousTake: previousTake,
                    currentIsInPlanWindow: currentIsInPlanWindow
                )
            }

            func mean(_ values: [Double]) -> Int? {
                guard !values.isEmpty else { return nil }
                return Int((values.reduce(0, +) / Double(values.count)).rounded())
            }

            let scores = analyses.map(\.speechScore.overall)

            return Snapshot(
                baselines: Baselines(
                    score: mean(scores.map(Double.init)),
                    wordsPerMinute: mean(analyses.map(\.wordsPerMinute)),
                    fillerCount: mean(analyses.map { Double($0.totalFillerCount) }),
                    pauseCount: mean(analyses.map { Double($0.pauseCount) }),
                    totalWords: mean(analyses.map { Double($0.totalWords) }),
                    best: scores.max(),
                    priorSessionCount: analyses.count
                ),
                plan: plan,
                previousTake: previousTake,
                currentIsInPlanWindow: currentIsInPlanWindow
            )
        }.value
    }
}
