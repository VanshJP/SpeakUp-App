import Foundation
import SwiftUI

// MARK: - Session State

enum ReadAloudSessionState: Sendable {
    case idle
    case listening
    case finished
}

// MARK: - Read Aloud Result

struct ReadAloudResult {
    let passage: ReadAloudPassage
    let accuracy: Double
    let matchedWords: Int
    let totalWords: Int
    let mismatchedWords: Int
    let timeTaken: TimeInterval
    let wordStates: [WordMatchState]

    var score: Int {
        Int(accuracy.rounded())
    }
}

// MARK: - Read Aloud View Model

@MainActor @Observable
class ReadAloudViewModel {
    let service = ReadAloudService()

    var selectedDifficulty: ReadAloudDifficulty? {
        didSet { applyFilters() }
    }
    var selectedCategory: ReadAloudCategory? {
        didSet { applyFilters() }
    }
    var sessionState: ReadAloudSessionState = .idle
    var selectedPassage: ReadAloudPassage?
    var result: ReadAloudResult?
    var errorMessage: String?
    var elapsedTime: TimeInterval = 0
    private(set) var filteredPassages: [ReadAloudPassage] = DefaultReadAloudPassages.all

    private var startTime: Date?
    private var timerTask: Task<Void, Never>?

    // MARK: - Filtered Passages

    var passages: [ReadAloudPassage] {
        filteredPassages
    }

    init() {
        applyFilters()
    }

    private func applyFilters() {
        filteredPassages = DefaultReadAloudPassages.all.filter { passage in
            if let difficulty = selectedDifficulty, passage.difficulty != difficulty {
                return false
            }
            if let category = selectedCategory, passage.category != category {
                return false
            }
            return true
        }
    }

    // MARK: - Session Control

    func startSession(passage: ReadAloudPassage) async {
        selectedPassage = passage
        service.configure(passage: passage)
        errorMessage = nil
        result = nil
        elapsedTime = 0

        let authorized = await service.requestAuthorization()
        guard authorized else {
            errorMessage = ReadAloudError.authorizationDenied.errorDescription
            return
        }

        do {
            try service.start()
            sessionState = .listening
            startTime = Date()
            startTimer()
            Haptics.medium()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopSession() {
        service.stop()
        stopTimer()

        guard let passage = selectedPassage else { return }

        let timeTaken = startTime.map { Date().timeIntervalSince($0) } ?? 0

        result = ReadAloudResult(
            passage: passage,
            accuracy: service.accuracyPercentage,
            matchedWords: service.matchedWordCount,
            totalWords: passage.wordCount,
            mismatchedWords: service.mismatchedWordCount,
            timeTaken: timeTaken,
            wordStates: service.wordStates
        )

        sessionState = .finished
        CurriculumActivitySignalStore.markReadAloudCompleted()
        Haptics.success()
    }

    func reset() {
        service.stop()
        stopTimer()
        sessionState = .idle
        selectedPassage = nil
        result = nil
        errorMessage = nil
        elapsedTime = 0
    }

    func retryPassage() async {
        guard let passage = selectedPassage else { return }
        await startSession(passage: passage)
    }

    // MARK: - Observable Service Properties

    var wordStates: [WordMatchState] { service.wordStates }
    var currentWordIndex: Int { service.currentWordIndex }
    var progressPercentage: Double { service.progressPercentage }
    var accuracyPercentage: Double { service.accuracyPercentage }
    var isListening: Bool { service.isListening }

    var isComplete: Bool {
        service.isComplete
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let start = self.startTime else { continue }
                self.elapsedTime = Date().timeIntervalSince(start)

                // Auto-stop if service finished
                if self.service.isComplete && self.sessionState == .listening {
                    self.stopSession()
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    var formattedElapsedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
