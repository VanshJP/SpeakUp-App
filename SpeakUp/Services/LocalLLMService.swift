import Foundation
import LlamaSwift
import os

// MARK: - Types

enum LocalModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case loading
    case ready
    case error(String)
}

nonisolated enum LocalLLMError: LocalizedError, Sendable {
    case fileNotFound(path: String)
    case downloadFailed(status: Int)
    case insufficientMemory(availableBytes: Int, requiredBytes: Int)
    case backendInitFailed
    case modelInitFailed
    case contextInitFailed
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Model file not found at \(path). Re-download the model."
        case .downloadFailed(let status):
            return "The model download failed (HTTP \(status)). Check your connection and try again."
        case .insufficientMemory(let available, let required):
            let avail = ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .memory)
            let req = ByteCountFormatter.string(fromByteCount: Int64(required), countStyle: .memory)
            return "Insufficient RAM (\(avail) available, \(req) recommended). Close other apps and try again."
        case .backendInitFailed:
            return "Internal Llama error: failed to initialize backend."
        case .modelInitFailed:
            return "Internal Llama error: failed to read model weights."
        case .contextInitFailed:
            return "Internal Llama error: failed to create inference context."
        case .unknown(let detail):
            return "Internal Llama error: \(detail)"
        }
    }
}

extension Notification.Name {
    /// Posted by `LocalLLMService` immediately before it initializes the heavy
    /// `LLMInferenceEngine`. Listeners (e.g. `WhisperService`) should unload
    /// their own large in-memory models so the LLM can claim the RAM.
    static let localLLMWillLoad = Notification.Name("LocalLLM.willLoadHeavyModel")
}

// MARK: - LocalLLMService

@MainActor @Observable
final class LocalLLMService {

    // MARK: - Configuration

    enum ModelProfile: String, CaseIterable, Identifiable {
        case gemma3_1B
        case gemmaE2B
        case gemmaE4B

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .gemma3_1B:
                return "Gemma 3 1B"
            case .gemmaE2B:
                return "Gemma 4 E2B"
            case .gemmaE4B:
                return "Gemma 4 E4B"
            }
        }

        var modelFileName: String {
            switch self {
            case .gemma3_1B:
                return "google_gemma-3-1b-it-Q4_K_M.gguf"
            case .gemmaE2B:
                return "google_gemma-4-E2B-it-Q4_K_M.gguf"
            case .gemmaE4B:
                // IQ2_M is the smallest published quant for E4B (~3.96 GB on
                // disk). Required to keep peak resident inside the iOS process
                // budget on 6 GB devices like iPhone 14 Pro; larger quants
                // (Q3_K_S 4.7 GB, Q4_K_M 5.41 GB) push the Metal weight buffer
                // past the `.warning` memory-pressure threshold.
                return "google_gemma-4-E4B-it-IQ2_M.gguf"
            }
        }

        var approximateModelSize: String {
            switch self {
            case .gemma3_1B:
                return "~0.8 GB"
            case .gemmaE2B:
                return "~3.5 GB"
            case .gemmaE4B:
                return "~4 GB"
            }
        }

        /// Minimum *app-available* memory required to load this profile.
        /// iOS does not let an app allocate the device's total RAM — `jetsam`
        nonisolated var minimumRecommendedMemoryBytes: Int {
            switch self {
            case .gemma3_1B:
                return 900 * 1024 * 1024
            case .gemmaE2B:
                // ~1.6 GB Q4_K_M weights (hot mmap pages) + ~30 MB KV
                // (Q4_0 @ 1024 ctx) + ~200 MB activations / compute buffer +
                // Swift/UIKit overhead. Peak resident on iPhone 14 Pro after
                // Whisper unload sits around 2.0 GB; this leaves ~300 MB of
                // headroom before iOS fires `.warning` memory pressure on a
                // 4 GB increased-memory-entitlement budget.
                return 2_100 * 1024 * 1024
            case .gemmaE4B:
                return 2_400 * 1024 * 1024
            }
        }

        nonisolated var contextTokenLimit: Int {
            switch self {
            case .gemma3_1B, .gemmaE2B:
                return 1024
            case .gemmaE4B:
                return 512
            }
        }

        var downloadURL: URL {
            switch self {
            case .gemma3_1B:
                guard let url = URL(string: "https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf") else {
                    preconditionFailure("Invalid Gemma 3 1B local model URL")
                }
                return url
            case .gemmaE2B:
                guard let url = URL(string: "https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q4_K_M.gguf") else {
                    preconditionFailure("Invalid Gemma 4 E2B local model URL")
                }
                return url
            case .gemmaE4B:
                guard let url = URL(string: "https://huggingface.co/bartowski/google_gemma-4-E4B-it-GGUF/resolve/main/google_gemma-4-E4B-it-IQ2_M.gguf") else {
                    preconditionFailure("Invalid Gemma 4 E4B local model URL")
                }
                return url
            }
        }
    }

    nonisolated private static let minimumMemoryForInference: Int = 350 * 1024 * 1024 // 350 MB
    private static let selectedProfileDefaultsKey = "local_llm_selected_profile"

    // MARK: - State

    private(set) var modelState: LocalModelState = .notDownloaded
    private(set) var downloadProgress: Double = 0
    private(set) var selectedProfile: ModelProfile

    var isModelReady: Bool {
        if case .ready = modelState { return true }
        return false
    }

    var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: Self.modelFilePath(for: selectedProfile).path)
    }

    var modelDisplayName: String { selectedProfile.displayName }
    var approximateModelSize: String { selectedProfile.approximateModelSize }
    var availableProfiles: [ModelProfile] { ModelProfile.allCases }
    var recommendedProfile: ModelProfile {
        Self.recommendedProfile(forAvailableMemory: Int(clamping: os_proc_available_memory()))
    }

    // MARK: - Private

    // Sendable — reachable from the MainActor service and the off-main orphan sweep alike.
    nonisolated private static let logger = Logger.app("LocalLLM")
    nonisolated private let engine = LLMInferenceEngine()
    @ObservationIgnored private var activeURLSessionTask: URLSessionDownloadTask?
    private var unloadTimer: Timer?
    @ObservationIgnored private let downloadDelegate = DownloadProgressDelegate()

    /// Background `URLSession` used for multi-GB GGUF downloads. The background
    /// configuration lets the system keep the transfer running when the user
    /// navigates away from the settings screen or backgrounds the app. The
    @ObservationIgnored
    private lazy var backgroundSession: URLSession = {
        let identifier = "com.vansh.SpeakUp.LocalLLM.download"
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = false
        config.allowsExpensiveNetworkAccess = false
        config.allowsConstrainedNetworkAccess = false
        config.timeoutIntervalForResource = 7200 // 2 hours for very large files
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: downloadDelegate, delegateQueue: nil)
    }()

    /// Optional hook awaited just before the `LLMInferenceEngine` is created.
    /// closure that unloads other heavy in-memory assets — primarily the
    @ObservationIgnored
    var preloadCleanupHandler: (@MainActor @Sendable () async -> Void)?

    // MARK: - Model File Management

    private static var modelsDirectory: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("LocalLLM", isDirectory: true)
        }
        let dir = appSupport.appendingPathComponent("LocalLLM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func modelFilePath(for profile: ModelProfile) -> URL {
        modelsDirectory.appendingPathComponent(profile.modelFileName)
    }

    var modelFileSize: String? {
        let path = Self.modelFilePath(for: selectedProfile).path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // MARK: - Initialization

    init() {
        if let storedRaw = UserDefaults.standard.string(forKey: Self.selectedProfileDefaultsKey),
           let storedProfile = ModelProfile(rawValue: storedRaw) {
            selectedProfile = storedProfile
        } else {
            selectedProfile = Self.recommendedProfile(forAvailableMemory: Int(clamping: os_proc_available_memory()))
        }

        if isModelDownloaded {
            modelState = .downloaded
        }

        let directory = Self.modelsDirectory
        let known = Set(ModelProfile.allCases.map(\.modelFileName))
        Task.detached(priority: .utility) {
            Self.deleteOrphanedModelFiles(in: directory, keeping: known)
        }
    }

    nonisolated private static func deleteOrphanedModelFiles(in directory: URL, keeping known: Set<String>) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in contents where !known.contains(file.lastPathComponent) {
            Self.logger.debug("Removing orphaned model file: \(file.lastPathComponent, privacy: .public)")
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Memory Check

    nonisolated static func hasSufficientMemory() -> Bool {
        let available = Int(clamping: os_proc_available_memory())
        return available > minimumMemoryForInference
    }

    nonisolated static func recommendedProfile(forAvailableMemory memoryBytes: Int) -> ModelProfile {
        if memoryBytes >= ModelProfile.gemmaE4B.minimumRecommendedMemoryBytes {
            return .gemmaE4B
        }
        if memoryBytes >= ModelProfile.gemmaE2B.minimumRecommendedMemoryBytes {
            return .gemmaE2B
        }
        return .gemma3_1B
    }

    @discardableResult
    func selectProfile(_ profile: ModelProfile) -> Bool {
        guard selectedProfile != profile else { return true }

        if case .downloading = modelState {
            Self.logger.debug("Refusing profile switch, download in progress for \(self.selectedProfile.rawValue, privacy: .public)")
            return false
        }
        if isModelReady {
            unloadModel()
        }

        selectedProfile = profile
        UserDefaults.standard.set(profile.rawValue, forKey: Self.selectedProfileDefaultsKey)
        downloadProgress = 0
        modelState = isModelDownloaded ? .downloaded : .notDownloaded
        return true
    }

    // MARK: - Download

    func downloadModel() async {
        guard !isModelDownloaded else {
            modelState = .downloaded
            return
        }
        if case .downloading = modelState { return }

        modelState = .downloading(progress: 0)
        downloadProgress = 0

        do {
            let activeProfile = selectedProfile
            let tempURL = try await downloadWithProgress(url: activeProfile.downloadURL)

            let dest = Self.modelFilePath(for: activeProfile)
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
            // User-initiated cancels surface as NSURLErrorCancelled — treat as
            // a non-error reset rather than a failure state.
            if (error as NSError).code == NSURLErrorCancelled {
                modelState = .notDownloaded
                downloadProgress = 0
            } else {
                modelState = .error("Download failed: \(error.localizedDescription)")
            }
        }
    }

    /// Cancels the active background download. Must only be invoked in response
    /// to explicit user intent (e.g. the Cancel button in `AIModelSettingsView`).
    /// View lifecycle, profile switches, and tab navigation must not call this.
    func cancelDownload() {
        activeURLSessionTask?.cancel()
        activeURLSessionTask = nil
        modelState = .notDownloaded
        downloadProgress = 0
    }

    // MARK: - Model Loading

    func loadModel() async {
        guard isModelDownloaded else {
            modelState = .notDownloaded
            return
        }

        let path = Self.modelFilePath(for: selectedProfile).path

        guard FileManager.default.fileExists(atPath: path) else {
            modelState = .error(
                LocalLLMError.fileNotFound(path: path).errorDescription ?? "Model file missing"
            )
            return
        }

        modelState = .loading

        NotificationCenter.default.post(name: .localLLMWillLoad, object: self)
        if let handler = preloadCleanupHandler {
            await handler()
        }

        let availableAfterCleanup = Int(clamping: os_proc_available_memory())
        let required = selectedProfile.minimumRecommendedMemoryBytes
        if availableAfterCleanup < required {
            modelState = .error(
                LocalLLMError.insufficientMemory(
                    availableBytes: availableAfterCleanup,
                    requiredBytes: required
                ).errorDescription ?? "Insufficient memory"
            )
            return
        }

        do {
            try await Task.detached(priority: .userInitiated) { [engine, selectedProfile] in
                try engine.load(modelPath: path, contextSize: selectedProfile.contextTokenLimit)
            }.value
            modelState = .ready
        } catch let error as LocalLLMError {
            modelState = .error(error.errorDescription ?? "Failed to load model")
        } catch {
            modelState = .error(
                LocalLLMError.unknown(error.localizedDescription).errorDescription ?? "Failed to load model"
            )
        }
    }

    func unloadModel() {
        Task.detached { [engine] in engine.unload() }
        modelState = isModelDownloaded ? .downloaded : .notDownloaded
    }

    /// Requests the engine abort any in-flight `generate` call as quickly as
    /// possible. Safe to call from any actor — does not block on the engine's
    /// inference lock. Intended for memory-pressure handlers so a long
    /// coaching-insight generation cannot keep the model resident past a
    /// `.warning` / `.critical` event and trip `jetsam`.
    nonisolated func cancelInflight() {
        engine.cancel()
    }

    func deleteModel() {
        unloadModel()
        try? FileManager.default.removeItem(at: Self.modelFilePath(for: selectedProfile))
        modelState = .notDownloaded
    }

    // MARK: - Auto-Unload Timer

    private func resetUnloadTimer() {
        unloadTimer?.invalidate()
        unloadTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isModelReady {
                    Self.logger.debug("Auto-unloading after 180s of inactivity")
                    self.unloadModel()
                }
            }
        }
    }

    // MARK: - Generation

    func generate(prompt: String, systemPrompt: String, maxTokens: Int = 256, temperature: Float = 0.3) async -> String? {
        // Check `modelState` (MainActor-local enum) rather than `engine.isLoaded`,
        // which would take the inference NSLock and could stall the main thread
        // if a back-to-back generation is still holding it.
        guard isModelReady else { return nil }

        guard Self.hasSufficientMemory() else {
            Self.logger.error("Insufficient memory for inference, skipping")
            return nil
        }

        let formatted = Self.formatChatPrompt(systemPrompt: systemPrompt, userPrompt: prompt, profile: selectedProfile)

        let inferenceTask = Task.detached(priority: .userInitiated) { [engine] in
            return engine.generate(prompt: formatted, maxTokens: maxTokens, temperature: temperature)
        }

        let result = await withTaskCancellationHandler {
            await inferenceTask.value
        } onCancel: {
            inferenceTask.cancel()
            engine.cancel()
        }

        resetUnloadTimer()
        return result
    }

    // MARK: - Coherence Evaluation

    func evaluateCoherence(transcript: String, promptText: String? = nil) async -> CoherenceResult? {
        let truncated = String(transcript.prefix(800))

        let systemPrompt: String
        let userPrompt: String

        if let promptText, !promptText.isEmpty {
            systemPrompt = """
            You are a strict speech evaluator. Score a spoken response 0-100 using this rubric.

            PENALIZE (drag the score down):
            - Rambling: tangents, repetition without payoff, sentences that wander off the prompt
            - Disjointed jumps between unrelated ideas with no signposting
            - Speech that ignores or contradicts the prompt
            - Run-on thoughts with no clear arc

            REWARD (push the score up):
            - Explicit logical transitions ("first", "however", "as a result", "to summarize")
            - Clear opening → body → conclusion structure
            - Tight, sustained relevance to the prompt
            - Each sentence advancing the argument

            Reply EXACTLY in this format, one line each, no extra text:
            SCORE: <0-100 integer>
            TOPIC_FOCUS: <one sentence on how well the speech addressed the prompt>
            LOGICAL_FLOW: <one sentence on transitions and structure>
            REASON: <one sentence naming the single biggest driver of the score>

            Example:
            SCORE: 72
            TOPIC_FOCUS: The speaker addressed the prompt clearly but drifted mid-speech.
            LOGICAL_FLOW: Ideas connected but lacked explicit transitions between points.
            REASON: Strong opening was undercut by a rambling middle section.
            """

            userPrompt = "Prompt: \(promptText)\n\nSpeech transcript:\n\(truncated)"
        } else {
            systemPrompt = """
            You are a strict speech evaluator. Score a spoken response 0-100 using this rubric.

            PENALIZE (drag the score down):
            - Rambling: tangents, repetition without payoff, sentences that drift between unrelated threads
            - Disjointed jumps with no signposting
            - Run-on thoughts that never resolve
            - Filler-heavy delivery that obscures the point

            REWARD (push the score up):
            - Explicit logical transitions ("first", "however", "as a result", "to summarize")
            - One sustained thread or argument across the speech
            - Each sentence advancing the previous one
            - A discernible arc from opening to conclusion

            Reply EXACTLY in this format, one line each, no extra text:
            SCORE: <0-100 integer>
            TOPIC_FOCUS: <one sentence on whether the speaker held a single thread>
            LOGICAL_FLOW: <one sentence on transitions and structure>
            REASON: <one sentence naming the single biggest driver of the score>

            Example:
            SCORE: 65
            TOPIC_FOCUS: The speaker held one main idea but revisited it without adding depth.
            LOGICAL_FLOW: Some jumps between sub-points without explicit transitions.
            REASON: Decent structure overall, but the ending trailed off without resolving the thread.
            """

            userPrompt = "Evaluate the coherence of this speech:\n\n\(truncated)"
        }

        guard let output = await generate(prompt: userPrompt, systemPrompt: systemPrompt, maxTokens: 64, temperature: 0.05) else {
            return nil
        }

        return CoherenceResult(parsing: output)
    }

    // MARK: - Coaching Insights

    func generateCoachingInsight(
        from analysis: SpeechAnalysis,
        transcript: String,
        context: CoachingContext = CoachingContext()
    ) async -> String? {
        let smallWindow = selectedProfile.contextTokenLimit <= 512
        let budget = smallWindow ? 300 : CoachingPrompt.localTranscriptBudget

        let prompt = CoachingPrompt.user(
            analysis: analysis,
            transcript: transcript,
            context: context,
            transcriptBudget: budget
        )

        return await generate(
            prompt: prompt,
            systemPrompt: CoachingPrompt.system(context: context, compact: smallWindow),
            maxTokens: 300,
            temperature: 0.4
        )
    }

    // MARK: - Transcript Quality Evaluation

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
            let nums = output.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
                .filter { $0 >= 0 && $0 <= 100 }
            guard nums.count >= 2 else { return nil }
            return (structure: nums[0], vocabulary: nums[1])
        }

        return (structure: max(0, min(100, s)), vocabulary: max(0, min(100, v)))
    }

    // MARK: - Chat Template

    private static func formatChatPrompt(systemPrompt: String, userPrompt: String, profile: ModelProfile) -> String {
        // Gemma has no dedicated system role — system instructions are
        // prepended to the first user turn separated by a blank line. Turn
        // markers must match the official Gemma chat template exactly.
        // BOS is injected automatically by `llama_tokenize` with
        // `add_special: true`, so it is intentionally omitted here.
        switch profile {
        case .gemma3_1B:
            return "<start_of_turn>user\n\(systemPrompt)\n\n\(userPrompt)<end_of_turn>\n<start_of_turn>model\n"
        case .gemmaE2B, .gemmaE4B:
            return "<|turn>user\n\(systemPrompt)\n\n\(userPrompt)<turn|>\n<|turn>model\n"
        }
    }

    // MARK: - Parsing Helpers


    // MARK: - Download with Progress

    private func downloadWithProgress(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            downloadDelegate.update(
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = progress
                        self?.modelState = .downloading(progress: progress)
                    }
                },
                onComplete: { [weak self] result in
                    Task { @MainActor [weak self] in
                        self?.activeURLSessionTask = nil
                    }
                    continuation.resume(with: result)
                }
            )

            let task = backgroundSession.downloadTask(with: url)
            activeURLSessionTask = task
            task.resume()
        }
    }
}

// MARK: - Download Progress Delegate

nonisolated private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias ProgressHandler = @Sendable (Double) -> Void
    typealias CompletionHandler = @Sendable (Result<URL, Error>) -> Void

    private let lock = NSLock()
    private var _onProgress: ProgressHandler?
    private var _onComplete: CompletionHandler?

    func update(onProgress: @escaping ProgressHandler, onComplete: @escaping CompletionHandler) {
        lock.lock()
        _onProgress = onProgress
        _onComplete = onComplete
        lock.unlock()
    }

    private func progressHandler() -> ProgressHandler? {
        lock.lock()
        defer { lock.unlock() }
        return _onProgress
    }

    private func takeCompletionHandler() -> CompletionHandler? {
        lock.lock()
        defer { lock.unlock() }
        let handler = _onComplete
        _onComplete = nil
        return handler
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
        progressHandler()?(progress)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
            !(200...299).contains(http.statusCode)
        {
            takeCompletionHandler()?(.failure(LocalLLMError.downloadFailed(status: http.statusCode)))
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".gguf")
        do {
            try FileManager.default.copyItem(at: location, to: tempFile)
            takeCompletionHandler()?(.success(tempFile))
        } catch {
            takeCompletionHandler()?(.failure(error))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            takeCompletionHandler()?(.failure(error))
        }
    }
}

// MARK: - LLM Inference Engine (off-MainActor)

/// Thread-safe wrapper around the llama.cpp C API. All heavy computation
/// runs on a background thread via the internal serial lock.
nonisolated final class LLMInferenceEngine: @unchecked Sendable {

    // Same category as the service logger — one stream for both layers.
    nonisolated private static let logger = Logger.app("LocalLLM")

    private var model: OpaquePointer?                       // llama_model *
    private var ctx: OpaquePointer?                         // llama_context *
    private var smpl: UnsafeMutablePointer<llama_sampler>?  // llama_sampler *
    private let lock = NSLock()
    private(set) var contextTokenLimit: Int = 512
    private let promptDecodeChunkSize: Int32 = 8

    private let cancelLock = NSLock()
    private var _cancelled = false

    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return model != nil && ctx != nil
    }

    // MARK: - Cancellation

    /// Requests early exit from the in-flight `generate` call. Non-blocking —
    /// only contends on a tiny dedicated lock, never the inference lock — so
    /// it stays responsive even during multi-second token decode loops.
    func cancel() {
        cancelLock.lock()
        _cancelled = true
        cancelLock.unlock()
    }

    private var isCancelled: Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return _cancelled
    }

    private func resetCancellation() {
        cancelLock.lock()
        _cancelled = false
        cancelLock.unlock()
    }

    // MARK: - Load

    func load(modelPath: String, contextSize: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        freeResources()
        contextTokenLimit = contextSize

        llama_backend_init()

        // Load model. mmap lets iOS evict cold weight pages under pressure;
        // mlock would pin them and trigger jetsam, so we leave it disabled.
        //
        // `n_gpu_layers = 0` forces the CPU backend even on Apple Silicon. On
        // iOS the Metal backend allocates a wired `MTLBuffer` for weight
        // tensors — `ggml_metal_log_allocated_size: 3072 MiB ...` in the load
        // log — and that buffer is non-pageable. Under the per-process budget
        // (~4 GB on iPhone 14 Pro with the increased-memory entitlement),
        // that wired allocation alone trips `.warning` memory pressure. The
        // CPU backend serves weights from the mmap'd file, so iOS can evict
        // cold pages under pressure without killing the app. Trade-off:
        // decode is ~2-3× slower per token than Metal, acceptable for
        // ≤300-token coaching insights.
        //
        // `check_tensors = false` skips a per-tensor integrity scan that
        // touches every weight page during load — a guaranteed way to fault
        // the entire 1.6 GB Q4_K_M E2B file into resident memory before
        // generation even starts. Disabling it lets mmap stay cold and keeps
        // the load-time RSS spike inside the iPhone 14 Pro budget.
        // Leave `use_extra_bufts` at its default (true) — it enables the
        // ggml-cpu-aarch64 weight repacking that gives ~2-3× decode throughput
        // on Apple ARM CPUs. Disabling it stalls coaching generation long
        // enough to look like a UI hang on iPhone 14 Pro.
        var mparams = llama_model_default_params()
        mparams.use_mmap = true
        mparams.use_mlock = false
        mparams.check_tensors = false
        mparams.n_gpu_layers = 0
        let loadedModel = llama_model_load_from_file(modelPath, mparams)

        guard let loadedModel else {
            Self.logger.error("Failed to load model from: \(modelPath, privacy: .private(mask: .hash))")
            llama_backend_free()
            throw LocalLLMError.modelInitFailed
        }
        model = loadedModel

        // Create context. Memory-saving tweaks for iOS:
        //   • n_ctx                 — per-profile (1024 for E2B / 3 1B, 512
        //                             for E4B); KV cache scales linearly.
        //   • type_k/type_v = Q4_0  — quarter of F16 KV cache size; quality
        //                             cost is small at short contexts and is
        //                             essential to keep the larger Gemma 4
        //                             quants inside the iPhone 14 Pro process
        //                             budget. Requires flash_attn.
        //   • flash_attn = ENABLED  — lower attention memory + faster decode.
        //   • n_batch = 64          — bounds the logical decode-buffer
        //                             allocation; we only ever submit chunks
        //                             of `promptDecodeChunkSize` (8) tokens,
        //                             so anything larger is wasted compute
        //                             scratch held resident for the whole run.
        //   • n_ubatch = 16         — physical batch ≤ logical batch; 16 still
        //                             covers single chunks with 2× headroom.
        //   • op_offload = false    — no device backend to offload to on the
        //                             CPU path; suppresses an unused
        //                             scheduler allocation.
        //   • swa_full = false      — Gemma 3 / 4 use a sliding-window cache;
        //                             this caps the KV buffer at the window
        //                             size instead of full `n_ctx`, saving
        //                             ~40-60% of KV memory on long contexts.
        //   • kv_unified = true     — single-sequence inference, so the
        //                             unified buffer is both smaller and
        //                             faster than per-sequence allocation.
        //   • no_perf = true        — skip llama's internal perf timers; we
        //                             don't surface them and they keep a
        //                             little extra state on the hot path.
        //   • n_threads = 2         — Apple ARM generation is memory-bandwidth
        //                             bound; using both P-cores and E-cores
        //                             adds L2 pressure with little throughput
        //                             gain and accelerates thermal throttling
        //                             on the 10-30s coaching-insight runs.
        //                             Two P-core threads is the sweet spot.
        //   • n_threads_batch = 4   — prompt processing is compute-bound;
        //                             give it the full P+E core budget.
        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(contextTokenLimit)
        cparams.n_batch = 64
        cparams.n_ubatch = 16
        cparams.type_k = GGML_TYPE_Q4_0
        cparams.type_v = GGML_TYPE_Q4_0
        cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
        cparams.offload_kqv = false
        cparams.op_offload = false
        cparams.swa_full = false
        cparams.kv_unified = true
        cparams.no_perf = true
        let genThreads: Int32 = 2
        let batchThreads = Int32(max(2, min(4, ProcessInfo.processInfo.processorCount - 2)))
        cparams.n_threads = genThreads
        cparams.n_threads_batch = batchThreads

        let loadedCtx = llama_init_from_model(loadedModel, cparams)
        guard let loadedCtx else {
            Self.logger.error("Failed to create context")
            llama_model_free(loadedModel)
            model = nil
            llama_backend_free()
            throw LocalLLMError.contextInitFailed
        }
        ctx = loadedCtx

        let sparams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.3))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(0))
        smpl = chain

        Self.logger.debug("Model loaded. ctx=\(self.contextTokenLimit) gen_threads=\(genThreads) batch_threads=\(batchThreads)")
    }

    // MARK: - Generate

    func generate(prompt: String, maxTokens: Int, temperature: Float = 0.3) -> String? {
        lock.lock()
        resetCancellation()

        guard let model, let ctx, let smpl else {
            lock.unlock()
            return nil
        }

        let tokens = tokenize(text: prompt, model: model)
        guard !tokens.isEmpty else {
            Self.logger.error("Tokenization produced no tokens")
            lock.unlock()
            return nil
        }

        llama_memory_clear(llama_get_memory(ctx), false)

        let reservedForGeneration = max(64, min(maxTokens, 320))
        let maxPromptTokens = max(128, contextTokenLimit - reservedForGeneration - 16)
        var boundedTokens = tokens
        if boundedTokens.count > maxPromptTokens {
            boundedTokens = Array(boundedTokens.suffix(maxPromptTokens))
        }

        var decodeCursor = 0
        while decodeCursor < boundedTokens.count {
            if isCancelled {
                llama_sampler_reset(smpl)
                lock.unlock()
                return nil
            }

            let remaining = boundedTokens.count - decodeCursor
            let chunkCount = min(Int(promptDecodeChunkSize), remaining)
            var chunk = Array(boundedTokens[decodeCursor..<(decodeCursor + chunkCount)])
            let promptBatch = llama_batch_get_one(&chunk, Int32(chunkCount))

            guard llama_decode(ctx, promptBatch) == 0 else {
                Self.logger.error("Failed to decode prompt chunk")
                lock.unlock()
                return nil
            }

            decodeCursor += chunkCount
        }

        var result = ""

        for i in 0..<maxTokens {
            // Check cancellation every ~8 tokens. Tightened from 10 to keep
            // the worst-case post-cancel latency under ~1s on CPU-bound runs
            // so a memory-pressure abort completes before jetsam fires.
            if i % 8 == 0 && isCancelled {
                Self.logger.debug("Generation cancelled")
                break
            }

            let newToken = llama_sampler_sample(smpl, ctx, -1)

            if llama_vocab_is_eog(llama_model_get_vocab(model), newToken) { break }

            if let piece = tokenToPiece(token: newToken, model: model) {
                result += piece
            }

            var nextToken = newToken
            let nextBatch = llama_batch_get_one(&nextToken, 1)
            guard llama_decode(ctx, nextBatch) == 0 else {
                Self.logger.error("Failed to decode generated token")
                break
            }
        }

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

        var terminated = Array(buf.prefix(Int(n)))
        terminated.append(0)
        return String(cString: terminated)
    }
}
