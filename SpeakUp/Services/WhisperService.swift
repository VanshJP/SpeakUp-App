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
    var modelLoadProgress: Double = 0
    var transcriptionProgress: Double = 0
    var errorMessage: String?

    // WhisperKit instance
    private var whisperKit: WhisperKit?

    // Filler word prompt to encourage capturing hesitations
    // This prompt biases the model toward transcribing filler sounds
    // The transcript style with hesitations helps Whisper recognize and output them
    private let fillerPrompt = "Um, uh, er, ah, hmm, mm, mhm, uh-huh, like, you know, I mean, so, basically. The speaker says um and uh frequently. Um, so, like, you know, I was, uh, thinking about, um, the thing."

    // MARK: - Initialization

    /// Load the Whisper model (call this early, e.g., on app launch)
    /// - Parameter modelVariant: Model variant to use (tiny, base, small, medium, large-v3)
    func loadModel(modelVariant: String = "base") async {
        // Allow re-initialization if model exists but isn't fully loaded
        guard whisperKit == nil || !isModelLoaded else { return }

        do {
            modelLoadProgress = 0.1
            errorMessage = nil

            // Configure WhisperKit
            let config = WhisperKitConfig(
                model: "openai_whisper-\(modelVariant)",
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: true,
                download: true
            )

            whisperKit = try await WhisperKit(config)

            modelLoadProgress = 1.0
            isModelLoaded = true
        } catch {
            errorMessage = "Failed to load Whisper model: \(error.localizedDescription)"
            isModelLoaded = false
            modelLoadProgress = 0
        }
    }

    // MARK: - Transcription

    /// Transcribe audio file with filler word detection and optional preferred terms.
    func transcribe(audioURL: URL, preferredTerms: [String] = []) async throws -> SpeechTranscriptionResult {
        // Load model if not loaded
        if whisperKit == nil {
            await loadModel()
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

        do {
            // Tokenize prompt to condition the model toward fillers + user dictionary words.
            let biasPrompt = buildBiasPrompt(preferredTerms: preferredTerms)
            let promptTokens = whisperKit.tokenizer?.encode(text: biasPrompt).filter { $0 < 51865 } ?? []
            
            // Configure decoding options for filler word capture
            let options = DecodingOptions(
                task: .transcribe,
                language: "en",
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 3,
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
                noSpeechThreshold: 0.4  // Lower threshold to capture more speech including hesitations
            )

            // Transcribe the audio
            let results = try await whisperKit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )

            guard let result = results.first else {
                throw WhisperServiceError.noSpeechTranscriptionResult
            }

            transcriptionProgress = 1.0

            // Process the WhisperKit result into our format
            return processWhisperResult(result)

        } catch {
            throw WhisperServiceError.transcriptionFailed(error)
        }
    }

    private func buildBiasPrompt(preferredTerms: [String]) -> String {
        let cleanedTerms = preferredTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()

        guard !cleanedTerms.isEmpty else { return fillerPrompt }
        let dictionaryLine = "Preferred names and terms: \(cleanedTerms.joined(separator: ", "))."
        return "\(fillerPrompt) \(dictionaryLine)"
    }

    /// Process WhisperKit result into our SpeechTranscriptionResult format with filler detection
    private func processWhisperResult(_ result: WhisperTranscriptionResult) -> SpeechTranscriptionResult {
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

        // Stabilize timings for downstream playback word-highlighting.
        // Whisper partial segments can occasionally emit tiny overlaps or zero-length words.
        var normalizedTimings: [RawWordTiming] = []
        normalizedTimings.reserveCapacity(rawTimings.count)
        var lastEnd: TimeInterval = 0
        for timing in rawTimings {
            let clampedStart = max(lastEnd, timing.start)
            let clampedEnd = max(clampedStart + 0.01, timing.end)
            normalizedTimings.append(
                RawWordTiming(
                    word: timing.word,
                    start: clampedStart,
                    end: clampedEnd,
                    confidence: timing.confidence
                )
            )
            lastEnd = clampedEnd
        }

        // Run unified filler detection pipeline
        let words = FillerDetectionPipeline.tagFillers(in: normalizedTimings)
        let duration = normalizedTimings.last?.end ?? 0

        return SpeechTranscriptionResult(
            text: result.text,
            words: words,
            duration: duration
        )
    }

    // MARK: - Model Management

    /// Available Whisper models (smaller = faster, larger = more accurate)
    static let availableModels: [(variant: String, size: String, description: String)] = [
        ("tiny", "~75 MB", "Fastest, lower accuracy"),
        ("base", "~140 MB", "Good balance (recommended)"),
        ("small", "~460 MB", "Better accuracy, slower"),
        ("medium", "~1.5 GB", "High accuracy, requires more memory"),
        ("large-v3", "~3 GB", "Best accuracy, slowest")
    ]

    /// Unload model to free memory
    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
        modelLoadProgress = 0
    }
}

// MARK: - Errors

enum WhisperServiceError: LocalizedError {
    case modelNotLoaded
    case noSpeechTranscriptionResult
    case transcriptionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded. Please wait for the model to download."
        case .noSpeechTranscriptionResult:
            return "No transcription result was produced."
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
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
