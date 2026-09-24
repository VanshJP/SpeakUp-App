import Foundation
import os.log
import Speech
import AVFoundation
import os

@Observable
class LiveTranscriptionService {
    private let logger = Logger.app("LiveTranscription")
    var liveFillerCount = 0
    var liveWordCount = 0
    var isActive = false
    var fillerConfig: FillerWordConfig = .default

    /// Monotonic per-word filler counts for the running session. Feeds the
    /// repeated-filler coaching cue ("that's 5× 'like'") without re-deriving
    /// counts in the view layer. Reset with the other live counters on start.
    var liveFillerWordCounts: [String: Int] = [:]

    /// Timestamp (relative to recognition start) when the last spoken word ended.
    /// Used to detect sentence boundaries for graceful recording stop.
    var lastSegmentEndTime: TimeInterval = 0

    private var audioEngine: AVAudioEngine?
    /// Made on first use, not in `init`. `RecordingView` holds its view model
    /// in `@State`, whose initial value is rebuilt and thrown away every time
    /// the view is re-created - and `ContentView` re-creates it whenever the
    /// analysis job writes settings. Building a recognizer is a round trip to
    /// the speech daemon, so each throwaway cost one on the main thread.
    @ObservationIgnored private var cachedRecognizer: SFSpeechRecognizer?
    private var recognizer: SFSpeechRecognizer? {
        if let cachedRecognizer { return cachedRecognizer }
        cachedRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        return cachedRecognizer
    }
    /// Read from the realtime audio thread by the tap block and swapped on the
    /// main actor at every recognition restart, so it cannot be plain isolated
    /// state. The critical section is one `append`.
    private let requestBox = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(uncheckedState: nil)
    private var recognitionTask: SFSpeechRecognitionTask?
    /// How many of the live utterance's segments have been tagged for fillers.
    private var lastProcessedSegmentCount = 0

    /// Words and fillers from utterances the recognizer has finished with -
    /// earlier requests, and earlier utterances inside the live one.
    ///
    /// The headline counts used to be `max(count, this request's count)`,
    /// which is only right if one request heard the whole take. It never does:
    /// SFSpeech closes a request after a pause, and on device it can also
    /// start a request's transcript over from empty after one. Every word and
    /// filler after the first pause went uncounted until the new stretch
    /// outgrew the old - pace drills scored slow, and Filler Elimination
    /// could call a run with fillers in it clean.
    private var committedWordCount = 0
    private var committedFillerCount = 0
    /// The utterance the recognizer is still revising, in the comparison form
    /// `RecognitionContinuity` reads, and whether it has been marked finished.
    private var utteranceWords: [String] = []
    private var utteranceIsClosed = false
    /// Monotonic within the live utterance, like the counts used to be within
    /// a request: a partial that revises a filler away must not flicker the
    /// display back down.
    private var utteranceWordCount = 0
    private var utteranceFillerCount = 0
    /// When the result that last changed the live utterance arrived. A long
    /// gap before the next partial marks a pause.
    private var utteranceHeardAt: Date?
    /// What the live request has committed so far - its earlier utterances -
    /// so a final that restates the whole request replaces them instead of
    /// being counted on top of them.
    private var requestWords: [String] = []
    private var requestWordCount = 0
    private var requestFillerCount = 0
    /// Cumulative offset so `lastSegmentEndTime` stays monotonic across
    /// recognition restarts (SFSpeech resets timestamps per request).
    private var segmentTimeOffset: TimeInterval = 0
    /// Bumped on every restart/stop so cancelled-task error callbacks cannot
    /// re-enter `restartRecognitionPreservingEngine` in a tight loop.
    private var recognitionGeneration = 0
    /// `removeTap` crashes if no tap is installed - track it explicitly.
    private var isTapInstalled = false
    /// Token only - touched from `deinit` (nonisolated) and init. Kept out of
    /// observation tracking so the token never participates in change
    /// notifications, and unsafe because NSObjectProtocol tokens are not
    /// Sendable but are only ever registered/removed from the main actor.
    @ObservationIgnored nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    /// Same rules as `interruptionObserver`, but re-registered per engine: the
    /// notification is only useful when it names the engine that raised it.
    @ObservationIgnored nonisolated(unsafe) private var configurationObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let info = notification.userInfo,
                let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                type == .began
            else { return }
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    /// Request speech recognition authorization (must be called before start).
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Start live transcription using its own audio engine tap.
    /// Call this AFTER the AVAudioRecorder has started so the session is active.
    ///
    /// Wire input + tap *before* `engine.start()`. Starting an empty graph
    /// while AVAudioRecorder already owns the mic (common on "Start Now"
    /// during countdown) makes `AVAudioEngineGraph::Initialize` raise an
    /// NSException that Swift `do/catch` cannot catch - abort.
    @MainActor
    func start() {
        guard let recognizer, recognizer.isAvailable else { return }

        // Idempotent: a rapid double-tap on the record button, or a re-entry
        // from the view-model before the previous session has fully torn
        // down, would otherwise install a second tap on a new engine while
        // the old tap is still delivering buffers into a nilled request,
        // crashing AudioToolbox on the next buffer. Also clears an engine
        // left running after a failed mid-session recognition re-arm.
        if isActive || audioEngine != nil { stopInternal() }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        liveFillerCount = 0
        liveWordCount = 0
        liveFillerWordCounts = [:]
        lastSegmentEndTime = 0
        segmentTimeOffset = 0
        committedWordCount = 0
        committedFillerCount = 0
        resetUtterance()
        isActive = true

        // Touch inputNode so the graph negotiates a hardware format before
        // we start. A 0 Hz format → Initialize exception / silent m4a.
        let session = AVAudioSession.sharedInstance()
        try? session.setPreferredSampleRate(session.sampleRate > 0 ? session.sampleRate : 44_100)
        let inputNode = engine.inputNode
        var format = inputNode.inputFormat(forBus: 0)
        if format.sampleRate <= 0 {
            format = inputNode.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            logger.error("LiveTranscription: invalid input format \(String(describing: format), privacy: .public), skipping live fillers")
            stopInternal()
            return
        }

        guard attachRecognition(on: engine) else {
            stopInternal()
            return
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            logger.error("LiveTranscription: audio engine failed to start: \(error.localizedDescription, privacy: .private(mask: .hash))")
            stopInternal()
            return
        }

        observeConfigurationChange(on: engine)
    }

    /// AirPods connecting, a headset unplugged, another app reshaping the
    /// shared session: AVAudioEngine stops itself and the tap's format goes
    /// stale. Nothing throws, so without this the live filler count simply
    /// froze for the rest of the take while the recorder kept writing.
    @MainActor
    private func observeConfigurationChange(on engine: AVAudioEngine) {
        removeConfigurationObserver()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildEnginePreservingCounts()
            }
        }
    }

    @MainActor
    private func removeConfigurationObserver() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
    }

    /// Rebuilds the capture graph without touching the live counters, so a
    /// route change costs the take a moment of recognition rather than the
    /// rest of it. `AudioService` re-asserts the session itself on the same
    /// route change; this only owns the engine that feeds the recognizer.
    @MainActor
    private func rebuildEnginePreservingCounts() {
        guard isActive else { return }
        logger.info("LiveTranscription: rebuilding capture graph after configuration change")

        recognitionGeneration += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        requestBox.withLock {
            $0?.endAudio()
            $0 = nil
        }

        // Stop before removing the tap (gotcha §9).
        audioEngine?.stop()
        removeTapIfNeeded()
        removeConfigurationObserver()
        audioEngine = nil

        let engine = AVAudioEngine()
        audioEngine = engine
        segmentTimeOffset = max(segmentTimeOffset, lastSegmentEndTime)

        guard attachRecognition(on: engine) else {
            stopInternal()
            return
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            logger.error("LiveTranscription: engine failed to restart after configuration change: \(error.localizedDescription, privacy: .private(mask: .hash))")
            stopInternal()
            return
        }

        observeConfigurationChange(on: engine)
    }

    @MainActor
    func stop() {
        requestBox.withLock { $0?.endAudio() }
        stopInternal()
    }

    @MainActor
    private func stopInternal() {
        // Idempotent across explicit stop() + cancelled-task callbacks.
        // Cleanup runs whenever an engine or request is still held - including
        // the orphaned-engine case after a failed recognition re-arm.
        let hasWork = isActive || audioEngine != nil || requestBox.withLock({ $0 != nil })
        guard hasWork else { return }

        isActive = false
        recognitionGeneration += 1
        removeConfigurationObserver()

        // Stop first: mutating the tap on a running engine reconfigures the
        // live AURemoteIO underneath its IO thread.
        audioEngine?.stop()
        removeTapIfNeeded()
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        requestBox.withLock { $0 = nil }
    }

    @MainActor
    private func removeTapIfNeeded() {
        guard isTapInstalled, let engine = audioEngine else {
            isTapInstalled = false
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    /// Installs a tap + recognition task on an already-running engine.
    /// Returns false when the input format is unusable.
    @MainActor
    @discardableResult
    private func attachRecognition(on engine: AVAudioEngine) -> Bool {
        guard let recognizer, recognizer.isAvailable else { return false }

        let inputNode = engine.inputNode
        // Prefer inputFormat - outputFormat can report 0 Hz before the graph
        // is fully wired even after engine.start().
        var format = inputNode.inputFormat(forBus: 0)
        if format.sampleRate <= 0 {
            format = inputNode.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            logger.error("LiveTranscription: invalid input format \(String(describing: format), privacy: .public), skipping tap")
            return false
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Unconditional: on-device processing is a product guarantee, not a
        // preference, and `supportsOnDeviceRecognition` can read false while
        // assets are still installing - which used to hand that session's
        // microphone audio to Apple's servers. It also keeps latency low and
        // avoids network pauses that force early isFinal → restart cycles.
        request.requiresOnDeviceRecognition = true
        requestBox.withLock { $0 = request }
        // A new request starts its transcript empty. Whatever the last one
        // heard is finished; bank it rather than let the next result replace it.
        commitUtterance()
        requestWords = []
        requestWordCount = 0
        requestFillerCount = 0
        recognitionGeneration += 1
        let generation = recognitionGeneration

        // The tap outlives individual recognition requests. Installing one on a
        // running engine makes AVAudioEngine reset the input node's format,
        // which reconfigures AURemoteIO's converter while its IO thread is
        // inside the input callback - that raced into a null callback pointer
        // and segfaulted about a minute into every session, at the first
        // recognition restart. Install once, before `engine.start()`, and swap
        // the request underneath it.
        if !isTapInstalled {
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [requestBox] buffer, _ in
                requestBox.withLock { $0?.append(buffer) }
            }
            isTapInstalled = true
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Hop onto the main actor before touching any state so teardown
            // and partial-result writes never race the 10 Hz recording timer
            // that reads `isActive` / `lastSegmentEndTime`.
            let hadError = error != nil
            let isFinal = result?.isFinal ?? false
            // Stamped here rather than on the main actor, which can hold a
            // callback back and hide the pause in front of it.
            let heardAt = Date()
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Ignore callbacks from cancelled generations (restart/stop).
                guard self.isActive, self.recognitionGeneration == generation else { return }
                if let result { self.processPartialResult(result, heardAt: heardAt) }

                // SFSpeech auto-finalizes after a pause. Previously we tore
                // down AVAudioEngine here, which yanked the shared input graph
                // out from under AVAudioRecorder mid-take and left the rest of
                // the m4a silent - Whisper then scored the session as Silent.
                // Keep the engine running and open a fresh recognition request.
                if hadError || isFinal {
                    self.restartRecognitionPreservingEngine()
                }
            }
        }
        return true
    }

    /// Re-arms speech recognition without stopping AVAudioEngine, so the
    /// concurrent AVAudioRecorder keeps a stable mic route.
    @MainActor
    private func restartRecognitionPreservingEngine() {
        guard isActive, let engine = audioEngine else {
            stopInternal()
            return
        }
        // A configuration change stops the engine without telling the request.
        // Re-arming onto it would hand the recognizer a tap that never fires.
        guard engine.isRunning else {
            rebuildEnginePreservingCounts()
            return
        }

        // Carry forward the furthest end time so sentence-boundary detection
        // still works across request boundaries.
        segmentTimeOffset = max(segmentTimeOffset, lastSegmentEndTime)

        // Invalidate in-flight callbacks before cancelling so the cancel error
        // cannot recurse into another restart.
        recognitionGeneration += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        requestBox.withLock {
            $0?.endAudio()
            $0 = nil
        }

        guard attachRecognition(on: engine) else {
            // Leave the audio graph alone for AVAudioRecorder - only drop
            // live-transcription state so metering / capture keep working.
            isActive = false
            recognitionTask = nil
            requestBox.withLock { $0 = nil }
            return
        }
    }

    @MainActor
    private func processPartialResult(_ result: SFSpeechRecognitionResult, heardAt: Date) {
        let segments = result.bestTranscription.segments
        let heard = RecognitionContinuity.words(in: segments.map(\.substring).joined(separator: " "))
        let endsUtterance = result.speechRecognitionMetadata != nil
        let afterPause = !endsUtterance
            && (utteranceHeardAt.map { heardAt.timeIntervalSince($0) >= RecognitionContinuity.restartGap } ?? false)

        // Same rules as Read Aloud: a result that starts over after a pause is
        // a new utterance, not a revision of the old one, and a blank or
        // shrunken final is not allowed to take anything back.
        switch RecognitionContinuity.classify(
            previous: utteranceWords,
            next: heard,
            previousClosed: utteranceIsClosed,
            afterPause: afterPause,
            committed: requestWords
        ) {
        case .ignore:
            utteranceIsClosed = utteranceIsClosed || endsUtterance
            return
        case .restart:
            commitUtterance()
            utteranceIsClosed = endsUtterance
        case .wholeRequest:
            absorbRequestIntoUtterance()
            utteranceIsClosed = endsUtterance
        case .revision:
            let grew = heard.count > utteranceWords.count
            utteranceIsClosed = endsUtterance || (utteranceIsClosed && !grew)
        }
        utteranceWords = heard
        utteranceHeardAt = heardAt

        let wordCount = segments.count
        guard wordCount > 0 else {
            // Preserve the counter through transient empty partials - the
            // recognizer occasionally emits zero-segment revisions between
            // utterances and we don't want the UI to flash back to 0.
            return
        }

        // Skip reprocessing when the recognizer revises existing segments
        // without adding new words; a shrinking partial must not rewind the
        // watermark either. Post-recording analysis handles precision.
        guard wordCount > lastProcessedSegmentCount else { return }
        let processedCount = lastProcessedSegmentCount
        lastProcessedSegmentCount = wordCount

        let words = segments.map { $0.substring }
        let timestamps = segments.map { $0.timestamp }
        let durations = segments.map { $0.duration }

        let fillerCount = FillerDetectionPipeline.countFillers(
            words: words,
            timestamps: timestamps,
            durations: durations,
            config: fillerConfig
        )

        let endTime = segments.last.map { $0.timestamp + $0.duration } ?? 0

        // Monotonic within an utterance: partial revisions routinely
        // reinterpret a word that was tagged as a filler into a non-filler (or
        // vice versa) once more context arrives, and letting the display
        // regress mid-utterance produces a flicker. Across utterances the
        // counts add, because each one heard different audio. Post-recording
        // analysis computes the authoritative count.
        utteranceFillerCount = max(utteranceFillerCount, fillerCount)
        utteranceWordCount = max(utteranceWordCount, wordCount)
        liveFillerCount = committedFillerCount + utteranceFillerCount
        liveWordCount = committedWordCount + utteranceWordCount
        lastSegmentEndTime = max(lastSegmentEndTime, segmentTimeOffset + endTime)

        // Tag only the segments this revision added. Re-running the tagger
        // over the whole transcript on every ~1 Hz partial made long sessions
        // quadratic on the main actor; seen segments are final for live display.
        updateFillerWordCounts(
            words: Array(words[processedCount...]),
            timestamps: Array(timestamps[processedCount...]),
            durations: Array(durations[processedCount...])
        )
    }

    /// Banks the live utterance's counts and starts the next one from zero.
    @MainActor
    private func commitUtterance() {
        committedWordCount += utteranceWordCount
        committedFillerCount += utteranceFillerCount
        requestWords += utteranceWords
        requestWordCount += utteranceWordCount
        requestFillerCount += utteranceFillerCount
        resetUtterance()
    }

    /// The recognizer restated the whole request in one result. Move what the
    /// request had committed back into the live utterance, so the restated
    /// words count once and the session total does not move, and mark their
    /// segments as already tagged for the per-word filler tallies.
    @MainActor
    private func absorbRequestIntoUtterance() {
        committedWordCount -= requestWordCount
        committedFillerCount -= requestFillerCount
        utteranceWordCount += requestWordCount
        utteranceFillerCount += requestFillerCount
        lastProcessedSegmentCount += requestWordCount
        requestWords = []
        requestWordCount = 0
        requestFillerCount = 0
    }

    @MainActor
    private func resetUtterance() {
        utteranceWords = []
        utteranceIsClosed = false
        utteranceWordCount = 0
        utteranceFillerCount = 0
        utteranceHeardAt = nil
        lastProcessedSegmentCount = 0
    }

    /// Per-word tallies from the same pause-aware pipeline that drives the
    /// headline count, so the repeated-filler cue names exactly what was said.
    /// Receives only the segments added since the last partial and accumulates
    /// additively - each segment index is counted exactly once per utterance,
    /// and `lastProcessedSegmentCount` resets to 0 whenever an utterance is
    /// committed (a new request, or the recognizer starting over inside one)
    /// so the next utterance's segments continue the tallies instead of
    /// colliding.
    @MainActor
    private func updateFillerWordCounts(words: [String], timestamps: [TimeInterval], durations: [TimeInterval]) {
        guard words.count == timestamps.count, words.count == durations.count else { return }

        let timings = zip(words, zip(timestamps, durations)).map { pair in
            RawWordTiming(
                word: pair.0,
                start: pair.1.0,
                end: pair.1.0 + pair.1.1,
                confidence: 1.0
            )
        }
        let tagged = FillerDetectionPipeline.tagFillers(in: timings, config: fillerConfig)

        for word in tagged where word.isFiller {
            let key = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard !key.isEmpty else { continue }
            liveFillerWordCounts[key, default: 0] += 1
        }
    }
}
