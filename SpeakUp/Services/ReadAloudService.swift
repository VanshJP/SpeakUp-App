import Foundation
import Speech
import AVFoundation
import UIKit
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

// MARK: - Pending Results

/// Recognition results for one request that have not reached the main actor
/// yet. Written on Apple's callback queue, so it cannot be isolated state.
private nonisolated struct PendingResults: Sendable {
    /// Results that ended an utterance, oldest first. Kept in order rather
    /// than coalesced: each one is the signal that tells a restart from a
    /// revision (see `RequestTranscript`), and there is one per pause.
    var closed: [HeardResult] = []
    /// The newest partial since the last of those. Latest-wins.
    var latest: HeardResult?
}

/// One transcript and when the recognizer delivered it. The time is taken in
/// the callback, because a coalesced partial can wait for the main actor and
/// the gap before it is how `RequestTranscript` spots a pause.
private nonisolated struct HeardResult: Sendable {
    let transcript: String
    let at: Date
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

    /// Why the mic stopped hearing the reader, once automatic recovery has
    /// given up - missing on-device assets, or a capture graph that will not
    /// restart. The read is held rather than ended (`isStalled`); if the
    /// reader finishes from there, the result screen shows this as a notice
    /// instead of letting a partial take stand as a confident verdict.
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

    /// One transcript per recognition request this session has opened, oldest
    /// first; the live one is last. Alignment runs over them joined, and that
    /// is what makes a re-arm invisible: SFSpeech starts every request's
    /// transcript at empty, so a single `String` would rewind the reader to
    /// word one every time the recognizer closed a request.
    ///
    /// Each entry also survives the recognizer starting over *inside* a
    /// request, which it does after a pause of a second or two on device. That
    /// was the read that "restarted from zero": the words before the pause
    /// were overwritten by the words after it, and alignment put the reader
    /// back near the top of the passage. See `RequestTranscript`.
    private var segments: [RequestTranscript] = [RequestTranscript()]
    private var activeSegment: Int { max(0, segments.count - 1) }

    /// Segment ids never restart, across every session this service runs.
    /// Cancelling a recognition task makes it fire one last error callback, and
    /// a Retry can open the next session before that lands; with per-session
    /// indices the dead task's transcript would be applied to the new passage.
    /// `segmentBaseID` is the id of `segments[0]`, so a stale id maps to a
    /// negative slot and is dropped.
    private var nextSegmentID = 0
    private var segmentBaseID = 0
    private var activeSegmentID: Int { segmentBaseID + activeSegment }

    /// Results waiting for the main actor, per segment id. Partials coalesce
    /// latest-wins, so a slow frame drops stale intermediate transcripts
    /// instead of queueing them, and a retired segment's final result can
    /// never be clobbered by the live segment's next partial. See
    /// `drainPendingTranscripts()`.
    private let pendingResults = OSAllocatedUnfairLock<[Int: PendingResults]>(initialState: [:])
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
    /// How long a due rollover may wait for the reader to pause between words.
    /// Still inside the ceiling at the far end.
    private static let rolloverQuietWait: TimeInterval = 10
    /// A gap this long since the transcript last changed reads as a pause.
    private static let quietGap: TimeInterval = 0.6
    private var rolloverTask: Task<Void, Never>?
    /// When the transcript last changed. The reader was mid-word then.
    private var lastHeardAt = Date.distantPast

    /// True between an interruption beginning and ending. Cancelling the
    /// recognition task to get out of a call's way makes it report an error,
    /// and without this the graph-is-dead recovery would answer that by trying
    /// to re-activate a session the call still owns - turning a survivable
    /// pause into a failed session.
    private var isInterrupted = false

    /// True while the app is in the background. There is no background audio
    /// mode, so the system takes the engine and recognition either way; the
    /// read is held and rebuilt when the app is active again, with every
    /// matched word intact. Auto-Lock used to do this in the middle of a
    /// passage - see `keepsScreenAwake`.
    private var isBackgrounded = false

    /// True while the reader has asked to hear the model line. Same teardown
    /// as an interruption and the same reason for a flag: the cancelled task
    /// reports an error that must not be answered with a rebuild, because the
    /// rebuild would re-open the mic straight into the synthesiser.
    private(set) var isPaused = false

    /// True when the mic stopped and automatic recovery gave up. The read is
    /// held - nothing matched is lost - until the reader resumes or finishes.
    /// This used to end the session, which is how a dropped mic became a read
    /// that had to start again from the first word.
    private(set) var isStalled = false

    /// One automatic retry per stall; reset once the recognizer is producing
    /// again, so a flaky route cannot loop.
    private var hasAutoResumed = false
    private var autoResumeTask: Task<Void, Never>?
    private static let autoResumeDelay: Duration = .milliseconds(1500)

    /// Recognition is down on purpose or by circumstance. Every recovery path
    /// checks this.
    private var isSuspended: Bool { isInterrupted || isBackgrounded || isPaused || isStalled }

    /// A call, Siri or the app leaving the foreground has the mic, not the
    /// reader. The session view says so instead of claiming to listen.
    var isHeldBySystem: Bool { isInterrupted || isBackgrounded }

    /// Time spent held, so the clock and words per minute measure reading
    /// rather than listening to the model or waiting out a call.
    private var heldSince: Date?
    private var heldTotal: TimeInterval = 0

    /// Tokens only - registered and removed on the main actor, and removed once
    /// more from `deinit`, which is nonisolated. Kept out of observation
    /// tracking so they never participate in change notifications.
    ///
    /// The configuration change names the engine that raised it, so it is
    /// registered per engine.
    @ObservationIgnored nonisolated(unsafe) private var engineObservers: [NSObjectProtocol] = []
    /// Interruptions and the app lifecycle, registered once per session. A
    /// rebuild replaces the engine but not the session, and a rebuild that
    /// fails into a stall must still hear the interruption end.
    @ObservationIgnored nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    deinit {
        for observer in engineObservers + lifecycleObservers {
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
        resetHoldClock()
    }

    private func resetTranscriptSegments() {
        segments = [RequestTranscript()]
        segmentBaseID = nextSegmentID
        nextSegmentID += 1
        unproductiveSegments = 0
        hasAutoResumed = false
        lastHeardAt = .distantPast
        pendingResults.withLock { $0 = [:] }
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
        resetHoldClock()
        recognitionFailureMessage = nil

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
        observeEngine(engine)
        observeLifecycle()
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
            segments.append(RequestTranscript())
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
            [weak self, pendingResults, isDrainScheduled] result, error in

            if let result {
                // `SFSpeechRecognitionResult` is not `Sendable`, so the values
                // are lifted out here rather than handing the object to a
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
                // The recognizer attaches metadata when it considers an
                // utterance over: on every final, and on some systems at each
                // pause, just before it starts the transcript again from
                // empty. That result is the one that must not be coalesced
                // away.
                let endsUtterance = result.speechRecognitionMetadata != nil
                let heard = HeardResult(transcript: transcript, at: Date())
                pendingResults.withLock { pending in
                    var entry = pending[segment] ?? PendingResults()
                    if endsUtterance {
                        entry.closed.append(heard)
                        entry.latest = nil
                    } else {
                        entry.latest = heard
                    }
                    pending[segment] = entry
                }
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
        // No engine while listening means a rebuild is waiting on the session.
        // It cancelled this request on purpose and arms a fresh one; answering
        // the cancellation would count it as a dead request.
        guard audioEngine != nil else { return }
        // A retired request delivering its own final is the expected shape of a
        // rollover, and a task cancelled by the previous session reports an
        // error long after its slots are gone; only the live request asks for
        // anything.
        guard segmentID == activeSegmentID else { return }

        // Apply whatever it finished with before retiring the slot.
        drainPendingTranscripts()
        guard isListening, !isSuspended, segmentID == activeSegmentID else { return }

        let produced = !segments[activeSegment].text.isEmpty
        let lifetime = Date().timeIntervalSince(segmentStartedAt)
        if produced || lifetime >= Self.unproductiveSegmentWindow {
            unproductiveSegments = 0
        } else {
            unproductiveSegments += 1
        }

        guard unproductiveSegments < Self.maxUnproductiveSegments else {
            stall(with: failure ?? ReadAloudError
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
            stall(with: failure ?? ReadAloudError.speechNotAvailable.errorDescription)
            return
        }
    }

    /// Rolls the live request over before it reaches its ceiling. Unlike
    /// `handleSegmentEnd` this runs while the request is still healthy, so the
    /// retired one is flushed and keeps producing into its own slot.
    ///
    /// It waits for a gap between words when it can. A request cut mid-word
    /// hands each half of that word to a different request, neither of which
    /// recognizes it, and the reader sees a word they said marked wrong.
    private func scheduleRollover() {
        rolloverTask?.cancel()
        rolloverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.segmentRolloverInterval))
            let deadline = Date().addingTimeInterval(Self.rolloverQuietWait)
            while !Task.isCancelled, Date() < deadline, self?.isMidWord == true {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            self?.rollOverSegment()
        }
    }

    /// The transcript changed moments ago, so the reader is probably mid-word.
    private var isMidWord: Bool {
        Date().timeIntervalSince(lastHeardAt) < Self.quietGap
    }

    private func rollOverSegment() {
        guard isListening, !isSuspended, let engine = audioEngine, engine.isRunning else { return }
        // Housekeeping on a healthy request. If the recognizer cannot take a
        // new one right now, keep reading on this one; `handleSegmentEnd`
        // deals with the ceiling if it comes to that. This used to end the
        // whole session.
        if !armRecognition(startNewSegment: true) {
            logger.info("Read Aloud rollover deferred: recognizer unavailable")
        }
    }

    /// A configuration change - AirPods connect, a headset is unplugged,
    /// another app reshapes the shared session. AVAudioEngine stops itself and
    /// the tap's format goes stale. Nothing throws; the mic simply goes quiet
    /// for the rest of the read unless the graph is rebuilt.
    private func observeEngine(_ engine: AVAudioEngine) {
        removeEngineObservers()
        let configuration = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildCaptureGraph(reason: "configuration change")
            }
        }
        engineObservers = [configuration]
    }

    private func removeEngineObservers() {
        for observer in engineObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        engineObservers = []
    }

    /// The other ways a read loses the mic without anyone asking it to.
    ///
    /// **Interruption** - a call, Siri, an alarm. The session is deactivated
    /// under us and has to be re-activated before the engine will start again.
    ///
    /// **Leaving the app** holds the read; coming back rebuilds it. "Coming
    /// back" is `didBecomeActive` rather than the foreground notification
    /// because it also follows Siri and a declined call, which never leave
    /// the foreground - and an interruption's `.ended` is not guaranteed to
    /// arrive at all. If another app still has the mic, the rebuild fails into
    /// a stall the reader can resume from, never into a lost read.
    private func observeLifecycle() {
        removeLifecycleObservers()
        let center = NotificationCenter.default

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

        let background = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleBackgrounding()
            }
        }

        let active = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleBecameActive()
            }
        }

        lifecycleObservers = [interruption, background, active]
    }

    private func removeLifecycleObservers() {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers = []
    }

    private func handleBackgrounding() {
        guard isListening, !isBackgrounded else { return }
        isBackgrounded = true
        holdCapture()
    }

    private func handleBecameActive() {
        guard isListening, isBackgrounded || isInterrupted else { return }
        isBackgrounded = false
        isInterrupted = false
        resumeCapture(reason: "app became active")
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
            holdCapture()
        case .ended:
            // `didBecomeActive` may have rebuilt already - Siri and a declined
            // call end that way - and rebuilding a working graph a second time
            // would cut off whatever the reader is saying.
            guard isInterrupted || isStalled else { return }
            // Otherwise rebuild regardless of what the options say.
            // `.shouldResume` is advice about resuming *playback*; a reader who
            // has just put the phone down wants the mic back either way, and a
            // session that is still taken fails into a stall they can resume
            // from.
            isInterrupted = false
            resumeCapture(reason: "interruption ended")
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
    /// the reader - and the same rebuild on the way back, with `segments`
    /// untouched.
    func pauseForModelPlayback() {
        guard isListening, !isSuspended else { return }
        isPaused = true
        holdCapture()
    }

    func resumeAfterModelPlayback() {
        guard isListening, isPaused else { return }
        isPaused = false
        syncHoldClock()
        rebuildCaptureGraph(reason: "model line finished")
    }

    /// The reader asked for the mic back after it stalled.
    func resumeListening() {
        guard isListening, isStalled else { return }
        resumeCapture(reason: "resumed by reader")
    }

    /// Takes recognition and the engine down without ending the read. Every
    /// hold comes through here and every way back goes through
    /// `rebuildCaptureGraph`, so neither side touches a matched word.
    private func holdCapture() {
        syncHoldClock()
        teardownRecognition()
        audioEngine?.stop()
    }

    /// Clears a stall and rebuilds - the reader's Resume, an interruption
    /// ending, and the app becoming active all come through here. Another hold
    /// that is still in force (the model line, a call) keeps the rebuild
    /// waiting for that hold to end.
    private func resumeCapture(reason: String) {
        autoResumeTask?.cancel()
        autoResumeTask = nil
        if isStalled {
            isStalled = false
            recognitionFailureMessage = nil
            unproductiveSegments = 0
        }
        syncHoldClock()
        rebuildCaptureGraph(reason: reason)
    }

    /// Rebuilds the capture graph in place and re-arms recognition on it,
    /// keeping `segments` - and therefore the reader's place in the passage -
    /// intact.
    ///
    /// An interruption leaves the session deactivated, and the engine will not
    /// start again until it is back. Re-activating it happens off the main
    /// actor: `setActive` blocks until the audio server answers, and this runs
    /// exactly when the reader starts speaking again - after the model line, a
    /// call, Resume. Same stall `AudioService.configureRecordingSession` moved
    /// off the main thread. The engine is built once the session is up.
    private func rebuildCaptureGraph(reason: String) {
        guard isListening, !isSuspended else { return }
        logger.info("Read Aloud rebuilding capture graph: \(reason, privacy: .public)")

        teardownRecognition()
        // Stop the engine *before* removing the tap (gotcha §9).
        audioEngine?.stop()
        removeTapIfNeeded()
        removeEngineObservers()
        audioEngine = nil

        Task { [weak self] in
            try? await Task.detached(priority: .userInitiated) {
                try AVAudioSession.sharedInstance().setActive(true)
            }.value
            self?.startCaptureGraph()
        }
    }

    /// Second half of `rebuildCaptureGraph`, once the session is active.
    ///
    /// Anything may have happened while it came up. A hold - the model line
    /// again, a call, the app leaving - owns the mic now and its own way back
    /// rebuilds; Done ended the read; and when two rebuilds overlap, the first
    /// to land builds the engine and the other must not replace it.
    private func startCaptureGraph() {
        guard isListening, !isSuspended, audioEngine == nil else { return }

        let engine = AVAudioEngine()
        do {
            try installTap(on: engine)
            audioEngine = engine
            engine.prepare()
            try engine.start()
        } catch {
            logger.error("Read Aloud engine restart failed: \(error.localizedDescription, privacy: .public)")
            stall(with: "The microphone stopped responding. It may be in use by another app.")
            return
        }

        observeEngine(engine)
        guard armRecognition(startNewSegment: true) else {
            stall(with: ReadAloudError.speechNotAvailable.errorDescription)
            return
        }
    }

    /// Holds the read once automatic recovery has failed, keeping every matched
    /// word. One more automatic attempt follows shortly - most failures here
    /// are a route change settling or another app letting go of the session -
    /// and after that the reader decides: Resume, or Done to score what they
    /// read.
    private func stall(with message: String?) {
        guard isListening else { return }
        logger.error("Read Aloud stalled: \(message ?? "no reason given", privacy: .public)")
        recognitionFailureMessage = message
            ?? ReadAloudError.recognitionFailed("Speech recognition stopped.").errorDescription
        isStalled = true
        holdCapture()

        guard !hasAutoResumed, autoResumeTask == nil else { return }
        hasAutoResumed = true
        autoResumeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoResumeDelay)
            guard !Task.isCancelled, let self else { return }
            self.autoResumeTask = nil
            guard self.isListening, self.isStalled else { return }
            self.resumeCapture(reason: "automatic retry")
        }
    }

    // MARK: - Held time

    /// Seconds this read has spent held - hearing the model, through a call,
    /// in the background, or stalled - up to `date`.
    func heldDuration(until date: Date = Date()) -> TimeInterval {
        heldTotal + (heldSince.map { date.timeIntervalSince($0) } ?? 0)
    }

    /// Opens or closes the held interval to match `isSuspended`. Called after
    /// every change to a hold flag.
    private func syncHoldClock() {
        if isSuspended, heldSince == nil {
            heldSince = Date()
        } else if !isSuspended, let since = heldSince {
            heldTotal += Date().timeIntervalSince(since)
            heldSince = nil
        }
    }

    private func resetHoldClock() {
        heldSince = nil
        heldTotal = 0
    }

    // MARK: - Stop

    func stop() {
        // Credit what the recognizer has already heard: a reader who taps Done
        // straight after the last word should get that word.
        if isListening {
            drainPendingTranscripts()
        }
        // `stopInternal` flushes the live request through `teardownRecognition`
        // - `endAudio()` must not be called twice on one request.
        stopInternal()
    }

    private func stopInternal() {
        // First, so a cancel-induced error callback cannot re-arm recognition
        // on the way down.
        isListening = false
        isInterrupted = false
        isBackgrounded = false
        isPaused = false
        isStalled = false
        autoResumeTask?.cancel()
        autoResumeTask = nil
        syncHoldClock()

        removeEngineObservers()
        removeLifecycleObservers()
        teardownRecognition()

        // Stop before removing the tap: mutating the tap on a running engine
        // reconfigures the live AURemoteIO underneath its IO thread (gotcha §9).
        audioEngine?.stop()
        removeTapIfNeeded()
        audioEngine = nil

        pendingResults.withLock { $0 = [:] }
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

    /// Applies every result each segment has produced since the last drain,
    /// then clears the way for the next one. Alignment re-runs over the whole
    /// transcript every time, so skipping intermediate partials loses nothing
    /// and saves the main actor the work.
    private func drainPendingTranscripts() {
        isDrainScheduled.withLock { $0 = false }
        let pending = pendingResults.withLock { current -> [Int: PendingResults] in
            let snapshot = current
            current = [:]
            return snapshot
        }
        guard !pending.isEmpty else { return }

        var changed = false
        for segmentID in pending.keys.sorted() {
            let slot = segmentID - segmentBaseID
            guard slot >= 0, slot < segments.count, let results = pending[segmentID] else { continue }
            let before = segments[slot]
            for closed in results.closed {
                segments[slot].apply(closed.transcript, utteranceEnded: true, at: closed.at)
            }
            if let latest = results.latest {
                segments[slot].apply(latest.transcript, utteranceEnded: false, at: latest.at)
            }
            if segments[slot] != before {
                changed = true
            }
        }
        guard changed else { return }

        lastHeardAt = Date()
        // Recognition is producing, so the next stall earns its own retry.
        hasAutoResumed = false
        processTranscript(joinedTranscript)
    }

    /// Every segment this session has produced, in order, as one transcript.
    private var joinedTranscript: String {
        Self.joinTranscripts(segments.map(\.text))
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
    /// Greedy left-to-right match. Handles the three ways real reading drifts
    /// from the page:
    /// - **Skipped words** (reader drops a word): a spoken word that matches a
    ///   nearby *reference* word marks everything between as `.skipped`.
    /// - **Inserted words** (filler, stumble): a spoken word matching nothing
    ///   is checked against what the *next* spoken word resolves to - if that
    ///   lands on the current or an upcoming reference word, the first word
    ///   was an insertion, not a miss. Single-word lookahead keeps skip vs
    ///   insert deterministic; deeper stumbles re-sync on the next partial
    ///   result anyway.
    /// - **Words said wrong** ("free" for "three"): see `isSlip`. Checked
    ///   before either of the above, which would otherwise explain the slip
    ///   away as a skip or a filler.
    /// - **Words replaced** ("lady" for "lorry", then back on the page): see
    ///   `isReplacement`. Also checked first, for the same reason.
    /// - **Names the recognizer preferred** ("Laurie" for "lorry"): matched.
    ///   See `ConsonantAnalyzer.isNameSpelling`.
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

        // Each word is compared as the current word and again as the next
        // one, so normalize once.
        let spokenNorms = spokenWords.map { normalize($0) }
        let passageWords = Set(normalizedReference)
        var spokenIndex = 0
        while spokenIndex < spokenWords.count {
            guard refIndex < reference.count else { break }

            let spokenNorm = spokenNorms[spokenIndex]
            let expectedNorm = normalizedReference[refIndex]

            if spokenNorm == expectedNorm
                || isNameSpelling(
                    spokenWords[spokenIndex],
                    normalized: spokenNorm,
                    of: reference[refIndex],
                    passage: passageWords
                ) {
                newStates[refIndex] = .matched
                matched += 1
                refIndex += 1
                spokenIndex += 1
                continue
            }

            let lookAhead = min(refIndex + 3, reference.count)
            let nextIndex = spokenIndex + 1
            let nextNorm = nextIndex < spokenNorms.count ? spokenNorms[nextIndex] : nil
            let matchAhead = ((refIndex + 1)..<lookAhead).first { normalizedReference[$0] == spokenNorm }

            // "tin" for "Thin." in "Thin. Tin." is this word said wrong, but
            // it also matches the "Tin." ahead. When the next word lands after
            // that match too, the skip explains both words just as well.
            let skipFitsNextWord = matchAhead.map {
                $0 + 1 < reference.count && nextNorm == normalizedReference[$0 + 1]
            } ?? false
            let saidWrong = !skipFitsNextWord && (
                isSlip(
                    spokenWords[spokenIndex],
                    at: refIndex,
                    next: nextNorm,
                    reference: reference,
                    normalizedReference: normalizedReference
                )
                || (matchAhead == nil && isReplacement(
                    spokenNorm,
                    at: refIndex,
                    next: nextNorm,
                    normalizedReference: normalizedReference
                ))
            )

            // Skipped-reference path: this spoken word belongs further ahead
            // in the passage.
            if let matchAhead, !saidWrong {
                markSkipped(refIndex..<matchAhead)
                newStates[matchAhead] = .matched
                matched += 1
                refIndex = matchAhead + 1
                spokenIndex += 1
                continue
            }

            // Insertion path: if the NEXT spoken word resolves at or near the
            // current position, this word was said in passing ("um") - drop it
            // without consuming a reference word or counting a miss.
            if !saidWrong, let nextNorm {
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

    /// Whether `spoken` is the reference word at `index` said wrong - "free"
    /// for "three", "tin" for "thin" - rather than a filler before it or a
    /// word further ahead: it is a near miss of that word, and the next
    /// spoken word lands on the word after it.
    ///
    /// Without this, a slip followed by a clean word read as a filler plus a
    /// skip, or in a minimal pair as a skip to the look-alike ahead, and the
    /// result could only call the word skipped. What was heard, the part
    /// worth practising, was thrown away. The score is the same either way:
    /// a skip and a mismatch are both a miss.
    ///
    /// - Parameters:
    ///   - spoken: The spoken word as heard.
    ///   - next: The next spoken word, normalized.
    nonisolated static func isSlip(
        _ spoken: String,
        at index: Int,
        next: String?,
        reference: [String],
        normalizedReference: [String]
    ) -> Bool {
        guard let next, index + 1 < normalizedReference.count,
              next == normalizedReference[index + 1]
        else { return false }
        // Compared as spelled: "three" normalizes to "3".
        return isNearMiss(spelling(of: spoken), of: spelling(of: reference[index]))
    }

    /// Whether `spoken` stood in for the reference word at `index`: it matches
    /// nothing nearby, it is not a hesitation, and the next spoken word lands
    /// on the word after this one. The reader said something else here and
    /// carried on.
    ///
    /// This used to count as a filler plus a skip whenever the two words were
    /// not spelled alike. That threw away what was heard, so the word review
    /// said "skipped" for a word the reader plainly said, and **Sounds to
    /// check** - which only reads words with something heard in their place -
    /// saw a slip on some misses and not on others. A skip and a mismatch are
    /// both a miss, so accuracy is unchanged. Hesitations still read as
    /// fillers: "um" where a word should be is a skip.
    nonisolated static func isReplacement(
        _ spokenNorm: String,
        at index: Int,
        next: String?,
        normalizedReference: [String]
    ) -> Bool {
        guard !spokenNorm.isEmpty, let next, index + 1 < normalizedReference.count,
              next == normalizedReference[index + 1]
        else { return false }
        return !FillerWordList.unconditionalFillers.contains(spokenNorm)
            && !FillerWordList.contextDependentFillers.contains(spokenNorm)
    }

    /// `ConsonantAnalyzer.isNameSpelling`, unless what was heard is itself a
    /// word on the page - a pair passage must never forgive its own pair.
    /// Alignment re-runs on every partial result, so the cheap checks go
    /// first and the spoken word arrives already normalized.
    nonisolated static func isNameSpelling(
        _ spoken: String,
        normalized: String,
        of expected: String,
        passage: Set<String>
    ) -> Bool {
        guard spoken.first?.isUppercase == true, !passage.contains(normalized) else { return false }
        return ConsonantAnalyzer.isNameSpelling(spoken, of: expected)
    }

    /// Close enough in spelling to be the same word said wrong: one edit for
    /// a word of up to three letters, up to half the longer word's letters
    /// past that. "three" and "free" are two edits apart; "um" and "the" are
    /// three.
    nonisolated static func isNearMiss(_ spoken: String, of expected: String) -> Bool {
        guard !spoken.isEmpty, !expected.isEmpty, spoken != expected else { return false }
        let spokenLetters = Array(spoken)
        let expectedLetters = Array(expected)
        let limit = max(1, max(spokenLetters.count, expectedLetters.count) / 2)
        guard abs(spokenLetters.count - expectedLetters.count) <= limit else { return false }

        var previous = Array(0...expectedLetters.count)
        var current = previous
        for (row, spokenLetter) in spokenLetters.enumerated() {
            current[0] = row + 1
            for (column, expectedLetter) in expectedLetters.enumerated() {
                current[column + 1] = min(
                    previous[column + 1] + 1,
                    current[column] + 1,
                    previous[column] + (spokenLetter == expectedLetter ? 0 : 1)
                )
            }
            swap(&previous, &current)
        }
        return previous[expectedLetters.count] <= limit
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
        let stripped = spelling(of: word)
        return Self.spelledNumberValue(stripped) ?? stripped
    }

    /// `normalize` without turning number words into digits: the word as
    /// spelled, lowercased, with apostrophes, hyphens and edge punctuation
    /// gone. What a near miss is measured on - "free" is one sound from
    /// "three", and nothing like "3".
    nonisolated static func spelling(of word: String) -> String {
        word
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
