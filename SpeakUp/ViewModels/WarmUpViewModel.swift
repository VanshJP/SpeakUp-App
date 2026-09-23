import Foundation
import SwiftUI

@Observable
class WarmUpViewModel {

    var currentExercise: WarmUpExercise?
    var currentStepIndex = 0
    var isRunning = false
    var timeRemaining: Int = 0
    var isComplete = false
    var selectedRounds: Int = 3
    /// False until the first Begin, so the runner can open on what the
    /// exercise is and how long it takes instead of mid-step with a clock.
    var hasStarted = false
    /// Seconds left in the "get ready" count before a breathing exercise's
    /// first step, nil when not counting in. A breathing round that starts
    /// the instant Begin is tapped catches you mid-breath.
    var leadInRemaining: Int?

    static let leadInSeconds = 3
    static let roundsRange = 1...10

    private var baseExercise: WarmUpExercise?
    private var timer: Timer?

    /// The focuses the shipped warm-ups actually cover, in declaration order.
    /// Grouping is on outcome rather than on `WarmUpCategory`, which named the
    /// mechanism - "Tongue Twisters", "Articulation" - and left the reader to
    /// work out that both are there to make you understood. The category
    /// survives as the row's tag, where it belongs.
    var availableFocuses: [PracticeFocus] { PracticeToolKind.warmUp.focuses }

    func exercises(for focus: PracticeFocus) -> [WarmUpExercise] {
        DefaultWarmUps.all.filter { $0.category.focus == focus }
    }

    var currentStep: ExerciseStep? {
        guard let exercise = currentExercise,
              currentStepIndex < exercise.steps.count else { return nil }
        return exercise.steps[currentStepIndex]
    }

    /// True for breathing exercises where rounds can be adjusted.
    var canCustomizeRounds: Bool {
        baseExercise?.category == .breathing
    }

    var isLeadingIn: Bool { leadInRemaining != nil }

    var nextStep: ExerciseStep? {
        guard let steps = currentExercise?.steps,
              steps.indices.contains(currentStepIndex + 1) else { return nil }
        return steps[currentStepIndex + 1]
    }

    /// Steps in one breathing round; the whole exercise for everything else.
    var stepsPerRound: Int {
        guard canCustomizeRounds, let base = baseExercise else {
            return max(1, currentExercise?.steps.count ?? 1)
        }
        return max(1, base.steps.count / Self.encodedRounds)
    }

    var totalRounds: Int { canCustomizeRounds ? selectedRounds : 1 }

    var currentRound: Int {
        min(totalRounds, currentStepIndex / stepsPerRound + 1)
    }

    var totalSeconds: Int { currentExercise?.durationSeconds ?? 0 }

    /// Default breathing seeds encode this many rounds (pinned in
    /// `PracticeToolProgressTests`); one round is the first third.
    private static let encodedRounds = 3

    func selectExercise(_ exercise: WarmUpExercise) {
        baseExercise = exercise
        selectedRounds = 3
        applyRounds()
    }

    /// Called when the user changes the rounds stepper before starting.
    func rebuildWithRounds(_ rounds: Int) {
        guard !hasStarted else { return }
        selectedRounds = min(Self.roundsRange.upperBound, max(Self.roundsRange.lowerBound, rounds))
        applyRounds()
    }

    private func applyRounds() {
        guard let exercise = baseExercise else { return }
        let steps: [ExerciseStep]

        if exercise.category == .breathing, exercise.steps.count >= Self.encodedRounds {
            // Default exercises encode 3 rounds; extract one cycle and repeat.
            let cycleSize = max(1, exercise.steps.count / Self.encodedRounds)
            let oneRound = Array(exercise.steps.prefix(cycleSize))
            steps = Array(repeating: oneRound, count: selectedRounds).flatMap { $0 }
        } else {
            steps = exercise.steps
        }

        currentExercise = WarmUpExercise(
            id: exercise.id,
            category: exercise.category,
            title: exercise.title,
            instructions: exercise.instructions,
            steps: steps,
            durationSeconds: steps.reduce(0) { $0 + $1.durationSeconds }
        )
        currentStepIndex = 0
        isComplete = false
        // A runner left running by a mid-exercise ✕ must not present the next
        // one pre-paused - the play button would need two taps to start.
        isRunning = false
        hasStarted = false
        leadInRemaining = nil
        timeRemaining = steps.first?.durationSeconds ?? 0
    }

    /// Prepares the same exercise for another run without leaving the runner.
    func goAgain() {
        reset()
    }

    /// Begin, or resume after a pause. The first Begin on a breathing
    /// exercise counts in before the first step.
    func start() {
        guard !isComplete else { return }
        if !hasStarted {
            hasStarted = true
            if currentExercise?.category == .breathing {
                leadInRemaining = Self.leadInSeconds
                isRunning = true
                ChirpPlayer.shared.play(.tick)
                startTimer()
                return
            }
        }
        isRunning = true
        if !isLeadingIn {
            chirpForCurrentStep()
        }
        startTimer()
    }

    func togglePlayback() {
        if isRunning { pause() } else { start() }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        applyRounds()
    }

    func skip() {
        if isLeadingIn {
            // Skip on the count-in means "start now", not "lose step one".
            leadInRemaining = nil
            chirpForCurrentStep()
            return
        }
        hasStarted = true
        advanceStep()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    @MainActor
    private func tick() {
        guard isRunning else { return }

        if let leadIn = leadInRemaining {
            if leadIn > 1 {
                leadInRemaining = leadIn - 1
                ChirpPlayer.shared.play(.tick)
            } else {
                leadInRemaining = nil
                chirpForCurrentStep()
                Haptics.light()
            }
            return
        }

        if timeRemaining > 1 {
            timeRemaining -= 1
        } else {
            // Finish inside this tick. Waiting for a later tick displayed 0
            // for a full second and stretched every labeled duration -
            // 4-7-8 breathing actually ran 5-8-9.
            timeRemaining = 0
            advanceStep()
        }
    }

    private func advanceStep() {
        guard let exercise = currentExercise else { return }

        if currentStepIndex < exercise.steps.count - 1 {
            currentStepIndex += 1
            timeRemaining = exercise.steps[currentStepIndex].durationSeconds
            chirpForCurrentStep()
            Haptics.light()
        } else {
            isRunning = false
            isComplete = true
            timer?.invalidate()
            timer = nil
            if let exerciseId = currentExercise?.id {
                CurriculumActivitySignalStore.markExerciseCompleted(exerciseId)
            }
            Haptics.success()
        }
    }

    private func chirpForCurrentStep() {
        guard let step = currentStep else { return }
        if currentExercise?.category == .breathing {
            switch step.animation {
            case .expand:   ChirpPlayer.shared.play(.inhale)
            case .hold:     ChirpPlayer.shared.play(.hold)
            case .contract: ChirpPlayer.shared.play(.exhale)
            }
        } else {
            ChirpPlayer.shared.play(.tick)
        }
    }

    func cleanup() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
}
