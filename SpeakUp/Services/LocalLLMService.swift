import Foundation
import llama

// MARK: - Types

enum LocalLLMError: LocalizedError {
    case modelNotDownloaded
    case downloadFailed(String)
    case failedToLoadModel
    case failedToCreateContext
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: return "Model not downloaded"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .failedToLoadModel: return "Failed to load LLM model"
        case .failedToCreateContext: return "Failed to create inference context"
        case .generationFailed: return "Text generation failed"
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

@Observable
final class LocalLLMService {

    // MARK: - Configuration

    static let modelFileName = "qwen2.5-0.5b-instruct-q4_k_m.gguf"
    static let modelDownloadURL = URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf")!
    static let modelDisplayName = "Qwen 2.5 (0.5B)"
    static let approximateModelSize = "~400 MB"

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

    // MARK: - Model File Management

    private static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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

    // MARK: - Download

    func downloadModel() async {
        guard !isModelDownloaded else {
            modelState = .downloaded
            return
        }

        modelState = .downloading(progress: 0)
        downloadProgress = 0

        do {
            let tempURL = try await downloadWithProgress(url: Self.modelDownloadURL)

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

    // MARK: - Generation

    func generate(prompt: String, systemPrompt: String, maxTokens: Int = 256) async -> String? {
        guard engine.isLoaded else { return nil }

        let formatted = Self.formatChatPrompt(systemPrompt: systemPrompt, userPrompt: prompt)

        return await Task.detached(priority: .userInitiated) { [engine] in
            return engine.generate(prompt: formatted, maxTokens: maxTokens)
        }.value
    }

    // MARK: - Coherence Evaluation

    func evaluateCoherence(transcript: String) async -> CoherenceResult? {
        let truncated = String(transcript.prefix(800))

        let systemPrompt = """
        You are a speech coherence evaluator. Score the coherence of the given transcript \
        on a 0-100 scale. Output EXACTLY in this format with no other text:
        SCORE: <number>
        TOPIC_FOCUS: <one sentence>
        LOGICAL_FLOW: <one sentence>
        REASON: <one sentence>
        """

        let userPrompt = "Evaluate the coherence of this speech transcript:\n\n\(truncated)"

        guard let output = await generate(prompt: userPrompt, systemPrompt: systemPrompt) else {
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
        You are a supportive speech coach. Analyze the speaker's performance and provide \
        2-3 specific, actionable coaching tips. Be encouraging but honest. Focus on the \
        most impactful areas for improvement. Keep each tip to 1-2 sentences. \
        Format: Start each tip on a new line with a bullet point (•).
        """

        let prompt = Self.buildCoachingPrompt(from: analysis, transcript: transcript)

        return await generate(prompt: prompt, systemPrompt: systemPrompt, maxTokens: 350)
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

    private var model: OpaquePointer?   // llama_model *
    private var ctx: OpaquePointer?     // llama_context *
    private var smpl: OpaquePointer?    // llama_sampler *
    private let lock = NSLock()

    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return model != nil && ctx != nil
    }

    // MARK: - Load

    func load(modelPath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Clean up any previous state
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

        // Create context
        var cparams = llama_context_default_params()
        cparams.n_ctx = 2048
        let threadCount = UInt32(max(2, min(4, ProcessInfo.processInfo.processorCount - 2)))
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

    func generate(prompt: String, maxTokens: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let model, let ctx, let smpl else { return nil }

        // 1. Tokenize the prompt
        let tokens = tokenize(text: prompt, model: model)
        guard !tokens.isEmpty else {
            print("[LocalLLM] Tokenization produced no tokens")
            return nil
        }

        // 2. Clear KV cache for fresh generation
        llama_kv_cache_clear(ctx)

        // 3. Decode prompt tokens
        var tokensCopy = tokens
        let promptBatch = llama_batch_get_one(&tokensCopy, Int32(tokens.count))
        guard llama_decode(ctx, promptBatch) == 0 else {
            print("[LocalLLM] Failed to decode prompt")
            return nil
        }

        // 4. Generate tokens
        var result = ""

        for _ in 0..<maxTokens {
            // Sample the next token
            let newToken = llama_sampler_sample(smpl, ctx, -1)

            // Check for end-of-generation
            if llama_token_is_eog(model, newToken) { break }

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

        return result.isEmpty ? nil : result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Unload

    func unload() {
        lock.lock()
        defer { lock.unlock() }
        freeResources()
    }

    deinit {
        freeResources()
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

        let nTokens = llama_tokenize(
            model,
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
        let n = llama_token_to_piece(model, token, &buf, Int32(buf.count), 0, false)
        guard n > 0 else { return nil }

        // Create a null-terminated buffer for String(cString:)
        var terminated = Array(buf.prefix(Int(n)))
        terminated.append(0)
        return String(cString: terminated)
    }
}
