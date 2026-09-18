import Foundation
import SwiftUI

// MARK: - Session State

enum ReadAloudSessionState: Sendable {
    case idle
    case listening
    case finished
}

// MARK: - Read Aloud Result

struct ReadAloudResult: Identifiable {
    /// Presentation identity, not data: the result screen is presented by
    /// value so the cover can never outlive the result it is drawing.
    let id = UUID()
    let passage: ReadAloudPassage
    let accuracy: Double
    let matchedWords: Int
    let totalWords: Int
    let mismatchedWords: Int
    let timeTaken: TimeInterval
    let wordStates: [WordMatchState]
    /// Set when the session ended without a fair measurement — the recognizer
    /// died mid-read, or nothing was heard at all. The result screen shows it
    /// instead of letting a bare "0% · Complete" stand as a verdict.
    var notice: String?

    var score: Int {
        Int(accuracy.rounded())
    }
}

// MARK: - Read Aloud View Model

@MainActor @Observable
class ReadAloudViewModel {
    let service = ReadAloudService()

    /// Session-scoped audio service: owns mic permission and the
    /// record-capable session configuration. The read-aloud engine taps the
    /// input directly, but without this setup a fresh launch runs under
    /// whatever ambient category lingers — silent buffers, cryptic failures.
    private let audioService = AudioService()

    var sessionState: ReadAloudSessionState = .idle
    var selectedPassage: ReadAloudPassage?
    var result: ReadAloudResult?
    var errorMessage: String?
    var elapsedTime: TimeInterval = 0

    private var startTime: Date?
    private var timerTask: Task<Void, Never>?
    /// Seconds spent listening to the model line. Subtracted from the take so
    /// the result's words-per-minute is measured against time the reader was
    /// actually reading.
    private var modelPlaybackSeconds: TimeInterval = 0
    private var modelPlaybackStarted: Date?

    /// Lifetime read-aloud count. In UserDefaults for the same reason as the
    /// drill counter: the view model is rebuilt per presentation, so anything
    /// held in memory buckets every session as the first one.
    private static let startCountKey = "analytics.readAloudSessionsStarted"
    private var sessionsStarted: Int {
        get { UserDefaults.standard.integer(forKey: Self.startCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.startCountKey) }
    }

    // MARK: - Catalog

    /// Focuses the shipped catalog covers, in declaration order.
    ///
    /// The catalog is no longer filtered in software. It carried two filter
    /// bars — outcome and length — over twenty passages whose rows already
    /// print both, and a "12 of 20 passages" caption to explain what the bars
    /// had done. Grouping by outcome is the whole taxonomy now.
    var availableFocuses: [PracticeFocus] { PracticeToolKind.readAloud.focuses }

    func passages(for focus: PracticeFocus) -> [ReadAloudPassage] {
        DefaultReadAloudPassages.all.filter { $0.category.focus == focus }
    }

    // MARK: - Session Control

    func startSession(passage: ReadAloudPassage) async {
        selectedPassage = passage
        service.configure(passage: passage)
        errorMessage = nil
        result = nil
        elapsedTime = 0
        modelPlaybackSeconds = 0
        modelPlaybackStarted = nil

        let authorized = await service.requestAuthorization()
        // The auto-start runs in the session view's `.task`, which cancels on
        // disappear — bail rather than spin up an engine nobody will stop.
        guard !Task.isCancelled else { return }
        guard authorized else {
            errorMessage = ReadAloudError.authorizationDenied.errorDescription
            return
        }

        guard await audioService.requestPermission() else {
            errorMessage = "Microphone access is needed to score your reading. Enable it in Settings."
            return
        }
        guard !Task.isCancelled else { return }

        do {
            try service.start()
            sessionState = .listening
            startTime = Date()
            startTimer()
            sessionsStarted += 1
            AnalyticsService.shared.log(
                .practiceStarted(useCase: "read_aloud", sessionNumber: sessionsStarted)
            )
            Haptics.medium()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopSession() {
        service.stop()
        stopTimer()

        guard let passage = selectedPassage else { return }

        endModelPlaybackClock()
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let timeTaken = max(0, elapsed - modelPlaybackSeconds)
        let heardNothing = service.matchedWordCount == 0 && service.mismatchedWordCount == 0 && timeTaken > 3

        result = ReadAloudResult(
            passage: passage,
            accuracy: service.accuracyPercentage,
            matchedWords: service.matchedWordCount,
            totalWords: passage.wordCount,
            mismatchedWords: service.mismatchedWordCount,
            timeTaken: timeTaken,
            wordStates: service.wordStates,
            notice: notice(for: timeTaken, heardNothing: heardNothing)
        )

        sessionState = .finished
        // Bailing out before matching a word shouldn't advance curriculum signals
        if service.matchedWordCount > 0 {
            CurriculumActivitySignalStore.markReadAloudCompleted()
        }
        if result?.notice != nil {
            Haptics.warning()
        } else {
            Haptics.success()
        }
    }

    /// A degraded session says so on its result screen instead of standing as
    /// a verdict: recognition died mid-read, or the mic never picked up a word.
    private func notice(for timeTaken: TimeInterval, heardNothing: Bool) -> String? {
        if let failure = service.recognitionFailureMessage {
            return failure
        }
        if heardNothing {
            return "We didn't catch any words. Try speaking up, or move somewhere quieter."
        }
        return nil
    }

    func reset() {
        service.stop()
        stopTimer()
        sessionState = .idle
        selectedPassage = nil
        result = nil
        errorMessage = nil
        elapsedTime = 0
        modelPlaybackSeconds = 0
        modelPlaybackStarted = nil
    }

    // MARK: - Hear the model

    /// Shadow practice, as a button rather than a mode.
    ///
    /// It used to be a toggle at the top of the catalog that you had to flip
    /// *before* opening a passage, which meant the one moment you want to hear
    /// the line — halfway through, having just fumbled it — was the one moment
    /// you could not. Holding the read costs nothing now: recognition comes
    /// back on the same transcript.
    func pauseForModel() {
        guard sessionState == .listening, !service.isPaused else { return }
        modelPlaybackStarted = Date()
        service.pauseForModelPlayback()
    }

    func resumeAfterModel() {
        guard sessionState == .listening, service.isPaused else { return }
        endModelPlaybackClock()
        service.resumeAfterModelPlayback()
    }

    private func endModelPlaybackClock() {
        guard let modelPlaybackStarted else { return }
        modelPlaybackSeconds += Date().timeIntervalSince(modelPlaybackStarted)
        self.modelPlaybackStarted = nil
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
    /// Listening is held while the model line plays. The mic indicator says so
    /// rather than claiming to be listening to a synthesiser.
    var isHearingModel: Bool { service.isPaused }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let start = self.startTime else { continue }
                self.elapsedTime = Date().timeIntervalSince(start)

                guard self.sessionState == .listening else { continue }

                // A recognizer that died for good ends the session now —
                // letting the clock run on produces a confident-looking zero.
                if self.service.recognitionFailureMessage != nil {
                    self.stopSession()
                    continue
                }

                // Backstop for a mic that went quiet without saying why.
                // Recognition now survives its own request boundaries, so a
                // service that is no longer listening mid-session has hit
                // something none of us predicted — land on the result screen
                // with the words that were matched rather than leaving a live
                // clock over a dead microphone and a disabled Done button,
                // which is what made a dropped read feel like a lost one.
                if !self.service.isListening {
                    self.stopSession()
                    continue
                }

                // Auto-stop if service finished
                if self.service.isComplete {
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
        elapsedTime.minutesSeconds
    }
}
