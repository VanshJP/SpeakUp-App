import Foundation
import SwiftData
import os.log

/// Runs the user's practice routine: records what has been done today, and
/// hands the finished step off to the next one.
///
/// The handoff is the whole point. Every one of these steps already existed as
/// a door on Today or in the Library; what was missing was the sentence that
/// says which door is next, at the only moment it is useful — the second the
/// last thing finished. Finishing a warm-up and being returned to a home screen
/// of eight equally weighted choices is where a routine dies.
///
/// `.shared` like every other non-injected service (see `AGENTS.md`). MainActor
/// because it writes the main `ModelContext` and drives UI state.
@MainActor
@Observable
final class PracticeRoutineService {
    static let shared = PracticeRoutineService()

    private let logger = Logger.app("Routine")
    private var modelContext: ModelContext?

    /// A finished step and the one that follows it. Set by `complete`, and
    /// rendered by `ContentView` as a bar over the tab surface — which is why
    /// it survives the sheet that set it closing.
    struct Handoff: Equatable {
        var finished: RoutineStep
        var next: RoutineStep
    }

    private(set) var handoff: Handoff?

    /// A step the user has asked to start. `ContentView` opens the tools;
    /// `TodayView` owns `.session`, because the day's prompt and duration live
    /// there and nowhere else. Whoever handles a case clears it.
    var pendingStep: RoutineStep?

    private init() {}

    func configure(with context: ModelContext) {
        modelContext = context
    }

    // MARK: - State

    private var settings: UserSettings? {
        guard let modelContext else { return nil }
        return try? modelContext.fetch(FetchDescriptor<UserSettings>()).first
    }

    var steps: [RoutineStep] { settings?.practiceRoutine ?? RoutineStep.defaultSteps }

    var progress: RoutineProgress { settings?.routineProgress ?? .empty }

    /// The link the routine is waiting on, or nil when today's chain is done.

    // MARK: - Completion

    /// Tick a step off for today and, if the chain continues, offer the next.
    ///
    /// Idempotent: runners call this from view state that can re-fire (a
    /// `.onChange` that re-evaluates, a result screen that redraws), and a
    /// second tick must not re-raise a handoff the user already waved off.
    func complete(_ step: RoutineStep) {
        guard let settings, let modelContext else { return }

        let current = settings.routineProgress
        guard !current.completed.contains(step) else { return }

        settings.apply(progress: current.marking(step))
        try? modelContext.save()
        logger.info("Routine step complete: \(step.rawValue, privacy: .public)")

        // The user took the bar's suggestion. Leaving it up would have it
        // pointing at the screen they are already on — a take routed straight
        // into its own breakdown does exactly this.
        if handoff?.next == step { handoff = nil }

        // Only steps that are actually in this user's chain get a handoff. A
        // warm-up taken on a whim is not a routine, and treating it as one would
        // make the bar appear for anyone who ever opens a tool.
        guard steps.contains(step), let next = progress.nextAfter(step, in: steps) else { return }
        handoff = Handoff(finished: step, next: next)
        // Light, not success: the runner that just finished has already played
        // its own success haptic, and two buzzes on one event read as a glitch.
        Haptics.light()
    }

    /// Take the handoff: clear the bar and ask for the next step to open.
    func advance() {
        guard let handoff else { return }
        pendingStep = handoff.next
        self.handoff = nil
    }

    func dismissHandoff() {
        handoff = nil
    }

    /// Start a step directly — the routine card's own controls, which are not a
    /// handoff and should not clear one that is showing.
    func start(_ step: RoutineStep) {
        pendingStep = step
    }

    func clearPendingStep() {
        pendingStep = nil
    }

    // MARK: - Editing

    func update(_ steps: [RoutineStep]) {
        guard let settings, let modelContext else { return }
        settings.apply(routine: steps)
        try? modelContext.save()
    }
}
