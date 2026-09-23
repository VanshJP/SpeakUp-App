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
    /// Set when the session ended without a fair measurement - the recognizer
    /// died mid-read, or nothing was heard at all. The result screen shows it
    /// instead of letting a bare "0% · Complete" stand as a verdict.
    var notice: String?
    /// Consonants that came out as another sound or were not heard, read
    /// from the words heard in place of the page's.
    var soundCheck: SoundCheck = .empty

    var score: Int {
        Int(accuracy.rounded())
    }

    /// The stretches the reader stumbled on, as one short passage to run next.
    /// Nil when nothing needs another pass.
    var missedPhrasesText: String? {
        Self.missedPhrases(in: passage.words, states: wordStates)
    }

    /// Each missed or skipped word with the words either side of it, as
    /// `ReadAloudPassage.practiceText(around:in:context:)` builds them.
    ///
    /// Retry replays the whole passage, which spends most of the next take on
    /// words that were already clean. This is the deliberate-practice version:
    /// only the parts that went wrong, straight away.
    static func missedPhrases(in words: [String], states: [WordMatchState], context: Int = 2) -> String? {
        let missed = words.indices.filter { $0 < states.count && states[$0].needsAttention }
        return ReadAloudPassage.practiceText(around: missed, in: words, context: context)
    }

    /// What the recognizer heard in place of each missed word, by word index.
    static func heardWords(in states: [WordMatchState]) -> [Int: String] {
        var heard: [Int: String] = [:]
        for (index, state) in states.enumerated() {
            if case .mismatched(let spoken) = state {
                heard[index] = spoken
            }
        }
        return heard
    }
}

// MARK: - Read Aloud View Model

@MainActor @Observable
class ReadAloudViewModel {
    let service = ReadAloudService()

    /// Session-scoped audio service: owns mic permission and the
    /// record-capable session configuration. The read-aloud engine taps the
    /// input directly, but without this setup a fresh launch runs under
    /// whatever ambient category lingers - silent buffers, cryptic failures.
    private let audioService = AudioService()

    var sessionState: ReadAloudSessionState = .idle
    var selectedPassage: ReadAloudPassage?
    var result: ReadAloudResult?
    var errorMessage: String?
    var elapsedTime: TimeInterval = 0

    private var startTime: Date?
    private var timerTask: Task<Void, Never>?

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
    /// bars - outcome and length - over twenty passages whose rows already
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

        let authorized = await service.requestAuthorization()
        // The auto-start runs in the session view's `.task`, which cancels on
        // disappear - bail rather than spin up an engine nobody will stop.
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

        let timeTaken = readingTime()
        let heardNothing = service.matchedWordCount == 0 && service.mismatchedWordCount == 0 && timeTaken > 3

        result = ReadAloudResult(
            passage: passage,
            accuracy: service.accuracyPercentage,
            matchedWords: service.matchedWordCount,
            totalWords: passage.wordCount,
            mismatchedWords: service.mismatchedWordCount,
            timeTaken: timeTaken,
            wordStates: service.wordStates,
            notice: notice(for: timeTaken, heardNothing: heardNothing),
            soundCheck: SoundCheck(
                passage: passage.words,
                heard: ReadAloudResult.heardWords(in: service.wordStates)
            )
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
    /// a verdict: the reader finished while the mic was stalled, or the mic
    /// never picked up a word.
    private func notice(for timeTaken: TimeInterval, heardNothing: Bool) -> String? {
        if let failure = service.recognitionFailureMessage {
            return "The mic stopped before you finished, so this scores the part we heard. \(failure)"
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
    }

    // MARK: - Hear the model

    /// Shadow practice, as a button rather than a mode.
    ///
    /// It used to be a toggle at the top of the catalog that you had to flip
    /// *before* opening a passage, which meant the one moment you want to hear
    /// the line - halfway through, having just fumbled it - was the one moment
    /// you could not. Holding the read costs nothing now: recognition comes
    /// back on the same transcript, and the service stops the clock while the
    /// model plays.
    func pauseForModel() {
        guard sessionState == .listening, !service.isPaused else { return }
        service.pauseForModelPlayback()
    }

    func resumeAfterModel() {
        guard sessionState == .listening, service.isPaused else { return }
        service.resumeAfterModelPlayback()
    }

    /// The mic stalled and the reader wants it back. Their place is kept.
    func resumeListening() {
        guard sessionState == .listening else { return }
        service.resumeListening()
    }

    /// Wall-clock time since the read started, less every second it spent
    /// held - hearing the model, through a call, in the background, or
    /// stalled. What the clock shows and what words per minute divides by.
    private func readingTime(at date: Date = Date()) -> TimeInterval {
        guard let startTime else { return 0 }
        return max(0, date.timeIntervalSince(startTime) - service.heldDuration(until: date))
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
    /// A call, Siri or leaving the app has the mic. The read picks up again on
    /// its own when the app is back.
    var isHeldBySystem: Bool { service.isHeldBySystem }
    /// The mic stopped and automatic recovery gave up. Resume or Done.
    var isStalled: Bool { service.isStalled }
    /// The recognizer is actually hearing the room. A word's pronunciation can
    /// only play when it is not, or the reader would be scored on the
    /// synthesiser.
    var isMicOpen: Bool {
        service.isListening && !service.isPaused && !service.isHeldBySystem && !service.isStalled
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.startTime != nil else { continue }
                self.elapsedTime = self.readingTime()

                guard self.sessionState == .listening else { continue }

                // A recognizer that stops for good no longer ends the session:
                // the service holds the read as stalled, the clock stops with
                // it, and the reader chooses Resume or Done. Ending it here is
                // what used to turn a dropped mic into a read that started
                // again from the first word.

                // Backstop for a mic that went quiet without saying why.
                // Recognition survives its own request boundaries and every
                // hold the service knows about, so a service that is no longer
                // listening mid-session has hit something none of us
                // predicted - land on the result screen with the words that
                // were matched rather than leaving a live clock over a dead
                // microphone and a disabled Done button.
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
