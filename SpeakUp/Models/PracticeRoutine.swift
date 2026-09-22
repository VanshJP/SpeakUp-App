import Foundation

/// One link in a practice routine.
///
/// A routine is the answer to "what now?". Every tool in the app is a door, and
/// a home screen full of doors makes the user re-decide the whole session every
/// time they finish something. An ordered chain means finishing one thing names
/// the next thing, and the only decision left is whether to take it.
nonisolated enum RoutineStep: String, CaseIterable, Identifiable, Sendable, Codable {
    case calm
    case warmUp
    case drill
    case readAloud
    case session
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: return "Settle nerves"
        case .warmUp: return "Warm up"
        case .drill: return "Run a drill"
        case .readAloud: return "Read aloud"
        case .session: return "Today's take"
        case .review: return "Read the score"
        }
    }

    /// Why the link is in the chain. One line, coach voice.
    var detail: String {
        switch self {
        case .calm: return "A minute of calm before you speak"
        case .warmUp: return "Open the voice so the first sentence is not the warm-up"
        case .drill: return "One weakness, under a minute"
        case .readAloud: return "Reps on clarity with the words already written"
        case .session: return "The scored take this is all for"
        case .review: return "See what changed and what to fix next"
        }
    }

    /// Verb-first label for the control that starts this step.
    var actionTitle: String {
        switch self {
        case .calm: return "Open Calm"
        case .warmUp: return "Start warm-up"
        case .drill: return "Pick a drill"
        case .readAloud: return "Open Read Aloud"
        case .session: return "Start speaking"
        case .review: return "Open History"
        }
    }

    /// Icon only - identity colour comes from `PracticeToolKind` at the view
    /// layer (`RoutineStep.tool` / `.tint` in `RoutineCard.swift`). The catalog
    /// is MainActor-isolated and this type has to stay pure. See gotchas §7.
    var icon: String {
        switch self {
        case .calm: return "heart.fill"
        case .warmUp: return "wind"
        case .drill: return "bolt.fill"
        case .readAloud: return "text.book.closed"
        case .session: return "mic.fill"
        case .review: return "chart.line.uptrend.xyaxis"
        }
    }

    /// Rough minutes the step costs, for the card's time line. The take is the
    /// user's own chosen length plus ~40s of countdown, scoring and reveal;
    /// the rest are what the tools typically run (warm-ups 50-115s, drills
    /// under a minute). Rounded up so the promise is kept rather than beaten.
    func estimatedMinutes(takeSeconds: Int) -> Int {
        switch self {
        case .calm, .warmUp, .readAloud: return 2
        case .drill, .review: return 1
        case .session: return (takeSeconds + 40 + 59) / 60
        }
    }

    /// The scored take cannot be dropped. A routine without it is preparation
    /// for nothing, and the app already has a Library full of tools for anyone
    /// who wants to practise without being measured.
    var isPinned: Bool { self == .session }

    /// Factory chain: open the voice, take the scored rep, look at what it said.
    /// Short on purpose - a routine that takes twenty minutes is one people skip
    /// on the days they most need it.
    static let defaultSteps: [RoutineStep] = [.warmUp, .session, .review]
}

// MARK: - Order

/// Resolves and reorders the persisted routine. Deliberately the same shape as
/// `TodayHomeLayout`, because it is the same problem: an ordered, user-editable
/// list with one member that may not be removed.
nonisolated enum PracticeRoutine {
    /// Empty storage means "never customized" and returns the factory chain,
    /// not an empty routine.
    static func resolve(_ raw: [String]) -> [RoutineStep] {
        guard !raw.isEmpty else { return RoutineStep.defaultSteps }

        var seen = Set<RoutineStep>()
        var ordered: [RoutineStep] = []
        for value in raw {
            guard let step = RoutineStep(rawValue: value), !seen.contains(step) else { continue }
            seen.insert(step)
            ordered.append(step)
        }

        // The take is required. A stale or hand-edited payload that dropped it
        // gets it back in canonical position - before the review, not after it,
        // which is the one place a repaired chain could still read as nonsense.
        return adding(.session, to: ordered)
    }

    static func encode(_ steps: [RoutineStep]) -> [String] {
        steps.map(\.rawValue)
    }

    /// Insert `step` in canonical order - the order of `RoutineStep.allCases`,
    /// which runs prep → take → review. Someone adding Read Aloud to a chain
    /// wants it before the take, not after the review.
    static func adding(_ step: RoutineStep, to steps: [RoutineStep]) -> [RoutineStep] {
        guard !steps.contains(step) else { return steps }
        var result = steps
        let insertion = result.firstIndex { existing in
            canonicalIndex(existing) > canonicalIndex(step)
        } ?? result.count
        result.insert(step, at: insertion)
        return result
    }

    static func removing(_ step: RoutineStep, from steps: [RoutineStep]) -> [RoutineStep] {
        guard !step.isPinned else { return steps }
        return steps.filter { $0 != step }
    }

    /// Move `step` one slot toward the front or back. A routine is short enough
    /// that two arrows beat a drag, and arrows are reachable by assistive tech
    /// without an accessibility action of their own.
    static func moving(_ step: RoutineStep, by offset: Int, in steps: [RoutineStep]) -> [RoutineStep] {
        guard let index = steps.firstIndex(of: step) else { return steps }
        let target = index + offset
        guard steps.indices.contains(target) else { return steps }
        var result = steps
        result.swapAt(index, target)
        return result
    }

    private static func canonicalIndex(_ step: RoutineStep) -> Int {
        RoutineStep.allCases.firstIndex(of: step) ?? 0
    }
}

// MARK: - Progress

/// Which links are done today.
///
/// Day-stamped rather than cleared by a timer: the app is not running at
/// midnight, so "yesterday's ticks are gone" has to be a fact that is derived on
/// read, not an event somebody has to fire.
nonisolated struct RoutineProgress: Equatable {
    var completed: Set<RoutineStep>
    /// The day these completions belong to. Nil means nothing recorded yet.
    var day: Date?

    static let empty = RoutineProgress(completed: [], day: nil)

    init(completed: Set<RoutineStep> = [], day: Date? = nil) {
        self.completed = completed
        self.day = day
    }

    init(raw: [String], day: Date?) {
        self.completed = Set(raw.compactMap(RoutineStep.init(rawValue:)))
        self.day = day
    }

    var encoded: [String] {
        // Sorted so the stored payload is stable and a no-op save does not look
        // like a change to anything watching the row.
        completed.map(\.rawValue).sorted()
    }

    /// Progress as it stands *now*. A stamp from an earlier day means the
    /// routine has come round again, so yesterday's ticks clear.
    func rolling(now: Date = Date()) -> RoutineProgress {
        guard let day, day.startOfDay == now.startOfDay else { return .empty }
        return self
    }

    func marking(_ step: RoutineStep, now: Date = Date()) -> RoutineProgress {
        var rolled = rolling(now: now)
        rolled.completed.insert(step)
        rolled.day = now.startOfDay
        return rolled
    }

    /// The next unfinished link, in routine order. Nil when the chain is done
    /// for today - which is when the card should go quiet rather than invent
    /// something else to ask for.
    func next(in steps: [RoutineStep], now: Date = Date()) -> RoutineStep? {
        let rolled = rolling(now: now)
        return steps.first { !rolled.completed.contains($0) }
    }

    /// The next unfinished link *after* `step`.
    ///
    /// Different question from `next`, and the handoff wants this one: someone
    /// who skipped the warm-up and went straight to the take should be pointed
    /// at the review, not sent back to a warm-up the take has already made
    /// pointless. The card still shows the skipped link as outstanding.
    func nextAfter(_ step: RoutineStep, in steps: [RoutineStep], now: Date = Date()) -> RoutineStep? {
        guard let index = steps.firstIndex(of: step) else { return nil }
        let rolled = rolling(now: now)
        return steps[steps.index(after: index)...].first { !rolled.completed.contains($0) }
    }

    func isDone(in steps: [RoutineStep], now: Date = Date()) -> Bool {
        next(in: steps, now: now) == nil
    }

    /// The link the Today card deals: the first unfinished one after the
    /// furthest the user has got.
    ///
    /// The card shows one step at a time, so a link skipped on the way is
    /// passed, not outstanding - dealing a warm-up after the take is done
    /// would be dealing nonsense. The take itself is never passed: opening an
    /// old breakdown from History ticks the review without a take today.
    /// `completed` must already be rolled to today.
    static func upNext(in steps: [RoutineStep], completed: Set<RoutineStep>) -> RoutineStep? {
        let furthest = steps.lastIndex { completed.contains($0) } ?? -1
        return steps.indices
            .first { !completed.contains(steps[$0]) && ($0 > furthest || steps[$0].isPinned) }
            .map { steps[$0] }
    }
}
