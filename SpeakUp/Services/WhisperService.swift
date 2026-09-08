import AVFoundation
import Foundation
import WhisperKit

// WhisperKit exports TranscriptionResult - we use our own SpeechTranscriptionResult
// to avoid naming collisions
typealias WhisperTranscriptionResult = TranscriptionResult

@Observable
class WhisperService {
    var isTranscribing = false
    var isModelLoaded = false
    private(set) var isLoadingModel = false
    private(set) var isDownloadingModel = false
    var modelLoadProgress: Double = 0
    var transcriptionProgress: Double = 0
    var errorMessage: String?

    private var whisperKit: WhisperKit?

    /// Serializes loadModel / transcribe / unloadModel. WhisperKit is not
    /// reentrant — two recordings processed concurrently (coordinator jobs for
    /// different recordingIDs) would race one shared instance: torn-down model
    private let semaphore = AsyncSemaphore(value: 1)

    private let fillerPrompt = "Um, uh, er, ah, hmm, mm, mhm, uh-huh, like, you know, I mean, so, basically. The speaker says um and uh frequently. Um, so, like, you know, I was, uh, thinking about, um, the thing."

    /// Whisper's decoder prompt context is capped at 224 tokens. Staying comfortably under
    /// the cap prevents the decoder from hanging on oversized prompts when the user has a
    /// large vocab/dictation bank.
    private static let maxPromptTokens = 200

    /// Maximum number of user-supplied bias terms to include in the prompt line, so the
    /// dictionary clause can never dominate the prompt budget even before tokenization.
    private static let maxBiasTerms = 25

    nonisolated private static let maxWordDuration: TimeInterval = 3.0

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

    func loadModel(modelVariant: String = "base") async {
        await semaphore.wait()
        defer { semaphore.signal() }
        await loadModelLocked(modelVariant: modelVariant)
    }

    private static let firstLoadCompletedKey = "whisper.firstLoadCompleted.v1"

    static var hasCompletedFirstLoad: Bool {
        UserDefaults.standard.bool(forKey: firstLoadCompletedKey)
    }

    private func loadModelLocked(modelVariant: String = "base") async {
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

    private static var hubDownloadBase: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    private static func cachedModelFolder(variantName: String) -> URL? {
        let folder = hubDownloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(variantName, isDirectory: true)

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

    private static func loadWhisperKitWithDownloadTimeout(
        config: WhisperKitConfig,
        seconds: TimeInterval
    ) async throws -> WhisperKit {
        nonisolated final class Box: @unchecked Sendable {
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
            try await group.next()
            group.cancelAll()
        }
        guard let kit = box.value else {
            throw WhisperServiceError.modelDownloadTimedOut
        }
        return kit
    }

    // MARK: - Transcription

    func transcribe(audioURL: URL, preferredTerms: [String] = []) async throws -> SpeechTranscriptionResult {
        await semaphore.wait()
        defer { semaphore.signal() }

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
                noSpeechThreshold: 0.6
            )

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

            return await Task.detached(priority: .userInitiated) {
                Self.processWhisperResult(result)
            }.value

        } catch is CancellationError {
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

    func unloadModel() async {
        await semaphore.wait()
        defer { semaphore.signal() }
        whisperKit = nil
        isModelLoaded = false
        modelLoadProgress = 0
    }
}

/// Liveness signal for a running decode.
/// task, once per decoded token, so this must be thread-safe and must not touch
/// alone never reaches WhisperKit's internals, which would leave a zombie
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
