import Foundation
import LlamaSwift

// MARK: - Types

enum LocalLLMError: LocalizedError {
    case modelNotDownloaded
    case downloadFailed(String)
    case failedToLoadModel
    case failedToCreateContext
    case generationFailed
    case insufficientMemory

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: return "Model not downloaded"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .failedToLoadModel: return "Failed to load LLM model"
        case .failedToCreateContext: return "Failed to create inference context"
        case .generationFailed: return "Text generation failed"
        case .insufficientMemory: return "Insufficient memory for LLM inference"
        }
    }
}

enum LocalModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case loading
    case ready
    case error(String)
}

// MARK: - LocalLLMService

@MainActor @Observable
final class LocalLLMService {

    // MARK: - Configuration

    static let modelFileName = "qwen2.5-0.5b-instruct-q4_k_m.gguf"
    static let modelDownloadURL: URL? = URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf")
    static let modelDisplayName = "Qwen 2.5 (0.5B)"
    static let approximateModelSize = "~400 MB"

    /// Minimum available memory (bytes) required before running inference.
    nonisolated private static let minimumMemoryForInference: UInt64 = 200 * 1024 * 1024 // 200 MB

    // MARK: - State

    private(set) var modelState: LocalModelState = .notDownloaded
    private(set) var downloadProgress: Double = 0

    var isModelReady: Bool {
        if case .ready = modelState { return true }
        return false
    }

    var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: Self.modelFilePath.path)
    }

    // MARK: - Private

    nonisolated private let engine = LLMInferenceEngine()
    private var downloadTask: Task<Void, Never>?
    private var unloadTimer: Timer?

    // MARK: - Model File Management

    private static var modelsDirectory: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("LocalLLM", isDirectory: true)
        }
        let dir = appSupport.appendingPathComponent("LocalLLM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var modelFilePath: URL {
        modelsDirectory.appendingPathComponent(modelFileName)
    }

    var modelFileSize: String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: Self.modelFilePath.path),
              let size = attrs[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // MARK: - Initialization

    init() {
        if isModelDownloaded {
            modelState = .downloaded
        }
    }

    // MARK: - Memory Check

    /// Returns true if sufficient memory is available for LLM inference.
    nonisolated static func hasSufficientMemory() -> Bool {
        let available = os_proc_available_memory()
        return available > minimumMemoryForInference
    }

    // MARK: - Download

    func downloadModel() async {
        guard !isModelDownloaded else {
            modelState = .downloaded
            return
        }

        guard let downloadURL = Self.modelDownloadURL else {
            modelState = .error("Invalid download URL")
            return
        }

        modelState = .downloading(progress: 0)
        downloadProgress = 0

        do {
            let tempURL = try await downloadWithProgress(url: downloadURL)

            // Move to final location
            let dest = Self.modelFilePath
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)

            modelState = .downloaded
            downloadProgress = 1.0
        } catch is CancellationError {
            modelState = .notDownloaded
            downloadProgress = 0
        } catch {
            modelState = .error("Download failed: \(error.localizedDescription)")
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        modelState = .notDownloaded
        downloadProgress = 0
    }

    // MARK: - Model Loading

    func loadModel() async {
        guard isModelDownloaded else {
            modelState = .notDownloaded
            return
        }

        modelState = .loading

        let path = Self.modelFilePath.path
        let success = await Task.detached(priority: .userInitiated) { [engine] in
            return engine.load(modelPath: path)
        }.value

        modelState = success ? .ready : .error("Failed to load model")
    }

    func unloadModel() {
        Task.detached { [engine] in engine.unload() }
        modelState = isModelDownloaded ? .downloaded : .notDownloaded
    }

    func deleteModel() {
        unloadModel()
        try? FileManager.default.removeItem(at: Self.modelFilePath)
        modelState = .notDownloaded
    }

    // MARK: - Auto-Unload Timer

    /// Resets the auto-unload timer. Call after each inference to reclaim memory after inactivity.
    private func resetUnloadTimer() {
        unloadTimer?.invalidate()
        unloadTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isModelReady {
                    print("[LocalLLM] Auto-unloading after 60s of inactivity")
                    self.unloadModel()
                }
            }
        }
    }

    // MARK: - Generation

    func generate(prompt: String, systemPrompt: String, maxTokens: Int = 256, temperature: Float = 0.3) async -> String? {
        guard engine.isLoaded else { return nil }

        // Pre-inference memory check
        guard Self.hasSufficientMemory() else {
            print("[LocalLLM] Insufficient memory for inference, skipping")
            return nil
        }

        let formatted = Self.formatChatPrompt(systemPrompt: systemPrompt, userPrompt: prompt)

        let result = await Task.detached(priority: .userInitiated) { [engine] in
            return engine.generate(prompt: formatted, maxTokens: maxTokens, temperature: temperature)
        }.value

        resetUnloadTimer()
        return result
    }

    // MARK: - Coherence Evaluation

    /// Evaluate speech coherence with prompt-aware scoring.
    /// When `promptText` is provided, the rubric emphasises prompt relevance.
    /// For free-practice (nil prompt), the rubric focuses on internal consistency.
    func evaluateCoherence(transcript: String, promptText: String? = nil) async -> CoherenceResult? {
        let truncated = String(transcript.prefix(800))

        let systemPrompt: String
        let userPrompt: String

        if let promptText, !promptText.isEmpty {
            // --- Prompt-based session ---
            systemPrompt = """
            You are a speech evaluator. Score this speech 0-100 based on four criteria:
            1. Prompt relevance — Does the speech address the given topic?
            2. Logical flow — Are ideas connected with transitions?
            3. Completeness — Does it have an opening, body, and conclusion?
            4. Fluency — Are sentences well-formed and clear?
            Reply EXACTLY in this format:
            SCORE: <number>
            TOPIC_FOCUS: <one sentence>
            LOGICAL_FLOW: <one sentence>
            REASON: <one sentence>
            Example:
            SCORE: 72
            TOPIC_FOCUS: The speaker mostly addressed the prompt but drifted mid-speech.
            LOGICAL_FLOW: Ideas were connected but lacked clear transitions.
            REASON: Good opening, weak conclusion.
            """

            userPrompt = "Prompt: \(promptText)\n\nSpeech transcript:\n\(truncated)"
        } else {
            // --- Free-practice session ---
            systemPrompt = """
            You are a speech evaluator. Score this speech 0-100 based on four criteria:
            1. Internal consistency — Do sentences relate to each other?
            2. Logical flow — Are ideas connected and ordered logically?
            3. Topical focus — Does the speaker stay on one thread or ramble?
            4. Fluency — Are sentences well-formed and clear?
            Reply EXACTLY in this format:
            SCORE: <number>
            TOPIC_FOCUS: <one sentence>
            LOGICAL_FLOW: <one sentence>
            REASON: <one sentence>
            Example:
            SCORE: 65
            TOPIC_FOCUS: The speaker stayed on one main idea throughout.
            LOGICAL_FLOW: Some jumps between ideas without transitions.
            REASON: Decent structure but the ending trailed off.
            """

            userPrompt = "Evaluate the coherence of this speech:\n\n\(truncated)"
        }

        // Near-deterministic temperature for reliable scoring
        guard let output = await generate(prompt: userPrompt, systemPrompt: systemPrompt, maxTokens: 64, temperature: 0.05) else {
            return nil
        }

        if let result = Self.parseCoherenceResult(output) {
            return result
        }

        // Fallback: extract just a number
        let numbers = output.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        let score = numbers.first(where: { $0 >= 0 && $0 <= 100 }) ?? 50
        return CoherenceResult(score: score, topicFocus: "", logicalFlow: "", reason: "")
    }

    // MARK: - Coaching Insights

    func generateCoachingInsight(
        from analysis: SpeechAnalysis,
        transcript: String
    ) async -> String? {
        let systemPrompt = """
        You are an expert public-speaking coach. Your job is to help speakers \
        improve their delivery, clarity, and confidence.
        Speech-science context you MUST use when relevant:
        - Optimal pace: 130-170 words per minute. Above 185 is rushing. Below 115 is dragging.
        - Filler words (um, uh, like, you know) above 5% of total words hurt credibility.
        - Strategic pauses of 1-2 seconds after key points improve audience retention.
        - Vocal variety (pitch + volume changes) keeps listeners engaged.
        Rules:
        - Give exactly 2-3 tips. Each tip MUST be a specific, actionable exercise.
        - Reference the speaker's actual numbers (WPM, filler count, scores).
        - Start each tip on a new line with •.
        - Keep each tip to 1-2 sentences. Be encouraging but honest.
        """

        let prompt = Self.buildCoachingPrompt(from: analysis, transcript: transcript)

        // Slightly higher temperature for more natural coaching language
        return await generate(prompt: prompt, systemPrompt: systemPrompt, maxTokens: 300, temperature: 0.4)
    }

    // MARK: - Transcript Quality Evaluation

    /// Evaluates transcript quality for structure and vocabulary richness.
    /// Returns a tuple of (structureScore, vocabularyScore) each 0-100, or nil on failure.
    func evaluateTranscriptQuality(transcript: String) async -> (structure: Int, vocabulary: Int)? {
        let truncated = String(transcript.prefix(800))

        let systemPrompt = """
        You are a speech evaluator. Rate this transcript on two dimensions, each 0-100:
        STRUCTURE: Are sentences complete? Is there a logical progression? \
        Are ideas organized (not rambling)?
        VOCABULARY: Is the word choice varied and specific? Does the speaker \
        use precise language rather than vague filler phrases?
        Reply EXACTLY in this format with no other text:
        STRUCTURE: <number>
        VOCABULARY: <number>
        Example:
        STRUCTURE: 68
        VOCABULARY: 55
        """

        let userPrompt = "Rate this speech transcript:\n\n\(truncated)"

        guard let output = await generate(prompt: userPrompt, systemPrompt: systemPrompt, maxTokens: 32, temperature: 0.1) else {
            return nil
        }

        return Self.parseTranscriptQualityResult(output)
    }

    // MARK: - Transcript Quality Parsing

    private static func parseTranscriptQualityResult(_ output: String) -> (structure: Int, vocabulary: Int)? {
        var structure: Int?
        var vocabulary: Int?

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("STRUCTURE:") {
                let value = trimmed.dropFirst(10).trimmingCharacters(in: .whitespaces)
                structure = Int(value.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "")
            } else if trimmed.uppercased().hasPrefix("VOCABULARY:") {
                let value = trimmed.dropFirst(11).trimmingCharacters(in: .whitespaces)
                vocabulary = Int(value.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "")
            }
        }

        guard let s = structure, let v = vocabulary else {
            // Fallback: try to extract any two numbers
            let nums = output.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .filter { $0 >= 0 && $0 <= 100 }
            guard nums.count >= 2 else { return nil }
            return (structure: nums[0], vocabulary: nums[1])
        }

        return (structure: max(0, min(100, s)), vocabulary: max(0, min(100, v)))
    }

    // MARK: - Chat Template (Qwen2.5)

    private static func formatChatPrompt(systemPrompt: String, userPrompt: String) -> String {
        "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(userPrompt)<|im_end|>\n<|im_start|>assistant\n"
    }

    // MARK: - Parsing Helpers

    private static func parseCoherenceResult(_ output: String) -> CoherenceResult? {
        let lines = output.components(separatedBy: "\n")
        var score: Int?
        var topicFocus = ""
        var logicalFlow = ""
        var reason = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("SCORE:") {
                let value = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                score = Int(value.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "")
            } else if trimmed.uppercased().hasPrefix("TOPIC_FOCUS:") {
                topicFocus = String(trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces))
            } else if trimmed.uppercased().hasPrefix("LOGICAL_FLOW:") {
                logicalFlow = String(trimmed.dropFirst(13).trimmingCharacters(in: .whitespaces))
            } else if trimmed.uppercased().hasPrefix("REASON:") {
                reason = String(trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces))
            }
        }

        guard let s = score else { return nil }
        return CoherenceResult(
            score: max(0, min(100, s)),
            topicFocus: topicFocus,
            logicalFlow: logicalFlow,
            reason: reason
        )
    }

    private static func buildCoachingPrompt(from analysis: SpeechAnalysis, transcript: String) -> String {
        let truncatedTranscript = String(transcript.prefix(500))

        var parts: [String] = []
        parts.append("Speech Performance Summary:")
        parts.append("- Overall Score: \(analysis.speechScore.overall)/100")
        parts.append("- Words Per Minute: \(Int(analysis.wordsPerMinute))")
        parts.append("- Total Words: \(analysis.totalWords)")
        parts.append("- Filler Words: \(analysis.totalFillerCount)")
        parts.append("- Pauses: \(analysis.pauseCount) (strategic: \(analysis.strategicPauseCount), hesitations: \(analysis.hesitationPauseCount))")

        let subscores = analysis.speechScore.subscores
        parts.append("- Clarity: \(subscores.clarity)/100")
        parts.append("- Pace: \(subscores.pace)/100")
        parts.append("- Filler Usage Score: \(subscores.fillerUsage)/100")
        parts.append("- Pause Quality: \(subscores.pauseQuality)/100")

        if let vv = subscores.vocalVariety {
            parts.append("- Vocal Variety: \(vv)/100")
        }
        if let vocab = subscores.vocabulary {
            parts.append("- Vocabulary: \(vocab)/100")
        }

        if !analysis.fillerWords.isEmpty {
            let topFillers = analysis.fillerWords.prefix(3).map { "\($0.word) (\($0.count)x)" }.joined(separator: ", ")
            parts.append("- Top filler words: \(topFillers)")
        }

        parts.append("")
        parts.append("Transcript excerpt:")
        parts.append(truncatedTranscript)
        parts.append("")
        parts.append("Based on this performance, provide 2-3 specific coaching tips to help this speaker improve.")

        return parts.joined(separator: "\n")
    }

    // MARK: - Download with Progress

    private func downloadWithProgress(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadProgressDelegate(
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = progress
                        self?.modelState = .downloading(progress: progress)
                    }
                },
                onComplete: { result in
                    continuation.resume(with: result)
                }
            )

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 3600 // 1 hour for large model download
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }
}

// MARK: - Download Progress Delegate

nonisolated private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let onProgress: @Sendable (Double) -> Void
    let onComplete: @Sendable (Result<URL, Error>) -> Void

    init(
        onProgress: @escaping @Sendable (Double) -> Void,
        onComplete: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Copy to a temp file we control (URLSession's file is deleted after this method returns)
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".gguf")
        do {
            try FileManager.default.copyItem(at: location, to: tempFile)
            onComplete(.success(tempFile))
        } catch {
            onComplete(.failure(error))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            onComplete(.failure(error))
        }
    }
}

// MARK: - LLM Inference Engine (off-MainActor)

/// Thread-safe wrapper around the llama.cpp C API. All heavy computation
/// runs on a background thread via the internal serial lock.
nonisolated final class LLMInferenceEngine: @unchecked Sendable {

    private var model: OpaquePointer?                       // llama_model *
    private var ctx: OpaquePointer?                         // llama_context *
    private var smpl: UnsafeMutablePointer<llama_sampler>?  // llama_sampler *
    private let lock = NSLock()

    /// Set to true to request early exit from the generate loop.
    private var _cancelled = false

    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return model != nil && ctx != nil
    }

    // MARK: - Cancellation

    func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
    }

    // MARK: - Load

    func load(modelPath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Clean up any previous state (including backend)
        freeResources()

        llama_backend_init()

        // Load model
        var mparams = llama_model_default_params()
        mparams.use_mmap = true
        let loadedModel = llama_model_load_from_file(modelPath, mparams)

        guard let loadedModel else {
            print("[LocalLLM] Failed to load model from: \(modelPath)")
            llama_backend_free()
            return false
        }
        model = loadedModel

        // Create context — 1024 tokens is sufficient for our short prompts
        var cparams = llama_context_default_params()
        cparams.n_ctx = 1024
        let threadCount = Int32(max(2, min(4, ProcessInfo.processInfo.processorCount - 2)))
        cparams.n_threads = threadCount
        cparams.n_threads_batch = threadCount

        let loadedCtx = llama_init_from_model(loadedModel, cparams)
        guard let loadedCtx else {
            print("[LocalLLM] Failed to create context")
            llama_model_free(loadedModel)
            model = nil
            llama_backend_free()
            return false
        }
        ctx = loadedCtx

        // Initialize sampler chain: top-k → top-p → temperature → dist
        let sparams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.3))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(0))
        smpl = chain

        print("[LocalLLM] Model loaded successfully. Threads: \(threadCount)")
        return true
    }

    // MARK: - Generate

    func generate(prompt: String, maxTokens: Int, temperature: Float = 0.3) -> String? {
        lock.lock()
        _cancelled = false

        guard let model, let ctx, let smpl else {
            lock.unlock()
            return nil
        }

        // 1. Tokenize the prompt
        let tokens = tokenize(text: prompt, model: model)
        guard !tokens.isEmpty else {
            print("[LocalLLM] Tokenization produced no tokens")
            lock.unlock()
            return nil
        }

        // 2. Clear KV cache for fresh generation
        llama_memory_clear(llama_get_memory(ctx), false)

        // 3. Decode prompt tokens
        var tokensCopy = tokens
        let promptBatch = llama_batch_get_one(&tokensCopy, Int32(tokens.count))
        guard llama_decode(ctx, promptBatch) == 0 else {
            print("[LocalLLM] Failed to decode prompt")
            lock.unlock()
            return nil
        }

        // 4. Generate tokens
        var result = ""

        for i in 0..<maxTokens {
            // Check cancellation every ~10 tokens
            if i % 10 == 0 && _cancelled {
                print("[LocalLLM] Generation cancelled")
                break
            }

            // Sample the next token
            let newToken = llama_sampler_sample(smpl, ctx, -1)

            // Check for end-of-generation
            if llama_vocab_is_eog(llama_model_get_vocab(model), newToken) { break }

            // Decode token to text
            if let piece = tokenToPiece(token: newToken, model: model) {
                result += piece
            }

            // Prepare and decode the new token
            var nextToken = newToken
            let nextBatch = llama_batch_get_one(&nextToken, 1)
            guard llama_decode(ctx, nextBatch) == 0 else {
                print("[LocalLLM] Failed to decode generated token")
                break
            }
        }

        // Reset sampler state for next generation
        llama_sampler_reset(smpl)
        lock.unlock()

        return result.isEmpty ? nil : result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Unload

    func unload() {
        lock.lock()
        defer { lock.unlock() }
        freeResources()
    }

    deinit {
        lock.lock()
        freeResources()
        lock.unlock()
    }

    // MARK: - Private Helpers

    private func freeResources() {
        if let smpl { llama_sampler_free(smpl) }
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
        smpl = nil
        ctx = nil
        model = nil
        llama_backend_free()
    }

    private func tokenize(text: String, model: OpaquePointer) -> [llama_token] {
        let utf8 = Array(text.utf8)
        // Estimate max tokens (roughly 1 token per 4 chars, with generous headroom)
        let maxTokens = Int32(utf8.count / 2 + 128)
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))

        let vocab = llama_model_get_vocab(model)
        let nTokens = llama_tokenize(
            vocab,
            text,
            Int32(utf8.count),
            &tokens,
            maxTokens,
            /* add_special */ true,
            /* parse_special */ true
        )

        guard nTokens > 0 else { return [] }
        return Array(tokens.prefix(Int(nTokens)))
    }

    private func tokenToPiece(token: llama_token, model: OpaquePointer) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(llama_model_get_vocab(model), token, &buf, Int32(buf.count), 0, false)
        guard n > 0 else { return nil }

        // Create a null-terminated buffer for String(cString:)
        var terminated = Array(buf.prefix(Int(n)))
        terminated.append(0)
        return String(cString: terminated)
    }
}
