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
    /// True only while a Hub download is in flight - not a local cache load.
    /// Analyzing UI uses this so a failed first download does not keep saying
    /// "Downloading…" through the Apple Speech fallback.
    private(set) var isDownloadingModel = false
    var modelLoadProgress: Double = 0
    var transcriptionProgress: Double = 0
    var errorMessage: String?

    // WhisperKit instance
    private var whisperKit: WhisperKit?

    /// Serializes transcribe / unloadModel. WhisperKit is not reentrant - two
    /// recordings processed concurrently (coordinator jobs for different
    /// recordingIDs) would race one shared instance: torn-down model under live
    /// inference.
    ///
    /// Building the model is deliberately *not* done under this semaphore; see
    /// `modelBuild`. A decode that overruns its watchdog is abandoned rather
    /// than awaited, and its instance dropped, so the next caller never shares
    /// an instance with it. See `awaitDecode`.
    private let semaphore = AsyncSemaphore(value: 1)

    /// The model build in flight, if any. Every caller shares it instead of
    /// starting a second one.
    ///
    /// It is its own task rather than work done while holding `semaphore`, so
    /// a take can wait on the build itself: awaiting a task raises it to the
    /// waiter's priority, and waiting on the semaphore raised nothing. The
    /// launch preload starts this build at background priority. A take that
    /// ended while it was still running used to queue behind it on the
    /// semaphore while the system starved it, and the self-check sat on
    /// "Preparing Speech Engine..." with nothing able to time it out.
    @ObservationIgnored private var modelBuild: Task<Void, Never>?

    /// Bumped whenever the model or a build is dropped, so a build that
    /// finishes late cannot install a model nobody is waiting for any more.
    @ObservationIgnored private var modelGeneration = 0

    /// How long a take waits for a first-time Hub download before falling
    /// through to on-device Apple Speech.
    private static let modelDownloadTimeout: TimeInterval = 45

    /// How long a take waits for a build from the on-disk cache. That is
    /// seconds normally, and up to about a minute for the Neural Engine
    /// compile after an OS update on an older phone. This is the backstop for
    /// a build that never finishes, not a performance bar.
    private static let modelBuildTimeout: TimeInterval = 90

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
    /// the end of the file and hands every consumer of word timings - playback
    /// highlighting, pause detection, per-word acoustics - a window of silence.
    nonisolated private static let maxWordDuration: TimeInterval = 3.0

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
    /// the file. Deliberately loose - the stall detector handles every ordinary
    /// hang long before this fires.
    /// Opens the audio file, so it runs inside the watchdog task, never on
    /// the main actor.
    nonisolated private static func decodeCeiling(for audioURL: URL) -> TimeInterval {
        let audioDuration = (try? AVAudioFile(forReading: audioURL)).map {
            Double($0.length) / $0.processingFormat.sampleRate
        } ?? 0
        return min(1800, max(300, audioDuration * 10))
    }

    // MARK: - Initialization

    /// Load the Whisper model (call this early, e.g., on app launch)
    /// - Parameter modelVariant: Model variant to use (tiny, base, small, medium, large-v3)
    ///
    /// Not time-boxed: nothing is waiting on a preload. A take that needs the
    /// model waits through `modelForTranscription()` instead, which is.
    func loadModel(modelVariant: String = "base") async {
        guard let build = startModelBuildIfNeeded(modelVariant: modelVariant) else { return }
        await build.value
    }

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

    /// Starts a model build unless the model is loaded or a build is already
    /// running. Returns the build to wait on, or nil when the model is ready.
    private func startModelBuildIfNeeded(modelVariant: String = "base") -> Task<Void, Never>? {
        if whisperKit != nil, isModelLoaded { return nil }
        if let modelBuild { return modelBuild }

        let isFirstLoad = !Self.hasCompletedFirstLoad
        let variantName = "openai_whisper-\(modelVariant)"

        // Prefer a fully local load whenever the Core ML bundle is already
        // on disk. WhisperKitConfig(download: true) hits Hugging Face
        // *before* it looks at the cache - on spotty Wi‑Fi that hangs
        // processing even though the model never needed the network.
        // Once cached, transcription must work in airplane mode.
        let config = Self.makeConfig(variantName: variantName)

        modelGeneration += 1
        let generation = modelGeneration
        isLoadingModel = true
        isDownloadingModel = config.download
        modelLoadProgress = 0.1
        errorMessage = nil

        // Runs at the caller's priority (background for the launch preload)
        // until a take waits on it and raises it.
        let build = Task(priority: Task.currentPriority) { [weak self] in
            let built: Result<WhisperKit, Error>
            do {
                built = .success(try await WhisperKit(config))
            } catch {
                built = .failure(error)
            }
            self?.finishModelBuild(
                built,
                generation: generation,
                isFirstLoad: isFirstLoad,
                modelVariant: modelVariant
            )
        }
        modelBuild = build
        return build
    }

    private func finishModelBuild(
        _ built: Result<WhisperKit, Error>,
        generation: Int,
        isFirstLoad: Bool,
        modelVariant: String
    ) {
        // Dropped while it ran: unloaded, or a take gave up on a download.
        guard generation == modelGeneration else { return }

        modelBuild = nil
        isLoadingModel = false
        isDownloadingModel = false

        switch built {
        case .success(let kit):
            whisperKit = kit
            modelLoadProgress = 1.0
            isModelLoaded = true
            if isFirstLoad {
                UserDefaults.standard.set(true, forKey: Self.firstLoadCompletedKey)
                AnalyticsService.shared.log(.modelDownload(tier: modelVariant, result: "success"))
            }
        case .failure(let error):
            errorMessage = "Failed to load Whisper model: \(error.localizedDescription)"
            whisperKit = nil
            isModelLoaded = false
            modelLoadProgress = 0
            if isFirstLoad {
                AnalyticsService.shared.log(.modelDownload(tier: modelVariant, result: "failed"))
            }
        }
    }

    /// The model, for a take that is waiting on it now.
    ///
    /// Waits on the build itself, which raises it to this caller's priority,
    /// and gives up after a bounded wait instead of pinning the take. Returns
    /// the error to throw, or nil once the model is ready.
    private func modelForTranscription() async -> (any Error)? {
        guard let build = startModelBuildIfNeeded() else { return nil }

        let isDownload = isDownloadingModel
        let finished = await Self.wait(
            for: build,
            upTo: isDownload ? Self.modelDownloadTimeout : Self.modelBuildTimeout
        )
        if Task.isCancelled { return CancellationError() }
        if finished {
            return whisperKit != nil && isModelLoaded ? nil : WhisperServiceError.modelNotLoaded
        }

        // A local build is left running: it is not waiting on the network,
        // and the next take may find it finished.
        guard isDownload else { return WhisperServiceError.modelBuildTimedOut }

        // A download that overran is cancelled, so it stops spending the
        // user's connection and the analyzing copy stops saying
        // "Downloading..." through the Apple Speech fallback.
        discardModel()
        errorMessage = WhisperServiceError.modelDownloadTimedOut.errorDescription
        if !Self.hasCompletedFirstLoad {
            AnalyticsService.shared.log(.modelDownload(tier: "base", result: "timeout"))
        }
        return WhisperServiceError.modelDownloadTimedOut
    }

    /// Forgets the model and any build in flight. A build that finishes later
    /// is ignored; a decode still holding the old instance keeps its own
    /// reference and never shares it with the next caller.
    private func discardModel() {
        modelGeneration += 1
        modelBuild?.cancel()
        modelBuild = nil
        whisperKit = nil
        isModelLoaded = false
        isLoadingModel = false
        isDownloadingModel = false
        modelLoadProgress = 0
    }

    /// Waits up to `seconds` for `task`. Returns true once it has finished and
    /// false on timeout or cancellation - without waiting any longer, since a
    /// wedged task would otherwise pin the caller. The wait runs at the
    /// caller's priority, which raises `task` to it.
    nonisolated private static func wait(
        for task: Task<Void, Never>,
        upTo seconds: TimeInterval
    ) async -> Bool {
        let race = FirstFinisher<Bool>()
        let priority = Task.currentPriority
        let finished = try? await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                race.adopt(Task.detached(priority: priority) {
                    await task.value
                    race.finish(.success(true))
                })
                race.adopt(Task.detached(priority: priority) {
                    try? await Task.sleep(for: .seconds(seconds))
                    race.finish(.success(false))
                })
            }
        } onCancel: {
            race.finish(.success(false))
        }
        return finished ?? false
    }

    // MARK: - Offline-first config

    /// Documents/huggingface - same default HubApi uses, so a prior download
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
        // AudioEncoder alone on disk - treating that as offline-ready would
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
            // finished - pass it so loadTokenizer skips the network too.
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

    // MARK: - Transcription

    /// Transcribe audio file with filler word detection and optional preferred terms.
    func transcribe(audioURL: URL, preferredTerms: [String] = []) async throws -> SpeechTranscriptionResult {
        // The model first, outside the semaphore, so a take waits on the build
        // (and raises its priority) instead of queueing behind it.
        if let failure = await modelForTranscription() {
            throw failure
        }

        await semaphore.wait()
        defer { semaphore.signal() }

        // Unloaded while this call waited its turn (the local LLM claiming
        // the memory) - the reload leg in `SpeechService` rebuilds it.
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
            // the cap, the decoder can hang indefinitely on inference - cap both the source
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
                // Inert while `promptTokens` is set - WhisperKit skips the KV
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
                // WhisperKit discards an entire 30 s window - no error, no gap
                // marker - when `noSpeechProb > noSpeechThreshold` and the
                // window also fails `logProbThreshold`
                // (SegmentSeeker.findSeekPointAndSegments). Lowering it drops
                // *more* audio, so the old 0.4 (against a 0.6 default) was
                // deleting quiet stretches: trailing off at the end of a
                // thought, or fading in the back half of a long recording.
                noSpeechThreshold: 0.6
            )

            // WhisperKit's decoder can hang indefinitely under certain conditions
            // (degenerate audio, prompt edge-cases), so a watchdog runs alongside
            // it - see `awaitDecode`. Only one result is ever returned here:
            // without a `chunkingStrategy` WhisperKit decodes the whole file in a
            // single task, so `.first` is the complete transcript, not the first
            // chunk. The decode is its own task, not a task-group child, so the
            // watchdog can give up on it: a task group waits for every child
            // before it rethrows, and a wedged decode never finishes.
            //
            // It runs on `WhisperDecodeExecutor`, not the cooperative pool: see
            // that type for why. The per-token callback below is delivered
            // from a low-priority task on the pool, so a busy pool starves it
            // while the decode itself is fine. The segment callback runs inline
            // in the decode loop, once per window, so the watchdog still sees
            // the decode moving when the pool is saturated.
            let kit = WhisperKitBox(whisperKit)
            let decode = Task.detached(
                executorPreference: WhisperDecodeExecutor.shared,
                priority: Task.currentPriority
            ) { () async throws -> WhisperTranscriptionResult in
                kit.value.segmentDiscoveryCallback = { _ in heartbeat.beat() }
                let results = try await kit.value.transcribe(
                    audioPath: audioURL.path,
                    decodeOptions: options,
                    callback: { _ in
                        heartbeat.beat()
                        // `false` is WhisperKit's documented early-stop.
                        return !heartbeat.shouldAbort
                    }
                )
                guard let first = results.first else {
                    throw WhisperServiceError.noSpeechTranscriptionResult
                }
                return first
            }
            let result = try await Self.awaitDecode(decode, heartbeat: heartbeat, audioURL: audioURL)

            transcriptionProgress = 1.0

            // Process the WhisperKit result into our format. Detached because
            // the word-timing walk over a long transcript is pure CPU that has
            // no business on the main actor - this used to run inline and
            // stalled any sheet presentation racing it (e.g. tapping Calm
            // right after a take finishes).
            return await Task.detached(priority: .userInitiated) {
                Self.processWhisperResult(result)
            }.value

        } catch WhisperServiceError.transcriptionTimedOut {
            // The watchdog gave up on a decode that may still be running on
            // this instance. Drop it, so the next caller builds a clean one
            // instead of sharing it, and let `SpeechService` skip the Whisper
            // retries: a stalled decode would only stall again.
            if self.whisperKit === whisperKit {
                discardModel()
            }
            throw WhisperServiceError.transcriptionTimedOut
        } catch is CancellationError {
            // External cancellation (job cancelled, app backgrounding): stop
            // the decode before unwinding. `awaitDecode` has already done so.
            heartbeat.requestAbort()
            throw CancellationError()
        } catch {
            throw WhisperServiceError.transcriptionFailed(error)
        }
    }

    /// Waits for `decode` under a stall watchdog and returns as soon as either
    /// side settles.
    ///
    /// The watchdog measures decode *progress*, not elapsed time - see
    /// `decodeStallTimeout` - with `decodeCeiling` as the backstop. On a stall
    /// it flags the heartbeat and cancels the decode (WhisperKit checks
    /// cancellation before every decoder step), then returns at once rather
    /// than waiting for the decode to acknowledge: a decode wedged inside
    /// WhisperKit never would, and waiting on it is what used to leave the
    /// self-check on "Transcribing..." for good.
    nonisolated private static func awaitDecode(
        _ decode: Task<WhisperTranscriptionResult, Error>,
        heartbeat: DecodeHeartbeat,
        audioURL: URL
    ) async throws -> WhisperTranscriptionResult {
        let race = FirstFinisher<WhisperTranscriptionResult>()
        let priority = Task.currentPriority
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                race.adopt(Task.detached(priority: priority) {
                    do {
                        race.finish(.success(try await decode.value))
                    } catch {
                        race.finish(.failure(error))
                    }
                })
                race.adopt(Task.detached(priority: priority) {
                    // Opens the audio file, so it runs here, never on the
                    // main actor.
                    let deadline = Date().addingTimeInterval(WhisperService.decodeCeiling(for: audioURL))
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        if heartbeat.secondsSinceLastBeat >= WhisperService.decodeStallTimeout
                            || Date() >= deadline {
                            heartbeat.requestAbort()
                            decode.cancel()
                            race.finish(.failure(WhisperServiceError.transcriptionTimedOut))
                            return
                        }
                    }
                })
            }
        } onCancel: {
            heartbeat.requestAbort()
            decode.cancel()
            race.finish(.failure(CancellationError()))
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
    /// actor-isolated state - pure value math over POD timings.
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
        // Waits out a decode in flight; a build in flight is simply dropped.
        discardModel()
    }
}

/// Carries the non-Sendable WhisperKit instance into the decode task. Only
/// one decode ever uses an instance at a time (see `semaphore`).
nonisolated private final class WhisperKitBox: @unchecked Sendable {
    let value: WhisperKit
    init(_ value: WhisperKit) { self.value = value }
}

/// Runs WhisperKit's decode on GCD threads instead of Swift's cooperative pool.
///
/// WhisperKit 0.15's greedy sampler reads each token out of an `MLTensor` with
/// `asIntArray()` / `asFloatArray()`, which start a `Task` and block the calling
/// thread on a `DispatchSemaphore` until it finishes - twice per token. On the
/// cooperative pool that parks one of its few threads (one per core) for every
/// token, and the pool never adds a thread to replace a blocked one. Anything
/// else holding pool threads at the same time - a llama generate or unload,
/// background SwiftData fetches, the analysis of an earlier take - leaves the
/// sampler's task waiting for a thread, and the decode crawls or stalls. A
/// freshly launched app has an idle pool, so the same take decodes quickly
/// after a relaunch.
///
/// GCD notices a worker blocked in the kernel and brings up another, so the
/// same waits here cost a thread for a moment instead of starving the pool.
nonisolated private final class WhisperDecodeExecutor: TaskExecutor {
    static let shared = WhisperDecodeExecutor()

    private let queue = DispatchQueue(
        label: "com.vansh.SpeakUpMore.whisper-decode",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        let executor = asUnownedTaskExecutor()
        queue.async {
            unownedJob.runSynchronously(on: executor)
        }
    }
}

/// Hands a continuation to whichever of several racing tasks finishes first,
/// then cancels the rest. Every lock call stays in a synchronous method -
/// NSLock is unavailable from asynchronous contexts under Swift 6.
nonisolated private final class FirstFinisher<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var outcome: Result<Value, Error>?
    private var racers: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        guard let settled = outcome else {
            self.continuation = continuation
            lock.unlock()
            return
        }
        lock.unlock()
        continuation.resume(with: settled)
    }

    /// Registers a racer, cancelling it straight away if the race is over.
    func adopt(_ racer: Task<Void, Never>) {
        lock.lock()
        let isOver = outcome != nil
        if !isOver { racers.append(racer) }
        lock.unlock()
        if isOver { racer.cancel() }
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return
        }
        outcome = result
        let waiting = continuation
        continuation = nil
        let losers = racers
        racers = []
        lock.unlock()
        losers.forEach { $0.cancel() }
        waiting?.resume(with: result)
    }
}

/// Liveness signal for a running decode.
///
/// WhisperKit invokes the transcription callback from a detached background
/// task, once per decoded token, so this must be thread-safe and must not touch
/// actor-isolated state. The watchdog reads `secondsSinceLastBeat` to tell a
/// slow recording (beating steadily) from a hung decoder (silent), and flips
/// `shouldAbort` to make the callback stop the decode - cancelling the await
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
/// Locking stays inside non-async closures - NSLock is unavailable from
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
    case modelBuildTimedOut
    case noSpeechTranscriptionResult
    case transcriptionFailed(Error)
    case transcriptionTimedOut

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Speech model isn't ready yet."
        case .modelDownloadTimedOut:
            return "Speech model download timed out. Check your connection, or try again later. On-device recognition can still finish the take."
        case .modelBuildTimedOut:
            return "Speech model took too long to start. On-device recognition can still finish the take."
        case .noSpeechTranscriptionResult:
            return "No transcription result was produced."
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .transcriptionTimedOut:
            return "Transcription timed out. Try recording a shorter clip or restart the app."
        }
    }

    /// A timeout, not a bad transcript: the model is still downloading or
    /// building, or a decode stalled. Retrying Whisper would only wait again.
    var abandonsWhisper: Bool {
        switch self {
        case .modelDownloadTimedOut, .modelBuildTimedOut, .transcriptionTimedOut:
            return true
        case .modelNotLoaded, .noSpeechTranscriptionResult, .transcriptionFailed:
            return false
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
