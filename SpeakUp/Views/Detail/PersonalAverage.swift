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

    /// How far back the same-subject scan looks. Deliberately short: this
    /// exists for "I just did that again", not for archaeology, and every extra
    /// row is a materialized blob column.
    static let repeatScanLimit = 40

    /// The last time the user answered this same prompt or story.
    ///
    /// A different prompt every session is variety, not practice. The rep that
    /// moves anything is the same sixty seconds, twice, with the feedback in
    /// between — and that is only legible if the second take is shown against
    /// the first.
    struct PreviousTake: Sendable {
        let date: Date
        let overall: Int
        let subscores: SpeechSubscores
        /// Which attempt the session being viewed is. 2 on the first repeat.
        let takeNumber: Int
    }

    /// Everything the results screen reads from history in one pass.
    struct Snapshot: Sendable {
        var baselines = Baselines()
        /// What the speaker is working on. Built from the same decode pass —
        /// a second fetch just to rank subscores would double the cost of the
        /// most expensive thing this screen does.
        var plan: CoachPlan?
        var previousTake: PreviousTake?
        /// Whether the session being viewed is inside the plan's window.
        ///
        /// The plan is always built from the newest sessions, so opening a
        /// three-month-old recording would otherwise bolt today's focus onto it
        /// and imply it was what that session was about.
        var currentIsInPlanWindow = false
    }

    /// What a session was practising, as one comparable key.
    ///
    /// Story wins over prompt, matching how `PromptRelevanceService` picks its
    /// source text. The two ids are different types — `Story` is keyed by UUID,
    /// `Prompt` by String — so they are normalised here rather than at the two
    /// call sites that would otherwise each have to get it right.
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
        // `Prompt.id` is a String and defaults to empty, so an empty subject is
        // not an identity — matching on it would pair up unrelated sessions.
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
            // Everything before this one, plus this one.
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
    ///
    /// The plan window deliberately does *not* exclude `currentID`: baselines
    /// answer "how does this session compare to my others", so the session
    /// itself must be left out, while the plan answers "what am I working on
    /// now", which the latest session is part of.
    /// - Parameter repeatSubject: the prompt or story the session being viewed
    ///   answered, from `repeatSubject(of:)`, used to find the user's previous
    ///   attempt at the same thing.
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
            // One extra row so excluding the current session still leaves a
            // full window; the repeat scan wants a longer tail than that.
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
                // A session that scored 0 hit the zero-word gate — a silent or
                // failed capture, not a measurement of how the user speaks.
                // Averaging those in produced baselines like "vs 5 avg" for
                // pace and deltas like "62 above your average", which read as
                // broken rather than encouraging.
                .filter { $0.speechScore.overall > 0 }

            // No prior session to compare against still leaves a plan — the
            // focus is worth showing from the very first recording.
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
