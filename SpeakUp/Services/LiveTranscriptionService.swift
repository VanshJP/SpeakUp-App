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

    var liveFillerWordCounts: [String: Int] = [:]

    var lastSegmentEndTime: TimeInterval = 0

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    /// Read from the realtime audio thread by the tap block and swapped on the
    /// main actor at every recognition restart, so it cannot be plain isolated
    /// state. The critical section is one `append`.
    private let requestBox = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(uncheckedState: nil)
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastProcessedSegmentCount = 0
    private var segmentTimeOffset: TimeInterval = 0
    private var recognitionGeneration = 0
    /// `removeTap` crashes if no tap is installed — track it explicitly.
    private var isTapInstalled = false
    /// Token only — touched from `deinit` (nonisolated) and init. Kept out of
    /// observation tracking so the token never participates in change
    /// notifications, and unsafe because NSObjectProtocol tokens are not
    /// Sendable but are only ever registered/removed from the main actor.
    @ObservationIgnored nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
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
    }

    /// Request speech recognition authorization (must be called before start).
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

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
        lastProcessedSegmentCount = 0
        segmentTimeOffset = 0
        isActive = true

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
    }

    @MainActor
    func stop() {
        requestBox.withLock { $0?.endAudio() }
        stopInternal()
    }

    @MainActor
    private func stopInternal() {
        // Idempotent across explicit stop() + cancelled-task callbacks.
        // Cleanup runs whenever an engine or request is still held — including
        // the orphaned-engine case after a failed recognition re-arm.
        let hasWork = isActive || audioEngine != nil || requestBox.withLock({ $0 != nil })
        guard hasWork else { return }

        isActive = false
        recognitionGeneration += 1

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

    @MainActor
    @discardableResult
    private func attachRecognition(on engine: AVAudioEngine) -> Bool {
        guard let recognizer, recognizer.isAvailable else { return false }

        let inputNode = engine.inputNode
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
        // assets are still installing — which used to hand that session's
        // microphone audio to Apple's servers. It also keeps latency low and
        // avoids network pauses that force early isFinal → restart cycles.
        request.requiresOnDeviceRecognition = true
        requestBox.withLock { $0 = request }
        lastProcessedSegmentCount = 0
        recognitionGeneration += 1
        let generation = recognitionGeneration

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
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isActive, self.recognitionGeneration == generation else { return }
                if let result { self.processPartialResult(result) }

                if hadError || isFinal {
                    self.restartRecognitionPreservingEngine()
                }
            }
        }
        return true
    }

    @MainActor
    private func restartRecognitionPreservingEngine() {
        guard isActive, let engine = audioEngine else {
            stopInternal()
            return
        }

        segmentTimeOffset = max(segmentTimeOffset, lastSegmentEndTime)

        recognitionGeneration += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        requestBox.withLock {
            $0?.endAudio()
            $0 = nil
        }

        guard attachRecognition(on: engine) else {
            isActive = false
            recognitionTask = nil
            requestBox.withLock { $0 = nil }
            return
        }
    }

    @MainActor
    private func processPartialResult(_ result: SFSpeechRecognitionResult) {
        let segments = result.bestTranscription.segments
        let wordCount = segments.count
        guard wordCount > 0 else {
            // Preserve the counter through transient empty partials — the
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

        liveFillerCount = max(liveFillerCount, fillerCount)
        liveWordCount = max(liveWordCount, wordCount)
        lastSegmentEndTime = max(lastSegmentEndTime, segmentTimeOffset + endTime)

        updateFillerWordCounts(
            words: Array(words[processedCount...]),
            timestamps: Array(timestamps[processedCount...]),
            durations: Array(durations[processedCount...])
        )
    }

    /// Per-word tallies from the same pause-aware pipeline that drives the
    /// headline count, so the repeated-filler cue names exactly what was said.
    /// Receives only the segments added since the last partial and accumulates
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
