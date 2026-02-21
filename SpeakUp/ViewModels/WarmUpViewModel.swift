import Foundation
import SwiftUI

@Observable
class WarmUpViewModel {
    var selectedCategory: WarmUpCategory = .breathing
    var currentExercise: WarmUpExercise?
    var currentStepIndex = 0
    var isRunning = false
    var timeRemaining: Int = 0
    var isComplete = false
    var selectedRounds: Int = 3

    private var baseExercise: WarmUpExercise?
    private var timer: Timer?

    var exercises: [WarmUpExercise] {
        DefaultWarmUps.all.filter { $0.category == selectedCategory }
    }

    var currentStep: ExerciseStep? {
        guard let exercise = currentExercise,
              currentStepIndex < exercise.steps.count else { return nil }
        return exercise.steps[currentStepIndex]
    }

    var progress: Double {
        guard let exercise = currentExercise, !exercise.steps.isEmpty else { return 0 }
        return Double(currentStepIndex) / Double(exercise.steps.count)
    }

    /// True for breathing exercises where rounds can be adjusted.
    var canCustomizeRounds: Bool {
        baseExercise?.category == .breathing
    }

    func selectExercise(_ exercise: WarmUpExercise) {
        baseExercise = exercise
        selectedRounds = 3
        applyRounds()
    }

    /// Called when the user changes the rounds stepper before starting.
    func rebuildWithRounds(_ rounds: Int) {
        guard !isRunning else { return }
        selectedRounds = rounds
        applyRounds()
    }

    private func applyRounds() {
        guard let exercise = baseExercise else { return }
        let steps: [ExerciseStep]

        if exercise.category == .breathing, exercise.steps.count >= 3 {
            // Default exercises encode 3 rounds; extract one cycle and repeat.
            let defaultRounds = 3
            let cycleSize = max(1, exercise.steps.count / defaultRounds)
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
        timeRemaining = steps.first?.durationSeconds ?? 0
    }

    func start() {
        isRunning = true
        chirpForCurrentStep()
        startTimer()
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

        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
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
    }
}
