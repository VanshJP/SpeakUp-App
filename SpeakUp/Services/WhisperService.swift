import AVFoundation
import Foundation
import WhisperKit

typealias WhisperTranscriptionResult = TranscriptionResult

/// WhisperKit transcription with filler-biased prompting and bounded waits.
@Observable
class WhisperService {
    /// True while a model build is in flight (cache load or Hub download).
    private(set) var isLoadingModel = false
    /// True only while a Hub download is in flight, so the analyzing copy
    /// can say "Downloading…" without lying through a local load.
    private(set) var isDownloadingModel = false

    private var whisperKit: WhisperKit?

    /// Serializes decode and unload. WhisperKit is not reentrant. Model builds
    /// run outside it (see `modelBuild`) so a take can raise a build's priority
    /// by awaiting it.
    private let semaphore = AsyncSemaphore(value: 1)

    /// The shared model build in flight, if any.
    @ObservationIgnored private var modelBuild: Task<Void, Never>?

    /// Bumped whenever the model or a build is dropped, so a late build cannot
    /// install a model nobody is waiting for.
    @ObservationIgnored private var modelGeneration = 0

    /// First-time Hub download budget before falling through to Apple Speech.
    private static let modelDownloadTimeout: TimeInterval = 45

    /// Backstop for a cached build that never finishes. Normal is seconds;
    /// an ANE recompile after an OS update can take about a minute.
    private static let modelBuildTimeout: TimeInterval = 90

    /// Biases the decoder toward writing out hesitations.
    private let fillerPrompt = "Um, uh, er, ah, hmm, mm, mhm, uh-huh, like, you know, I mean, so, basically. The speaker says um and uh frequently. Um, so, like, you know, I was, uh, thinking about, um, the thing."

    /// Whisper's prompt context caps at 224 tokens; oversized prompts can hang
    /// the decoder.
    private static let maxPromptTokens = 200
    private static let maxBiasTerms = 25

    /// Whisper occasionally emits a word whose end overshoots by minutes.
    nonisolated private static let maxWordDuration: TimeInterval = 3.0

    /// Longest gap between decoded tokens before the decode counts as hung.
    /// Measures progress, not elapsed time, so long recordings still finish.
    nonisolated private static let decodeStallTimeout: TimeInterval = 60

    /// Backstop for a decoder that keeps emitting tokens without advancing.
    /// Opens the file, so call it off the main actor.
    nonisolated private static func decodeCeiling(for audioURL: URL) -> TimeInterval {
        let audioDuration = (try? AVAudioFile(forReading: audioURL)).map {
            Double($0.length) / $0.processingFormat.sampleRate
        } ?? 0
        return min(1800, max(300, audioDuration * 10))
    }

    // MARK: - Model Loading

    /// Launch preload. Not time-boxed: nothing waits on it. Takes wait through
    /// `modelForTranscription()`, which is bounded.
    func loadModel(modelVariant: String = "base") async {
        guard let build = startModelBuildIfNeeded(modelVariant: modelVariant) else { return }
        await build.value
    }

    /// First load downloads ~150 MB; later loads are seconds. The analyzing
    /// screen uses this to pick its copy.
    private static let firstLoadCompletedKey = "whisper.firstLoadCompleted.v1"

    static var hasCompletedFirstLoad: Bool {
        UserDefaults.standard.bool(forKey: firstLoadCompletedKey)
    }

    /// Starts a build unless the model is loaded or one is running. Returns
    /// the build to wait on, or nil when the model is ready.
    private func startModelBuildIfNeeded(modelVariant: String = "base") -> Task<Void, Never>? {
        if whisperKit != nil { return nil }
        if let modelBuild { return modelBuild }

        let isFirstLoad = !Self.hasCompletedFirstLoad
        let config = Self.makeConfig(variantName: "openai_whisper-\(modelVariant)")

        modelGeneration += 1
        let generation = modelGeneration
        isLoadingModel = true
        isDownloadingModel = config.download

        // Inherits the caller's priority until a take awaits it and raises it.
        let build = Task(priority: Task.currentPriority) { [weak self] in
            let built: Result<WhisperKit, Error>
            do {
                built = .success(try await WhisperKit(config))
            } catch {
                built = .failure(error)
            }
            self?.finishModelBuild(built, generation: generation, isFirstLoad: isFirstLoad, modelVariant: modelVariant)
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
        guard generation == modelGeneration else { return }

        modelBuild = nil
        isLoadingModel = false
        isDownloadingModel = false

        switch built {
        case .success(let kit):
            whisperKit = kit
            if isFirstLoad {
                UserDefaults.standard.set(true, forKey: Self.firstLoadCompletedKey)
                AnalyticsService.shared.log(.modelDownload(tier: modelVariant, result: "success"))
            }
        case .failure:
            whisperKit = nil
            if isFirstLoad {
                AnalyticsService.shared.log(.modelDownload(tier: modelVariant, result: "failed"))
            }
        }
    }

    /// Waits (bounded) for the model on behalf of a take. Returns the error
    /// to throw, or nil once the model is ready.
    private func modelForTranscription() async -> (any Error)? {
        guard let build = startModelBuildIfNeeded() else { return nil }

        let isDownload = isDownloadingModel
        let finished = await Self.wait(
            for: build,
            upTo: isDownload ? Self.modelDownloadTimeout : Self.modelBuildTimeout
        )
        if Task.isCancelled { return CancellationError() }
        if finished {
            return whisperKit != nil ? nil : WhisperServiceError.modelNotLoaded
        }

        // A slow local build keeps running; the next take may find it done.
        guard isDownload else { return WhisperServiceError.modelBuildTimedOut }

        // A slow download is cancelled so it stops spending the connection.
        discardModel()
        if !Self.hasCompletedFirstLoad {
            AnalyticsService.shared.log(.modelDownload(tier: "base", result: "timeout"))
        }
        return WhisperServiceError.modelDownloadTimedOut
    }

    /// Forgets the model and any build in flight.
    private func discardModel() {
        modelGeneration += 1
        modelBuild?.cancel()
        modelBuild = nil
        whisperKit = nil
        isLoadingModel = false
        isDownloadingModel = false
    }

    /// Waits up to `seconds` for `task`. Returns false on timeout or
    /// cancellation without waiting further on a wedged task.
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

    /// Documents/huggingface, HubApi's default download base.
    private static var hubDownloadBase: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    /// The cached model folder, only if both encoder and decoder are present.
    /// An interrupted download can leave the encoder alone on disk.
    private static func cachedModelFolder(variantName: String) -> URL? {
        let folder = hubDownloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(variantName, isDirectory: true)

        let hasEncoder = ["AudioEncoder.mlmodelc", "AudioEncoder.mlpackage"].contains {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        let hasDecoder = ["TextDecoder.mlmodelc", "TextDecoder.mlpackage"].contains {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        return (hasEncoder && hasDecoder) ? folder : nil
    }

    /// Cached model → load with no network. `download: true` contacts the Hub
    /// before checking the cache and hangs on bad Wi-Fi.
    private static func makeConfig(variantName: String) -> WhisperKitConfig {
        if let localFolder = cachedModelFolder(variantName: variantName) {
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

    func transcribe(audioURL: URL, preferredTerms: [String] = []) async throws -> SpeechTranscriptionResult {
        // Outside the semaphore so the take awaits the build and raises it.
        if let failure = await modelForTranscription() {
            throw failure
        }

        await semaphore.wait()
        defer { semaphore.signal() }

        // Unloaded while waiting (local LLM claimed the memory).
        guard let whisperKit else {
            throw WhisperServiceError.modelNotLoaded
        }

        let heartbeat = DecodeHeartbeat()

        do {
            let biasPrompt = buildBiasPrompt(preferredTerms: preferredTerms)
            let encoded = whisperKit.tokenizer?.encode(text: biasPrompt).filter { $0 < 51865 } ?? []
            let promptTokens = Array(encoded.suffix(WhisperService.maxPromptTokens))

            let options = DecodingOptions(
                task: .transcribe,
                language: "en",
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 5,
                usePrefillPrompt: true,
                skipSpecialTokens: false,
                withoutTimestamps: false,
                wordTimestamps: true,
                promptTokens: promptTokens,
                suppressBlank: false,
                suppressTokens: nil,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                firstTokenLogProbThreshold: -1.5,
                // Silence trigger: a window over this that also fails
                // `logProbThreshold` is discarded whole. Lower drops more audio.
                noSpeechThreshold: 0.6
            )

            // Its own task, not a task-group child: a group waits for every
            // child before rethrowing, and a wedged decode never finishes.
            // No `chunkingStrategy`, so `.first` is the whole transcript.
            //
            // Runs on `WhisperDecodeExecutor`, not the cooperative pool (see that
            // type). The per-token callback rides a low-priority pool task a busy
            // pool starves; the segment callback runs inline once per window, so
            // the watchdog still sees the decode moving.
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
                        return !heartbeat.shouldAbort
                    }
                )
                guard let first = results.first else {
                    throw WhisperServiceError.noSpeechTranscriptionResult
                }
                return first
            }
            let result = try await Self.awaitDecode(decode, heartbeat: heartbeat, audioURL: audioURL)

            return await Task.detached(priority: .userInitiated) {
                Self.processWhisperResult(result)
            }.value

        } catch WhisperServiceError.transcriptionTimedOut {
            // The abandoned decode may still hold this instance; never share it.
            if self.whisperKit === whisperKit {
                discardModel()
            }
            throw WhisperServiceError.transcriptionTimedOut
        } catch is CancellationError {
            heartbeat.requestAbort()
            throw CancellationError()
        } catch {
            throw WhisperServiceError.transcriptionFailed(error)
        }
    }

    /// Races `decode` against a stall watchdog and returns as soon as either
    /// settles, without waiting on a decode wedged inside WhisperKit.
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

    /// WhisperKit result → timed words with fillers tagged. Pure; runs detached.
    nonisolated private static func processWhisperResult(_ result: WhisperTranscriptionResult) -> SpeechTranscriptionResult {
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
                // No word timings: spread the segment evenly across its words.
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

        rawTimings.sort { $0.start < $1.start }

        let normalizedTimings = WhisperService.normalizeTimings(rawTimings)
        let words = FillerDetectionPipeline.tagFillers(in: normalizedTimings)
        let duration = normalizedTimings.last?.end ?? 0

        return SpeechTranscriptionResult(
            text: result.text,
            words: words,
            duration: duration
        )
    }

    /// Gives each word a non-zero duration bounded by the next word's start
    /// and `maxWordDuration`. Starts are never shifted, so one bad end cannot
    /// push every later word. Expects input sorted by start.
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

    /// Waits out a decode in flight; a build in flight is dropped.
    func unloadModel() async {
        await semaphore.wait()
        defer { semaphore.signal() }
        discardModel()
    }
}

// MARK: - Concurrency helpers

/// Carries the non-Sendable WhisperKit into the decode task. `semaphore`
/// guarantees one decode per instance.
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

    /// Concurrent is load-bearing: the sampler's inner `Task` inherits this
    /// executor, and on a serial queue it would wait behind its own blocker.
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

/// Resumes a continuation with whichever racer finishes first and cancels
/// the rest. Locks stay in sync methods (NSLock is unavailable in async
/// contexts under Swift 6).
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

/// Decode liveness. WhisperKit calls the transcription callback once per
/// token from a background task. `shouldAbort` is how the watchdog actually
/// stops WhisperKit; cancelling the await alone never reaches it.
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

/// Counting semaphore for async critical sections. `signal()` is sync so it
/// works from `defer`.
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

    /// A timeout, not a bad transcript. Retrying Whisper would only wait again.
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
            if seen.insert(value.lowercased()).inserted {
                result.append(value)
            }
        }
        return result
    }
}
