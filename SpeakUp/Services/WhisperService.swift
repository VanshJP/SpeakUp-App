import AVFoundation
import Foundation
import WhisperKit

// WhisperKit exports TranscriptionResult - we use our own SpeechTranscriptionResult
// to avoid naming collisions
typealias WhisperTranscriptionResult = TranscriptionResult

/// WhisperKit-based speech transcription service for accurate filler word detection
@Observable
class WhisperService {
    // State
    var isTranscribing = false
    var isModelLoaded = false
    /// True while `loadModel` is in flight (local load or Hub download).
    private(set) var isLoadingModel = false
    /// True only while a Hub download is in flight — not a local cache load.
    /// Analyzing UI uses this so a failed first download does not keep saying
    /// "Downloading…" through the Apple Speech fallback.
    private(set) var isDownloadingModel = false
    var modelLoadProgress: Double = 0
    var transcriptionProgress: Double = 0
    var errorMessage: String?

    // WhisperKit instance
    private var whisperKit: WhisperKit?

    /// Serializes loadModel / transcribe / unloadModel. WhisperKit is not
    /// reentrant — two recordings processed concurrently (coordinator jobs for
    /// different recordingIDs) would race one shared instance: torn-down model
    /// under live inference, double model loads.
    ///
    /// Release ordering stays safe because the signal fires only after
    /// transcribe's task group has awaited every child, and it is the
    /// heartbeat's abort flag — not cancellation — that actually stops
    /// WhisperKit's internal decode first. See `DecodeHeartbeat`.
    private let semaphore = AsyncSemaphore(value: 1)

    // Filler word prompt to encourage capturing hesitations
    // This prompt biases the model toward transcribing filler sounds
    // The transcript style with hesitations helps Whisper recognize and output them
    private let fillerPrompt = "Um, uh, er, ah, hmm, mm, mhm, uh-huh, like, you know, I mean, so, basically. The speaker says um and uh frequently. Um, so, like, you know, I was, uh, thinking about, um, the thing."

    /// Whisper's decoder prompt context is capped at 224 tokens. Staying comfortably under
    /// the cap prevents the decoder from hanging on oversized prompts when the user has a
    /// large vocab/dictation bank.
    private static let maxPromptTokens = 200

    /// Maximum number of user-supplied bias terms to include in the prompt line, so the
    /// dictionary clause can never dominate the prompt budget even before tokenization.
    private static let maxBiasTerms = 25

    /// Ceiling on a single word's length. Whisper occasionally emits a word whose end
    /// timestamp overshoots by minutes; left alone it drags the reported duration past
    /// the end of the file and hands every consumer of word timings — playback
    /// highlighting, pause detection, per-word acoustics — a window of silence.
    private static let maxWordDuration: TimeInterval = 3.0

    /// Longest gap between decoded tokens before the decoder counts as hung.
    ///
    /// WhisperKit reports every token through the transcription callback, so a
    /// live decoder beats many times per window. Watching that beat instead of
    /// total elapsed time is what lets a 10-minute recording finish: the flat
    /// 90 s cap this replaced timed those out, and each timeout fell through
    /// the chain to Apple Speech, which returns a truncated transcript.
    nonisolated private static let decodeStallTimeout: TimeInterval = 60

    /// Backstop for the one failure the stall detector cannot see: a decoder
    /// that keeps emitting tokens while the seek point never advances through
    /// the file. Deliberately loose — the stall detector handles every ordinary
    /// hang long before this fires.
    private static func decodeCeiling(for audioURL: URL) -> TimeInterval {
        let audioDuration = (try? AVAudioFile(forReading: audioURL)).map {
            Double($0.length) / $0.processingFormat.sampleRate
        } ?? 0
        return min(1800, max(300, audioDuration * 10))
    }

    // MARK: - Initialization

    /// Load the Whisper model (call this early, e.g., on app launch)
    /// - Parameter modelVariant: Model variant to use (tiny, base, small, medium, large-v3)
    func loadModel(modelVariant: String = "base") async {
        await semaphore.wait()
        defer { semaphore.signal() }
        await loadModelLocked(modelVariant: modelVariant)
    }

    /// Precondition: semaphore held.
    /// Whether the speech model has ever finished loading on this device.
    ///
    /// The difference matters to the user: a first load downloads roughly
    /// 150 MB and can take minutes on a slow connection, while every load after
    /// it is seconds. Without this the same spinner covers both, and the first
    /// run looks broken.
    private static let firstLoadCompletedKey = "whisper.firstLoadCompleted.v1"

    static var hasCompletedFirstLoad: Bool {
        UserDefaults.standard.bool(forKey: firstLoadCompletedKey)
    }

    private func loadModelLocked(modelVariant: String = "base") async {
        // Allow re-initialization if model exists but isn't fully loaded
        guard whisperKit == nil || !isModelLoaded else { return }

        let isFirstLoad = !Self.hasCompletedFirstLoad
        let variantName = "openai_whisper-\(modelVariant)"

        isLoadingModel = true
        defer {
            isLoadingModel = false
            isDownloadingModel = false
        }

        do {
            modelLoadProgress = 0.1
            errorMessage = nil

            // Prefer a fully local load whenever the Core ML bundle is already
            // on disk. WhisperKitConfig(download: true) hits Hugging Face
            // *before* it looks at the cache — on spotty Wi‑Fi that hangs
            // processing even though the model never needed the network.
            // Once cached, transcription must work in airplane mode.
            let config = Self.makeConfig(variantName: variantName)

            if config.download {
                // First install (or a wiped cache) still needs the network.
                // Cap the wait so a flaky connection fails into Apple Speech
                // instead of spinning the analyzing screen forever.
                isDownloadingModel = true
                whisperKit = try await Self.loadWhisperKitWithDownloadTimeout(
                    config: config,
                    seconds: 45
                )
            } else {
                whisperKit = try await WhisperKit(config)
            }

            modelLoadProgress = 1.0
            isModelLoaded = true

            if isFirstLoad {
                UserDefaults.standard.set(true, forKey: Self.firstLoadCompletedKey)
                await MainActor.run {
                    AnalyticsService.shared.log(
                        .modelDownload(tier: modelVariant, result: "success")
                    )
                }
            }
        } catch {
            let timedOut: Bool = {
                if case WhisperServiceError.modelDownloadTimedOut = error { return true }
                return false
            }()
            errorMessage = timedOut
                ? WhisperServiceError.modelDownloadTimedOut.errorDescription
                : "Failed to load Whisper model: \(error.localizedDescription)"
            isModelLoaded = false
            modelLoadProgress = 0
            whisperKit = nil

            if isFirstLoad {
                await MainActor.run {
                    AnalyticsService.shared.log(
                        .modelDownload(tier: modelVariant, result: timedOut ? "timeout" : "failed")
                    )
                }
            }
        }
    }

    // MARK: - Offline-first config

    /// Documents/huggingface — same default HubApi uses, so a prior download
    /// lands where we look for it on the next launch.
    private static var hubDownloadBase: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    /// Folder WhisperKit wrote during a previous `download: true` load.
    private static func cachedModelFolder(variantName: String) -> URL? {
        let folder = hubDownloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(variantName, isDirectory: true)

        // Require encoder + decoder. An interrupted Hub download can leave
        // AudioEncoder alone on disk — treating that as offline-ready would
        // permanently skip re-download and fail every load with download:false.
        let encoderCandidates = ["AudioEncoder.mlmodelc", "AudioEncoder.mlpackage"]
        let decoderCandidates = ["TextDecoder.mlmodelc", "TextDecoder.mlpackage"]
        let hasEncoder = encoderCandidates.contains {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        let hasDecoder = decoderCandidates.contains {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        return (hasEncoder && hasDecoder) ? folder : nil
    }

    private static func makeConfig(variantName: String) -> WhisperKitConfig {
        if let localFolder = cachedModelFolder(variantName: variantName) {
            // Point at the on-disk bundle and refuse Hub contact. Tokenizer
            // also resolves under hubDownloadBase once the first download
            // finished — pass it so loadTokenizer skips the network too.
            return WhisperKitConfig(
                modelFolder: localFolder.path,
                tokenizerFolder: hubDownloadBase,
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: true,
                download: false
            )
        }

        return WhisperKitConfig(
            model: variantName,
            downloadBase: hubDownloadBase,
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: true
        )
    }

    /// Races Hub download against a wall-clock deadline. Local loads skip this.
    ///
    /// `WhisperKit` / `WhisperKitConfig` are not Sendable, so the result is
    /// stashed in an unchecked box instead of crossing the task-group as `T`.
    private static func loadWhisperKitWithDownloadTimeout(
        config: WhisperKitConfig,
        seconds: TimeInterval
    ) async throws -> WhisperKit {
        final class Box: @unchecked Sendable {
            var value: WhisperKit?
        }
        let box = Box()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                box.value = try await WhisperKit(config)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw WhisperServiceError.modelDownloadTimedOut
            }
            // First child to finish wins: success empties the group via
            // cancelAll; timeout / download error throws out.
            try await group.next()
            group.cancelAll()
        }
        guard let kit = box.value else {
            throw WhisperServiceError.modelDownloadTimedOut
        }
        return kit
    }

    // MARK: - Transcription

    /// Transcribe audio file with filler word detection and optional preferred terms.
    func transcribe(audioURL: URL, preferredTerms: [String] = []) async throws -> SpeechTranscriptionResult {
        await semaphore.wait()
        defer { semaphore.signal() }

        // Load model if not loaded
        if whisperKit == nil {
            await loadModelLocked()
        }

        guard let whisperKit else {
            throw WhisperServiceError.modelNotLoaded
        }

        isTranscribing = true
        transcriptionProgress = 0

        defer {
            isTranscribing = false
            transcriptionProgress = 1.0
        }

        // One heartbeat per call, created before the try block so the
        // cancellation path below can still reach it. A fresh instance also
        // clears any abort state a previous run left behind.
        let heartbeat = DecodeHeartbeat()

        do {
            // Tokenize prompt to condition the model toward fillers + user dictionary words.
            // Whisper's prompt context is capped (~224 tokens). If the encoded prompt exceeds
            // the cap, the decoder can hang indefinitely on inference — cap both the source
            // term list and the final token count to stay safely under the limit.
            let biasPrompt = buildBiasPrompt(preferredTerms: preferredTerms)
            let encoded = whisperKit.tokenizer?.encode(text: biasPrompt).filter { $0 < 51865 } ?? []
            let promptTokens = Array(encoded.suffix(WhisperService.maxPromptTokens))
            
            // Configure decoding options for filler word capture
            let options = DecodingOptions(
                task: .transcribe,
                language: "en",
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                // WhisperKit's default. A window that fails the logprob or
                // compression-ratio checks is retried at a higher temperature;
                // cutting the retries short (this was 3) writes off marginal
                // windows that a later attempt would have decoded. The cost is
                // paid only on windows that are already failing.
                temperatureFallbackCount: 5,
                usePrefillPrompt: true,
                // Inert while `promptTokens` is set — WhisperKit skips the KV
                // cache prefill in that case (TextDecoder: "currently breaks if
                // it starts at non-zero index"). Left true for the day the
                // prompt goes away.
                usePrefillCache: true,
                skipSpecialTokens: false,
                withoutTimestamps: false,
                wordTimestamps: true,  // Enable word-level timestamps
                promptTokens: promptTokens,  // Condition model to transcribe filler words
                suppressBlank: false,  // Don't suppress blank/hesitation sounds
                supressTokens: nil,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                firstTokenLogProbThreshold: -1.5,
                // This is the *silence* trigger, not a speech-sensitivity dial.
                // WhisperKit discards an entire 30 s window — no error, no gap
                // marker — when `noSpeechProb > noSpeechThreshold` and the
                // window also fails `logProbThreshold`
                // (SegmentSeeker.findSeekPointAndSegments). Lowering it drops
                // *more* audio, so the old 0.4 (against a 0.6 default) was
                // deleting quiet stretches: trailing off at the end of a
                // thought, or fading in the back half of a long recording.
                noSpeechThreshold: 0.6
            )

            // WhisperKit's decoder can hang indefinitely under certain conditions
            // (degenerate audio, prompt edge-cases), so a watchdog runs alongside
            // it. The watchdog measures decode *progress*, not elapsed time — see
            // `decodeStallTimeout`. Only one result is ever returned here: without
            // a `chunkingStrategy` WhisperKit decodes the whole file in a single
            // task, so `.first` is the complete transcript, not the first chunk.
            let ceiling = WhisperService.decodeCeiling(for: audioURL)
            let result: WhisperTranscriptionResult = try await withThrowingTaskGroup(of: WhisperTranscriptionResult.self) { group in
                group.addTask {
                    let results = try await whisperKit.transcribe(
                        audioPath: audioURL.path,
                        decodeOptions: options,
                        callback: { _ in
                            heartbeat.beat()
                            // `false` is WhisperKit's documented early-stop:
                            // the only way to actually halt its internal
                            // decode, since task cancellation never reaches it.
                            return !heartbeat.shouldAbort
                        }
                    )
                    guard let first = results.first else {
                        throw WhisperServiceError.noSpeechTranscriptionResult
                    }
                    return first
                }
                group.addTask {
                    let deadline = Date().addingTimeInterval(ceiling)
                    while true {
                        try await Task.sleep(for: .seconds(5))
                        guard heartbeat.secondsSinceLastBeat < WhisperService.decodeStallTimeout,
                              Date() < deadline else {
                            // Stop the decode BEFORE bailing — once this error
                            // unwinds, the semaphore hands the shared instance
                            // to the next caller and a still-running decode
                            // would race it.
                            heartbeat.requestAbort()
                            throw WhisperServiceError.transcriptionTimedOut
                        }
                    }
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }

            transcriptionProgress = 1.0

            // Process the WhisperKit result into our format. Detached because
            // the word-timing walk over a long transcript is pure CPU that has
            // no business on the main actor — this used to run inline and
            // stalled any sheet presentation racing it (e.g. tapping Calm
            // right after a take finishes).
            return await Task.detached(priority: .userInitiated) {
                Self.processWhisperResult(result)
            }.value

        } catch is CancellationError {
            // External cancellation (job cancelled, app backgrounding): same
            // zombie risk as the watchdog — stop the decode before unwinding.
            heartbeat.requestAbort()
            throw CancellationError()
        } catch {
            throw WhisperServiceError.transcriptionFailed(error)
        }
    }

    private func buildBiasPrompt(preferredTerms: [String]) -> String {
        let cleanedTerms = preferredTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()
            .prefix(WhisperService.maxBiasTerms)

        guard !cleanedTerms.isEmpty else { return fillerPrompt }
        let dictionaryLine = "Preferred names and terms: \(cleanedTerms.joined(separator: ", "))."
        return "\(fillerPrompt) \(dictionaryLine)"
    }

    /// Process WhisperKit result into our SpeechTranscriptionResult format with filler detection.
    /// `nonisolated`: runs detached off the main actor, so it can touch no
    /// actor-isolated state — pure value math over POD timings.
    nonisolated private static func processWhisperResult(_ result: WhisperTranscriptionResult) -> SpeechTranscriptionResult {
        // Collect all word timings from all segments
        var rawTimings: [RawWordTiming] = []

        for segment in result.segments {
            if let wordTimings = segment.words {
                for wordTiming in wordTimings {
                    let word = wordTiming.word.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if !word.isEmpty {
                        rawTimings.append(RawWordTiming(
                            word: word,
                            start: TimeInterval(wordTiming.start),
                            end: TimeInterval(wordTiming.end),
                            confidence: Double(wordTiming.probability)
                        ))
                    }
                }
            } else {
                // Fallback: use segment-level timing and split text
                let segmentWords = segment.text.split(separator: " ").map(String.init)
                let segmentDuration = segment.end - segment.start
                let wordDuration = segmentWords.isEmpty ? 0 : segmentDuration / Float(segmentWords.count)

                for (i, word) in segmentWords.enumerated() {
                    let start = segment.start + Float(i) * wordDuration
                    let end = start + wordDuration
                    rawTimings.append(RawWordTiming(
                        word: word.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                        start: TimeInterval(start),
                        end: TimeInterval(end),
                        confidence: Double(1.0 - segment.noSpeechProb)
                    ))
                }
            }
        }

        // Sort by start time to ensure chronological order across segments
        rawTimings.sort { $0.start < $1.start }

        let normalizedTimings = WhisperService.normalizeTimings(rawTimings)

        // Run unified filler detection pipeline
        let words = FillerDetectionPipeline.tagFillers(in: normalizedTimings)
        let duration = normalizedTimings.last?.end ?? 0

        return SpeechTranscriptionResult(
            text: result.text,
            words: words,
            duration: duration
        )
    }

    /// Clamp word timings: Whisper partial segments can occasionally emit tiny overlaps
    /// or zero-length words. Every word keeps its own start (the caller sorted them, so
    /// starts are already non-decreasing) and gets a non-zero duration bounded by both
    /// the next word's start and `maxWordDuration`.
    ///
    /// Nothing carries forward: the previous version clamped each start against the
    /// previous *end*, so one overshooting end timestamp shifted every word after it.
    ///
    /// Expects `rawTimings` sorted by start.
    nonisolated static func normalizeTimings(_ rawTimings: [RawWordTiming]) -> [RawWordTiming] {
        var normalized: [RawWordTiming] = []
        normalized.reserveCapacity(rawTimings.count)

        for (index, timing) in rawTimings.enumerated() {
            let start = max(0, timing.start)
            let minimumEnd = start + 0.01
            var ceiling = start + maxWordDuration
            if index + 1 < rawTimings.count {
                ceiling = min(ceiling, max(minimumEnd, rawTimings[index + 1].start))
            }
            normalized.append(
                RawWordTiming(
                    word: timing.word,
                    start: start,
                    end: min(max(minimumEnd, timing.end), ceiling),
                    confidence: timing.confidence
                )
            )
        }

        return normalized
    }

    // MARK: - Model Management

    /// Unload model to free memory
    func unloadModel() async {
        await semaphore.wait()
        defer { semaphore.signal() }
        whisperKit = nil
        isModelLoaded = false
        modelLoadProgress = 0
    }
}

/// Liveness signal for a running decode.
///
/// WhisperKit invokes the transcription callback from a detached background
/// task, once per decoded token, so this must be thread-safe and must not touch
/// actor-isolated state. The watchdog reads `secondsSinceLastBeat` to tell a
/// slow recording (beating steadily) from a hung decoder (silent), and flips
/// `shouldAbort` to make the callback stop the decode — cancelling the await
/// alone never reaches WhisperKit's internals, which would leave a zombie
/// decode running while the semaphore lets the next caller in.
nonisolated private final class DecodeHeartbeat: @unchecked Sendable {
    private var lastBeat = Date()
    private var abortRequested = false
    private let lock = NSLock()

    func beat() {
        lock.lock()
        lastBeat = Date()
        lock.unlock()
    }

    var secondsSinceLastBeat: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastBeat)
    }

    /// One-way switch: set by the watchdog before it throws and by the
    /// cancellation path. A fresh instance per transcribe call resets it.
    func requestAbort() {
        lock.lock()
        abortRequested = true
        lock.unlock()
    }

    var shouldAbort: Bool {
        lock.lock()
        defer { lock.unlock() }
        return abortRequested
    }
}

/// Minimal counting semaphore for async critical sections.
/// Synchronous `signal()` so it is safe to call from `defer`.
/// Locking stays inside non-async closures — NSLock is unavailable from
/// asynchronous contexts under Swift 6.
nonisolated private final class AsyncSemaphore: @unchecked Sendable {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    init(value: Int) {
        permits = value
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if permits > 0 {
                permits -= 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func signal() {
        lock.lock()
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume()
        } else {
            permits += 1
            lock.unlock()
        }
    }
}


// MARK: - Errors

enum WhisperServiceError: LocalizedError {
    case modelNotLoaded
    case modelDownloadTimedOut
    case noSpeechTranscriptionResult
    case transcriptionFailed(Error)
    case transcriptionTimedOut

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Speech model isn't ready yet."
        case .modelDownloadTimedOut:
            return "Speech model download timed out. Check your connection, or try again later — on-device recognition can still finish the take."
        case .noSpeechTranscriptionResult:
            return "No transcription result was produced."
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .transcriptionTimedOut:
            return "Transcription timed out. Try recording a shorter clip or restart the app."
        }
    }
}

private extension Array where Element == String {
    func uniquedPreservingOrder() -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in self {
            let normalized = value.lowercased()
            if seen.insert(normalized).inserted {
                result.append(value)
            }
        }
        return result
    }
}
