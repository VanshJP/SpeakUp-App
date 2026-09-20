import Foundation
import Speech
import AVFoundation
import os
import os.log

// MARK: - Word Match State

enum WordMatchState: Equatable {
    case upcoming
    case current
    case matched
    case mismatched(spoken: String)
    case skipped

    /// The reader is past this word, however it went. Drives whether a word is
    /// tappable and whether it still animates.
    var isSettled: Bool {
        switch self {
        case .matched, .mismatched, .skipped: return true
        case .upcoming, .current: return false
        }
    }

    /// Settled but not clean - the states worth colouring in a transcript.
    var needsAttention: Bool {
        switch self {
        case .mismatched, .skipped: return true
        default: return false
        }
    }
}

// MARK: - Read Aloud Error

enum ReadAloudError: LocalizedError {
    case speechNotAvailable
    case authorizationDenied
    case audioEngineFailure(String)
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .speechNotAvailable:
            return "Speech recognition is not available on this device."
        case .authorizationDenied:
            return "Speech recognition permission was denied. Enable it in Settings."
        case .audioEngineFailure(let detail):
            return "Audio engine failed: \(detail)"
        case .recognitionFailed(let detail):
            return "Recognition failed: \(detail)"
        }
    }
}

// MARK: - Read Aloud Service

@Observable
class ReadAloudService {
    private let logger = Logger.app("ReadAloud")

    var wordStates: [WordMatchState] = []
    var currentWordIndex: Int = 0
    var matchedWordCount: Int = 0
    var mismatchedWordCount: Int = 0
    var isListening = false

    /// Set when recognition dies for good - missing on-device assets, or a
    /// capture graph that will not come back. The view model surfaces this as a
    /// result notice instead of letting the session end in a confident-looking
    /// zero.
    ///
    /// A request that merely *finished* is not a failure and must never land
    /// here. See `handleSegmentEnd`.
    var recognitionFailureMessage: String?

    private var referenceWords: [String] = []
    private var normalizedReference: [String] = []
    private var lastProcessedTranscript: String = ""

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    /// Read from the realtime audio thread by the tap block, and swapped on the
    /// main actor at every re-arm, so it cannot be plain isolated state. The
    /// critical section is one `append`; nilling it from `stopInternal()` while
    /// the tap was mid-append segfaulted exactly like LiveTranscriptionService's
    /// war story.
    private let requestBox = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(uncheckedState: nil)
    private var recognitionTask: SFSpeechRecognitionTask?

    /// One slot per recognition request this session has opened, oldest first;
    /// the live one is last. Alignment runs over the joined text, and that is
    /// what makes a re-arm invisible: SFSpeech starts every request's transcript
    /// at empty, so a single `String` would rewind the reader to word one every
    /// time the recognizer closed a request.
    private var segmentTranscripts: [String] = [""]
    private var activeSegment: Int { max(0, segmentTranscripts.count - 1) }

    /// Segment ids never restart, across every session this service runs.
    /// Cancelling a recognition task makes it fire one last error callback, and
    /// a Retry can open the next session before that lands; with per-session
    /// indices the dead task's transcript would be applied to the new passage.
    /// `segmentBaseID` is the id of `segmentTranscripts[0]`, so a stale id maps
    /// to a negative slot and is dropped.
    private var nextSegmentID = 0
    private var segmentBaseID = 0
    private var activeSegmentID: Int { segmentBaseID + activeSegment }

    /// Newest transcript *per segment*, written on Apple's callback queue and
    /// read on the main actor. Latest-wins within a segment, so a slow frame
    /// drops stale intermediate transcripts instead of queueing them - but a
    /// retired segment's final result can never be clobbered by the live
    /// segment's next partial. See `drainPendingTranscripts()`.
    private let pendingTranscripts = OSAllocatedUnfairLock<[Int: String]>(initialState: [:])
    /// True while exactly one drain is queued on the main actor. Bounds the
    /// number of in-flight tasks to one no matter how fast partials arrive.
    private let isDrainScheduled = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// `removeTap` crashes if no tap is installed - track it explicitly.
    private var isTapInstalled = false

    /// When the live request was opened, and how many requests in a row have
    /// died instantly with nothing to show for it. A recognizer whose on-device
    /// assets are missing fails that way immediately and forever; re-arming it
    /// in a tight loop would spin the CPU behind a screen claiming to listen.
    private var segmentStartedAt = Date.distantPast
    private var unproductiveSegments = 0
    private static let unproductiveSegmentWindow: TimeInterval = 1.0
    private static let maxUnproductiveSegments = 3

    /// Re-arm before a request reaches its own audio-duration ceiling (about a
    /// minute). Swapping early is seamless - the tap appends the next buffer to
    /// the new request - whereas letting the ceiling hit drops whatever was in
    /// flight when the error arrives, which a reader sees as skipped words.
    private static let segmentRolloverInterval: TimeInterval = 45
    private var rolloverTask: Task<Void, Never>?

    /// True between an interruption beginning and ending. Cancelling the
    /// recognition task to get out of a call's way makes it report an error,
    /// and without this the graph-is-dead recovery would answer that by trying
    /// to re-activate a session the call still owns - turning a survivable
    /// pause into a failed session.
    private var isInterrupted = false

    /// True while the reader has asked to hear the model line. Same teardown
    /// as an interruption and the same reason for a flag: the cancelled task
    /// reports an error that must not be answered with a rebuild, because the
    /// rebuild would re-open the mic straight into the synthesiser.
    private(set) var isPaused = false

    /// Recognition is down on purpose. Every recovery path checks this.
    private var isSuspended: Bool { isInterrupted || isPaused }

    /// Tokens only - registered and removed on the main actor, and removed once
    /// more from `deinit`, which is nonisolated. Kept out of observation
    /// tracking so they never participate in change notifications.
    @ObservationIgnored nonisolated(unsafe) private var sessionObservers: [NSObjectProtocol] = []

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    deinit {
        for observer in sessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Configure

    func configure(passage: ReadAloudPassage) {
        referenceWords = passage.words
        normalizedReference = referenceWords.map { Self.normalize($0) }
        wordStates = Array(repeating: .upcoming, count: referenceWords.count)
        currentWordIndex = 0
        matchedWordCount = 0
        mismatchedWordCount = 0
        lastProcessedTranscript = ""
        recognitionFailureMessage = nil
        resetTranscriptSegments()
    }

    private func resetTranscriptSegments() {
        segmentTranscripts = [""]
        segmentBaseID = nextSegmentID
        nextSegmentID += 1
        unproductiveSegments = 0
        pendingTranscripts.withLock { $0 = [:] }
        isDrainScheduled.withLock { $0 = false }
    }

    // MARK: - Start Listening

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw ReadAloudError.speechNotAvailable
        }

        // Idempotent, same rule as LiveTranscriptionService: a Retry racing a
        // ghost start must not stack a second engine and tap on top of the
        // first - tear the old graph down before building a new one.
        if audioEngine != nil || isTapInstalled || recognitionTask != nil {
            stopInternal()
        }

        resetTranscriptSegments()

        let engine = AVAudioEngine()
        do {
            try installTap(on: engine)
            audioEngine = engine
            engine.prepare()
            try engine.start()
        } catch let error as ReadAloudError {
            stopInternal()
            throw error
        } catch {
            stopInternal()
            throw ReadAloudError.audioEngineFailure(error.localizedDescription)
        }

        isListening = true
        guard armRecognition(startNewSegment: false) else {
            stopInternal()
            throw ReadAloudError.speechNotAvailable
        }
        observeSession(engine)
    }

    /// Installs the tap every recognition request is fed through.
    ///
    /// Once per engine, and **before** `engine.start()`. Installing a tap makes
    /// AVAudioEngine reset the input node's format, which reconfigures
    /// AURemoteIO's converter while its realtime IO thread sits inside the input
    /// callback - re-installing one to re-arm recognition is what segfaulted
    /// LiveTranscriptionService about a minute into every session (gotcha §9).
    /// Re-arming swaps `requestBox` and leaves the tap alone.
    private func installTap(on engine: AVAudioEngine) throws {
        let inputNode = engine.inputNode
        var format = inputNode.inputFormat(forBus: 0)
        if format.sampleRate <= 0 {
            format = inputNode.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw ReadAloudError.audioEngineFailure("Invalid microphone format \(format)")
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [requestBox] buffer, _ in
            requestBox.withLock { $0?.append(buffer) }
        }
        isTapInstalled = true
    }

    /// Opens a fresh recognition request on the already-running engine and
    /// points the tap at it.
    ///
    /// The swap happens inside one `withLock`, so the tap moves from the old
    /// request to the new one between two buffers and no audio falls in the
    /// gap. The retired request is flushed rather than cancelled: its own final
    /// transcript still belongs in its own slot.
    ///
    /// - Parameter flushRetired: false when the retired request has already
    ///   finished on its own. `endAudio()` must not be called twice on one
    ///   request, and a request that reported `isFinal` has nothing left to
    ///   flush.
    @discardableResult
    private func armRecognition(startNewSegment: Bool, flushRetired: Bool = true) -> Bool {
        guard let recognizer, recognizer.isAvailable else { return false }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Unconditional: on-device processing is a product guarantee, not a
        // preference. Left unset, the recognizer is free to stream microphone
        // audio to Apple's servers. If the on-device assets are not available
        // the request fails, and failing is the correct outcome here.
        request.requiresOnDeviceRecognition = true

        if startNewSegment {
            segmentTranscripts.append("")
            nextSegmentID += 1
        }
        let segment = activeSegmentID

        let retired = requestBox.withLock { box -> SFSpeechAudioBufferRecognitionRequest? in
            let previous = box
            box = request
            return previous
        }
        if flushRetired { retired?.endAudio() }

        segmentStartedAt = Date()
        recognitionTask = recognizer.recognitionTask(with: request) {
            [weak self, pendingTranscripts, isDrainScheduled] result, error in

            if let result {
                // `SFSpeechRecognitionResult` is not `Sendable`, so the string
                // is lifted out here rather than handing the object to a
                // `@MainActor` task. Hoisted out of the lock deliberately:
                // `withLock` takes a `@Sendable` closure.
                //
                // Updates coalesce. Partial results fire many times a second
                // and each one used to spawn its own task. Once the main actor
                // fell behind - and it did, see the layout cache in
                // `WrappingHStack` - those tasks queued without bound, each
                // retaining a result. That is the read that froze and then died
                // around the twenty-second mark. Latest-wins: park the newest
                // transcript, keep one drain in flight.
                let transcript = result.bestTranscription.formattedString
                pendingTranscripts.withLock { $0[segment] = transcript }
                let needsDrain = isDrainScheduled.withLock { scheduled -> Bool in
                    guard !scheduled else { return false }
                    scheduled = true
                    return true
                }
                if needsDrain {
                    Task { @MainActor in
                        self?.drainPendingTranscripts()
                    }
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                // Resolve the message here too: `any Error` is not `Sendable`
                // either, so only the string crosses over.
                let failure: String? = error.flatMap {
                    ReadAloudError.recognitionFailed($0.localizedDescription).errorDescription
                }
                Task { @MainActor in
                    self?.handleSegmentEnd(segment: segment, failure: failure)
                }
            }
        }

        scheduleRollover()
        return true
    }

    // MARK: - Staying alive

    /// A recognition request ended. That is **routine**, not a failure: SFSpeech
    /// finalizes a request after a pause in speech, and again when the request
    /// reaches its own audio-duration ceiling. A passage read at a natural pace
    /// triggers both, several times.
    ///
    /// This used to tear the whole graph down - engine, tap and all - which is
    /// what dropped the mic halfway through a read and forced a restart. Re-arm
    /// instead, keeping the engine, the tap, and every word already matched.
    private func handleSegmentEnd(segment segmentID: Int, failure: String?) {
        guard isListening, !isSuspended else { return }
        // A retired request delivering its own final is the expected shape of a
        // rollover, and a task cancelled by the previous session reports an
        // error long after its slots are gone; only the live request asks for
        // anything.
        guard segmentID == activeSegmentID else { return }

        // Apply whatever it finished with before retiring the slot.
        drainPendingTranscripts()
        guard isListening, segmentID == activeSegmentID else { return }

        let produced = !segmentTranscripts[activeSegment]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let lifetime = Date().timeIntervalSince(segmentStartedAt)
        if produced || lifetime >= Self.unproductiveSegmentWindow {
            unproductiveSegments = 0
        } else {
            unproductiveSegments += 1
        }

        guard unproductiveSegments < Self.maxUnproductiveSegments else {
            fail(with: failure ?? ReadAloudError
                .recognitionFailed("Speech recognition stopped responding.")
                .errorDescription)
            return
        }

        guard let engine = audioEngine, engine.isRunning else {
            // The graph went away under us - a route change, or media services
            // resetting. Rebuilding is the same job as a configuration change.
            rebuildCaptureGraph(reason: "engine stopped")
            return
        }

        // The request that just ended has already flushed itself.
        guard armRecognition(startNewSegment: true, flushRetired: false) else {
            fail(with: failure ?? ReadAloudError.speechNotAvailable.errorDescription)
            return
        }
    }

    /// Rolls the live request over before it reaches its ceiling. Unlike
    /// `handleSegmentEnd` this runs while the request is still healthy, so the
    /// retired one is flushed and keeps producing into its own slot.
    private func scheduleRollover() {
        rolloverTask?.cancel()
        rolloverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.segmentRolloverInterval))
            guard !Task.isCancelled else { return }
            self?.rollOverSegment()
        }
    }

    private func rollOverSegment() {
        guard isListening, !isSuspended, let engine = audioEngine, engine.isRunning else { return }
        guard armRecognition(startNewSegment: true) else {
            fail(with: ReadAloudError.speechNotAvailable.errorDescription)
            return
        }
    }

    /// The two ways a live capture graph dies without anyone asking it to.
    ///
    /// **Configuration change** - AirPods connect, a headset is unplugged,
    /// another app reshapes the shared session. AVAudioEngine stops itself and
    /// the tap's format goes stale. Nothing throws; the mic simply goes quiet
    /// for the rest of the read.
    ///
    /// **Interruption** - a call, Siri, an alarm. The session is deactivated
    /// under us and has to be re-activated before the engine will start again.
    private func observeSession(_ engine: AVAudioEngine) {
        removeSessionObservers()
        let center = NotificationCenter.default

        let configuration = center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildCaptureGraph(reason: "configuration change")
            }
        }

        // The type is read out here, on the notification queue: `userInfo` is
        // `[AnyHashable: Any]` and cannot cross into the task.
        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(type: type)
            }
        }

        sessionObservers = [configuration, interruption]
    }

    private func removeSessionObservers() {
        for observer in sessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionObservers = []
    }

    private func handleInterruption(type: UInt?) {
        guard
            isListening,
            let type,
            let interruption = AVAudioSession.InterruptionType(rawValue: type)
        else { return }

        switch interruption {
        case .began:
            // The system has already stopped the engine. Drop recognition so no
            // stale task outlives the call, and keep every matched word: the
            // read resumes where the reader left it.
            isInterrupted = true
            teardownRecognition()
            audioEngine?.stop()
        case .ended:
            // Rebuild regardless of what the options say. `.shouldResume` is
            // advice about resuming *playback*; a reader who has just put the
            // phone down wants the mic back either way, and the rebuild
            // reports honestly if the session really is still taken.
            isInterrupted = false
            rebuildCaptureGraph(reason: "interruption ended")
        @unknown default:
            break
        }
    }

    /// Holds the read while the TTS model line plays.
    ///
    /// Shadow practice used to be a mode chosen before the passage opened, on
    /// a toggle at the top of the catalog. It is a button inside the session
    /// now, usable at any point in a read, which only works if hearing the
    /// model does not cost you the words you have already matched. Same
    /// teardown as an interruption - a live mic would score the synthesiser as
    /// the reader - and the same rebuild on the way back, with
    /// `segmentTranscripts` untouched.
    func pauseForModelPlayback() {
        guard isListening, !isSuspended else { return }
        isPaused = true
        teardownRecognition()
        audioEngine?.stop()
    }

    func resumeAfterModelPlayback() {
        guard isListening, isPaused else { return }
        isPaused = false
        rebuildCaptureGraph(reason: "model line finished")
    }

    /// Rebuilds the capture graph in place and re-arms recognition on it,
    /// keeping `segmentTranscripts` - and therefore the reader's place in the
    /// passage - intact.
    private func rebuildCaptureGraph(reason: String) {
        guard isListening, !isSuspended else { return }
        logger.info("Read Aloud rebuilding capture graph: \(reason, privacy: .public)")

        teardownRecognition()
        // Stop the engine *before* removing the tap (gotcha §9).
        audioEngine?.stop()
        removeTapIfNeeded()
        removeSessionObservers()
        audioEngine = nil

        // An interruption leaves the session deactivated; the engine will not
        // start again until it is back.
        try? AVAudioSession.sharedInstance().setActive(true)

        let engine = AVAudioEngine()
        do {
            try installTap(on: engine)
            audioEngine = engine
            engine.prepare()
            try engine.start()
        } catch {
            fail(with: ReadAloudError.audioEngineFailure(error.localizedDescription).errorDescription)
            return
        }

        guard armRecognition(startNewSegment: true) else {
            fail(with: ReadAloudError.speechNotAvailable.errorDescription)
            return
        }
        observeSession(engine)
    }

    private func fail(with message: String?) {
        if recognitionFailureMessage == nil {
            recognitionFailureMessage = message
                ?? ReadAloudError.recognitionFailed("Speech recognition stopped.").errorDescription
        }
        stopInternal()
    }

    // MARK: - Stop

    func stop() {
        // `stopInternal` flushes the live request through `teardownRecognition`
        // - `endAudio()` must not be called twice on one request.
        stopInternal()
    }

    private func stopInternal() {
        // First, so a cancel-induced error callback cannot re-arm recognition
        // on the way down.
        isListening = false
        isInterrupted = false
        isPaused = false

        removeSessionObservers()
        teardownRecognition()

        // Stop before removing the tap: mutating the tap on a running engine
        // reconfigures the live AURemoteIO underneath its IO thread (gotcha §9).
        audioEngine?.stop()
        removeTapIfNeeded()
        audioEngine = nil

        pendingTranscripts.withLock { $0 = [:] }
        isDrainScheduled.withLock { $0 = false }
    }

    /// Drops the recognition request and task without touching the engine or
    /// the tap, which outlive individual requests.
    private func teardownRecognition() {
        rolloverTask?.cancel()
        rolloverTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        requestBox.withLock {
            $0?.endAudio()
            $0 = nil
        }
    }

    private func removeTapIfNeeded() {
        guard isTapInstalled else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    // MARK: - Process Recognition Result

    /// Applies the newest transcript each segment has produced, then clears the
    /// way for the next drain. Anything that arrived while this was queued is
    /// already folded into `pendingTranscripts` - alignment re-runs over the
    /// whole transcript every time, so skipping intermediate states loses
    /// nothing and saves the main actor the work.
    private func drainPendingTranscripts() {
        isDrainScheduled.withLock { $0 = false }
        let pending = pendingTranscripts.withLock { current -> [Int: String] in
            let snapshot = current
            current = [:]
            return snapshot
        }
        guard !pending.isEmpty else { return }

        var changed = false
        for (segmentID, text) in pending {
            let slot = segmentID - segmentBaseID
            guard slot >= 0, slot < segmentTranscripts.count else { continue }
            guard segmentTranscripts[slot] != text else { continue }
            segmentTranscripts[slot] = text
            changed = true
        }
        guard changed else { return }
        processTranscript(joinedTranscript)
    }

    /// Every segment this session has produced, in order, as one transcript.
    private var joinedTranscript: String {
        Self.joinTranscripts(segmentTranscripts)
    }

    /// Pure and static so the re-arm contract can be pinned by tests: however
    /// the recognizer chose to cut the read into requests, the reader is scored
    /// against one continuous transcript.
    nonisolated static func joinTranscripts(_ segments: [String]) -> String {
        segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func processTranscript(_ transcript: String) {
        // Use formattedString split into words instead of segments.
        // Segments can split words mid-utterance in partial results (e.g. "quantum"
        // appears as segment "quant" then later corrects). formattedString gives the
        // recognizer's best word-boundary output, and re-evaluating on every callback
        // lets earlier partial mis-splits self-correct as more audio arrives.
        guard transcript != lastProcessedTranscript else { return }
        lastProcessedTranscript = transcript

        let spokenWords = transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        let computed = computeWordStates(from: spokenWords)

        // Already on the main actor. The nested `Task { @MainActor }` this
        // replaces only deferred the assignments by a turn, which split the
        // compute and the publish across two separate view updates.
        if wordStates != computed.states {
            wordStates = computed.states
        }
        if currentWordIndex != computed.refIndex {
            currentWordIndex = computed.refIndex
        }
        if matchedWordCount != computed.matched {
            matchedWordCount = computed.matched
        }
        if mismatchedWordCount != computed.mismatched {
            mismatchedWordCount = computed.mismatched
        }

        // Check if passage is complete
        if computed.refIndex >= referenceWords.count {
            stop()
        }
    }

    private func computeWordStates(from spokenWords: [String]) -> (states: [WordMatchState], refIndex: Int, matched: Int, mismatched: Int) {
        Self.computeAlignment(
            reference: referenceWords,
            normalizedReference: normalizedReference,
            spokenWords: spokenWords
        )
    }

    /// Pure alignment core, static and nonisolated so unit tests can pin its
    /// behavior directly (default isolation would otherwise fence it behind
    /// the main actor).
    ///
    /// Greedy left-to-right match. Handles the two ways real reading drifts
    /// from the page:
    /// - **Skipped words** (reader drops a word): a spoken word that matches a
    ///   nearby *reference* word marks everything between as `.skipped`.
    /// - **Inserted words** (filler, stumble): a spoken word matching nothing
    ///   is checked against what the *next* spoken word resolves to - if that
    ///   lands on the current or an upcoming reference word, the first word
    ///   was an insertion, not a miss. Single-word lookahead keeps skip vs
    ///   insert deterministic; deeper stumbles re-sync on the next partial
    ///   result anyway.
    nonisolated static func computeAlignment(
        reference: [String],
        normalizedReference: [String],
        spokenWords: [String]
    ) -> (states: [WordMatchState], refIndex: Int, matched: Int, mismatched: Int) {
        var newStates = Array(repeating: WordMatchState.upcoming, count: reference.count)
        var refIndex = 0
        var matched = 0
        var mismatched = 0

        func markSkipped(_ range: Range<Int>) {
            for j in range {
                newStates[j] = .skipped
                mismatched += 1
            }
        }

        var spokenIndex = 0
        while spokenIndex < spokenWords.count {
            guard refIndex < reference.count else { break }

            let spokenNorm = normalize(spokenWords[spokenIndex])
            let expectedNorm = normalizedReference[refIndex]

            if spokenNorm == expectedNorm {
                newStates[refIndex] = .matched
                matched += 1
                refIndex += 1
                spokenIndex += 1
                continue
            }

            // Skipped-reference path: this spoken word belongs further ahead
            // in the passage.
            let lookAhead = min(refIndex + 3, reference.count)
            var foundAhead = false

            if lookAhead > refIndex + 1 {
                for i in (refIndex + 1)..<lookAhead where spokenNorm == normalizedReference[i] {
                    markSkipped(refIndex..<i)
                    newStates[i] = .matched
                    matched += 1
                    refIndex = i + 1
                    foundAhead = true
                    break
                }
            }
            if foundAhead {
                spokenIndex += 1
                continue
            }

            // Insertion path: if the NEXT spoken word resolves at or near the
            // current position, this word was said in passing ("um") - drop it
            // without consuming a reference word or counting a miss.
            let nextIndex = spokenIndex + 1
            if nextIndex < spokenWords.count {
                let nextNorm = normalize(spokenWords[nextIndex])
                let nextResolvesHere = !nextNorm.isEmpty && nextNorm == expectedNorm
                let nextResolvesAhead = normalizedReference[(refIndex + 1)..<lookAhead]
                    .contains { $0 == nextNorm }
                if nextResolvesHere || nextResolvesAhead {
                    spokenIndex += 1
                    continue
                }
            }

            newStates[refIndex] = .mismatched(spoken: spokenWords[spokenIndex])
            mismatched += 1
            refIndex += 1
            spokenIndex += 1
        }

        if refIndex < newStates.count {
            newStates[refIndex] = .current
        }

        return (newStates, refIndex, matched, mismatched)
    }

    // MARK: - Scoring

    var accuracyPercentage: Double {
        let total = matchedWordCount + mismatchedWordCount
        guard total > 0 else { return 0 }
        return (Double(matchedWordCount) / Double(total)) * 100
    }

    var progressPercentage: Double {
        guard !referenceWords.isEmpty else { return 0 }
        return Double(currentWordIndex) / Double(referenceWords.count)
    }

    var isComplete: Bool {
        currentWordIndex >= referenceWords.count
    }

    // MARK: - Helpers

    /// Canonical form used for matching. Case, curly apostrophes, hyphens,
    /// and punctuation all fold away - and spelled numbers collapse to digits,
    /// because the page says "seventy-two" while the recognizer writes "72".
    nonisolated static func normalize(_ word: String) -> String {
        let lowered = word
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "'", with: "")

        let stripped = lowered
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Self.spelledNumberValue(stripped) ?? stripped
    }

    /// Parses tokens composed entirely of number words to their digit string.
    /// Handles both spaced ("one hundred") and fused ("onehundred",
    /// "seventytwo" - hyphens were stripped upstream) forms by greedily
    /// consuming the longest number-word prefix at each step. Returns nil for
    /// anything containing a non-number word - including plain digits, which
    /// are already canonical.
    private nonisolated static func spelledNumberValue(_ token: String) -> String? {
        guard !token.isEmpty, token.contains(where: \.isLetter) else { return nil }

        let lexicon: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9,
            "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
            "fourteen": 14, "fifteen": 15, "sixteen": 16,
            "seventeen": 17, "eighteen": 18, "nineteen": 19,
            "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
            "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
            "hundred": 0, "thousand": 0, "and": 0
        ]
        let scaleMarkers: Set<String> = ["hundred", "thousand"]
        let sortedWords = lexicon.keys.sorted { $0.count > $1.count }

        var parts: [String] = []
        var rest = Substring(token)
        while !rest.isEmpty {
            if rest.first == " " {
                rest = rest.dropFirst()
                continue
            }
            guard let match = sortedWords.first(where: { rest.hasPrefix($0) }) else {
                return nil
            }
            parts.append(match)
            rest = rest.dropFirst(match.count)
        }

        var total = 0
        var current = 0
        var sawNumberWord = false

        for part in parts where part != "and" {
            if let value = lexicon[part], !scaleMarkers.contains(part) {
                current += value
                sawNumberWord = true
            } else if part == "hundred" {
                current = max(current, 1) * 100
                sawNumberWord = true
            } else if part == "thousand" {
                total += max(current, 1) * 1000
                current = 0
                sawNumberWord = true
            }
        }

        guard sawNumberWord else { return nil }
        return String(total + current)
    }
}
