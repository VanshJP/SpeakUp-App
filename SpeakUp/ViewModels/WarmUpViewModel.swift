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

    func selectExercise(_ exercise: WarmUpExercise) {
        currentExercise = exercise
        currentStepIndex = 0
        isComplete = false
        timeRemaining = exercise.steps.first?.durationSeconds ?? 0
    }

    func start() {
        isRunning = true
        startTimer()
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        currentStepIndex = 0
        isComplete = false
        if let step = currentExercise?.steps.first {
            timeRemaining = step.durationSeconds
        }
    }

    func skip() {
        advanceStep()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
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
            Haptics.light()
        } else {
            // Exercise complete
            isRunning = false
            isComplete = true
            timer?.invalidate()
            timer = nil
            Haptics.success()
        }
    }

    func cleanup() {
        timer?.invalidate()
        timer = nil
    }
}
