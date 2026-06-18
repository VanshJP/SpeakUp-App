import Foundation
import LlamaSwift

// MARK: - Types

enum LocalModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case loading
    case ready
    case error(String)
}

enum ModelFamily: Equatable {
    case gemma
    case qwen
}

/// Typed errors surfaced from `LocalLLMService.loadModel()` so the UI can
/// distinguish recoverable problems (missing file → re-download) from
/// transient ones (insufficient RAM → close other apps and retry) from
/// hard llama backend failures.
enum LocalLLMError: LocalizedError {
    case fileNotFound(path: String)
    case insufficientMemory(availableBytes: Int, requiredBytes: Int)
    case backendInitFailed
    case modelInitFailed
    case contextInitFailed
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Model file not found at \(path). Re-download the model."
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
        /// Gemma 3 1B instruction-tuned — smallest viable profile. ~0.8 GB on
        /// disk, ~1 GB resident. Fits inside the iOS app budget on every
        /// supported device (iPhone XR / SE 2nd gen onward) without the
        /// increased-memory entitlement. Uses the standard
        /// `<start_of_turn>` Gemma chat template the engine already emits.
        case gemma3_1B
        case gemmaE2B
        case gemmaE4B
        /// Qwen 3 0.6B — ultra-light ChatML model. ~0.4 GB on disk, ~600 MB
        /// resident. Fits on every supported device with room to spare.
        case qwen3_0_6B
        /// Qwen 3 1.7B — compact ChatML model. ~1.1 GB on disk, ~1.5 GB
        /// resident. Good balance of quality and memory footprint.
        case qwen3_1_7B
        /// Qwen 3 4B — capable ChatML model. ~2.6 GB on disk, ~3.2 GB
        /// resident. Requires iPhone 12 Pro or later with increased-memory
        /// entitlement.
        case qwen3_4B

        var id: String { rawValue }

        var modelFamily: ModelFamily {
            switch self {
            case .gemma3_1B, .gemmaE2B, .gemmaE4B: return .gemma
            case .qwen3_0_6B, .qwen3_1_7B, .qwen3_4B: return .qwen
            }
        }

        var displayName: String {
            switch self {
            case .gemma3_1B:
                return "Gemma 3 1B"
            case .gemmaE2B:
                return "Gemma 4 E2B"
            case .gemmaE4B:
                return "Gemma 4 E4B"
            case .qwen3_0_6B:
                return "Qwen 3 0.6B"
            case .qwen3_1_7B:
                return "Qwen 3 1.7B"
            case .qwen3_4B:
                return "Qwen 3 4B"
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
            case .qwen3_0_6B:
                return "Qwen3-0.6B-Q4_K_M.gguf"
            case .qwen3_1_7B:
                return "Qwen3-1.7B-Q4_K_M.gguf"
            case .qwen3_4B:
                return "Qwen3-4B-Q4_K_M.gguf"
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
            case .qwen3_0_6B:
                return "~0.4 GB"
            case .qwen3_1_7B:
                return "~1.1 GB"
            case .qwen3_4B:
                return "~2.6 GB"
            }
        }

        /// Minimum *app-available* memory required to load this profile.
        ///
        /// iOS does not let an app allocate the device's total RAM — `jetsam`
        /// will kill the app at a much lower threshold reported by
        /// `os_proc_available_memory()`. Even on an 8 GB iPhone 15 Pro a
        /// foreground app typically gets ~3 GB before being killed (more with
        /// the `com.apple.developer.kernel.increased-memory-limit` entitlement,
        /// which this target enables).
        ///
        /// These values are tuned to the *real* app budget after the
        /// model weights, KV cache (Q8 quantized), activations and decode
        /// buffers are accounted for — not the on-disk model size.
        nonisolated var minimumRecommendedMemoryBytes: Int {
            switch self {
            case .gemma3_1B:
                // ~0.8 GB Q4_K_M weights + ~25 MB KV (Q4_0 @ 1024 ctx) +
                // ~150 MB activations / compute buffer + Swift/UIKit overhead.
                // Sized to fit inside the default app budget on iPhone XR / SE.
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
                // IQ2_M weights mmap'd (~2.5 GB hot pages on CPU backend) +
                // ~20 MB KV (Q4_0 @ 512 ctx) + activations. Tuned for iPhone 14
                // Pro and up with the increased-memory entitlement enabled.
                return 2_400 * 1024 * 1024
            case .qwen3_0_6B:
                // ~0.4 GB Q4_K_M weights + ~20 MB KV (Q4_0 @ 1024 ctx) +
                // ~120 MB activations. Fits on every supported device.
                return 600 * 1024 * 1024
            case .qwen3_1_7B:
                // ~1.1 GB Q4_K_M weights + ~25 MB KV (Q4_0 @ 1024 ctx) +
                // ~350 MB activations / compute buffer.
                return 1_500 * 1024 * 1024
            case .qwen3_4B:
                // ~2.6 GB Q4_K_M weights (hot mmap pages) + ~30 MB KV
                // (Q4_0 @ 512 ctx) + ~550 MB activations. Requires iPhone 12
                // Pro or later with the increased-memory entitlement.
                return 3_200 * 1024 * 1024
            }
        }

        /// llama_context `n_ctx`. Per-profile because the KV cache scales
        /// linearly with context size and the larger models have less headroom.
        /// 1024 tokens covers the full coaching system prompt + speech summary +
        /// transcript tail without truncation for the smaller models.
        nonisolated var contextTokenLimit: Int {
            switch self {
            case .gemma3_1B, .gemmaE2B, .qwen3_0_6B, .qwen3_1_7B:
                return 1024
            case .gemmaE4B, .qwen3_4B:
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
            case .qwen3_0_6B:
                guard let url = URL(string: "https://huggingface.co/bartowski/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf") else {
                    preconditionFailure("Invalid Qwen 3 0.6B local model URL")
                }
                return url
            case .qwen3_1_7B:
                guard let url = URL(string: "https://huggingface.co/bartowski/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf") else {
                    preconditionFailure("Invalid Qwen 3 1.7B local model URL")
                }
                return url
            case .qwen3_4B:
                guard let url = URL(string: "https://huggingface.co/bartowski/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf") else {
                    preconditionFailure("Invalid Qwen 3 4B local model URL")
                }
                return url
            }
        }
    }

    /// Minimum available memory (bytes) required before running inference.
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

    nonisolated private let engine = LLMInferenceEngine()
    @ObservationIgnored private var activeURLSessionTask: URLSessionDownloadTask?
    private var unloadTimer: Timer?
    @ObservationIgnored private let downloadDelegate = DownloadProgressDelegate()

    /// Background `URLSession` used for multi-GB GGUF downloads. The background
    /// configuration lets the system keep the transfer running when the user
    /// navigates away from the settings screen or backgrounds the app. The
    /// session is created lazily because instantiating a background session
    /// with a given identifier can only happen once per process.
    ///
    /// `@ObservationIgnored` is required: the `@Observable` macro rewrites
    /// stored properties into init-accessor computed pairs, which is
    /// incompatible with `lazy`.
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
    /// Host code (typically `LLMService` at app startup) should set this to a
    /// closure that unloads other heavy in-memory assets — primarily the
    /// Whisper model — so the LLM can claim the RAM. When `nil`, the
    /// `Notification.Name.localLLMWillLoad` notification is still posted so
    /// observers can react.
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
    }

    // MARK: - Memory Check

    /// Returns true if sufficient memory is available for LLM inference.
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

    /// Switches the active model profile.
    ///
    /// Returns `false` and leaves the active profile unchanged when a download
    /// is in progress — silently interrupting a multi-GB transfer would be
    /// hostile. Callers must surface this to the UI so the user can choose to
    /// invoke `cancelDownload()` explicitly.
    @discardableResult
    func selectProfile(_ profile: ModelProfile) -> Bool {
        guard selectedProfile != profile else { return true }

        if case .downloading = modelState {
            print("[LocalLLM] Refusing profile switch — download in progress for \(selectedProfile.rawValue)")
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
        // Guard against double-starts — the background session would happily
        // launch a second copy of the same transfer.
        if case .downloading = modelState { return }

        modelState = .downloading(progress: 0)
        downloadProgress = 0

        do {
            let activeProfile = selectedProfile
            let tempURL = try await downloadWithProgress(url: activeProfile.downloadURL)

            // Move to final location
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

        // Pre-check 1: file existence. Distinguishes a missing file (re-download
        // path) from a corrupt file (llama internal error path).
        guard FileManager.default.fileExists(atPath: path) else {
            modelState = .error(
                LocalLLMError.fileNotFound(path: path).errorDescription ?? "Model file missing"
            )
            return
        }

        modelState = .loading

        // Aggressive memory release: tell observers (WhisperService, etc.) to
        // unload before we claim multiple GB for llama context. Best-effort —
        // a missing host hook is not fatal, just makes the next memory check
        // more likely to fail.
        NotificationCenter.default.post(name: .localLLMWillLoad, object: self)
        if let handler = preloadCleanupHandler {
            await handler()
        }

        // Pre-check 2: memory headroom, measured *after* cleanup. The
        // pre-cleanup reading would frequently false-negative on devices that
        // had Whisper loaded.
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

    /// Resets the auto-unload timer. Call after each inference to reclaim memory after inactivity.
    private func resetUnloadTimer() {
        unloadTimer?.invalidate()
        unloadTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isModelReady {
                    print("[LocalLLM] Auto-unloading after 180s of inactivity")
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

        // Pre-inference memory check
        guard Self.hasSufficientMemory() else {
            print("[LocalLLM] Insufficient memory for inference, skipping")
            return nil
        }

        let formatted = Self.formatChatPrompt(systemPrompt: systemPrompt, userPrompt: prompt, profile: selectedProfile)

        let inferenceTask = Task.detached(priority: .userInitiated) { [engine] in
            return engine.generate(prompt: formatted, maxTokens: maxTokens, temperature: temperature)
        }

        let result = await withTaskCancellationHandler {
            await inferenceTask.value
        } onCancel: {
            // Ensure local inference exits promptly when callers cancel (e.g. user
            // cancels dictation formatting in the journal editor).
            inferenceTask.cancel()
            engine.cancel()
        }

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
            // --- Free-practice session ---
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
        You are a warm, encouraging public-speaking coach reviewing a session the speaker just finished. Your voice is that of a trusted mentor who has watched them work and wants to point out what actually shaped this delivery — confident, specific, kind, never preachy.

        How to think about the speech:
        1. Find the ONE pattern that most defined this delivery — pace, fillers, pauses, vocal variety, or structure.
        2. Connect that pattern to how the speech felt to a listener, not just to the metric.
        3. End with the next concrete exercise the speaker can try.

        Speech-science benchmarks to draw on when relevant:
        - Conversational pace: 130-170 WPM. Above 185 reads as rushing. Below 115 reads as dragging.
        - Fillers above ~5% of total words erode credibility.
        - 1-2 second pauses after key points improve audience retention.
        - Vocal variety (pitch + volume changes) keeps listeners engaged.

        Rules:
        - Reply with exactly 2-3 tips. No preamble, no closing line.
        - Start each tip on a new line with •.
        - Each tip: one short observation that ties the speaker's actual numbers (WPM, filler count, subscores) to how the speech landed, then one specific, doable exercise.
        - Weave the numbers into the prose — do not list them as bullet facts.
        - 1-2 sentences per tip. Encouraging, not condescending. No emojis.
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

    // MARK: - Chat Template

    private static func formatChatPrompt(systemPrompt: String, userPrompt: String, profile: ModelProfile) -> String {
        switch profile.modelFamily {
        case .gemma:
            // Gemma has no dedicated system role — system instructions are
            // prepended to the first user turn separated by a blank line. Turn
            // markers must match the official Gemma chat template exactly.
            // BOS is injected automatically by `llama_tokenize` with
            // `add_special: true`, so it is intentionally omitted here.
            switch profile {
            case .gemma3_1B:
                // Gemma 2 / 3 / 3n family template.
                return "<start_of_turn>user\n\(systemPrompt)\n\n\(userPrompt)<end_of_turn>\n<start_of_turn>model\n"
            default:
                // Gemma 4 template (HF `chat_template.jinja`): `<|turn>` opens
                // a turn, `<turn|>` closes it.
                return "<|turn>user\n\(systemPrompt)\n\n\(userPrompt)<turn|>\n<|turn>model\n"
            }
        case .qwen:
            // Qwen 2.5 / 3 use the ChatML format. The system role is a
            // first-class participant here, unlike Gemma. BOS is injected
            // automatically by `llama_tokenize` with `add_special: true`.
            // `/no_think` is appended to the user turn for Qwen 3 models to
            // disable the chain-of-thought reasoning mode — coaching insights
            // don't benefit from it and it wastes the token budget.
            let noThink = (profile == .qwen3_0_6B || profile == .qwen3_1_7B || profile == .qwen3_4B) ? " /no_think" : ""
            return "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(userPrompt)\(noThink)<|im_end|>\n<|im_start|>assistant\n"
        }
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
            // Re-target the long-lived background-session delegate at this
            // call's continuation. The delegate is one-shot per completion
            // handler so cancel/success/error all resolve exactly once.
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

/// Long-lived delegate attached to the background `URLSession`. Handlers are
/// re-targeted per call via `update(...)` so a single delegate instance can
/// serve consecutive downloads without leaking continuations across calls.
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

    /// One-shot: clears the stored handler so a subsequent error callback for
    /// the same task cannot double-resume the continuation.
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
        // Background sessions reclaim the temp file as soon as this callback
        // returns, so the copy must happen synchronously on this thread.
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

    private var model: OpaquePointer?                       // llama_model *
    private var ctx: OpaquePointer?                         // llama_context *
    private var smpl: UnsafeMutablePointer<llama_sampler>?  // llama_sampler *
    private let lock = NSLock()
    /// Context window in tokens. Set by `load(modelPath:contextSize:)` based on
    /// the active `ModelProfile`. The KV cache scales linearly with `n_ctx`,
    /// so the smaller Gemma 4 E4B / IQ2_M build is pinned to 512 while the
    /// E2B / 3 1B profiles use 1024 to fit full coaching system prompts
    /// without truncation. The `maxPromptTokens` calculation reads from this
    /// value so the budget tracks the configured window automatically.
    private(set) var contextTokenLimit: Int = 512
    /// Keep prompt decode chunks very small to stay below runtime `n_batch`
    /// defaults across llama builds. Some builds assert when a single decode
    /// batch is larger than the configured context batch size.
    private let promptDecodeChunkSize: Int32 = 8

    /// Cancellation flag protected by a *separate* lock so callers can request
    /// abort without contending with the heavyweight inference lock held by
    /// `generate`. Sharing the inference lock would defeat the purpose — the
    /// flag would only become observable *after* generation returned.
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

    /// Loads the model from `modelPath`. Throws a typed `LocalLLMError` so the
    /// caller can distinguish missing-file / OOM / llama-internal failures and
    /// surface the right recovery action. `contextSize` is the `n_ctx` value
    /// to use for this profile — caller picks based on memory budget.
    func load(modelPath: String, contextSize: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        // Clean up any previous state (including backend)
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
            print("[LocalLLM] Failed to load model from: \(modelPath)")
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
            print("[LocalLLM] Failed to create context")
            llama_model_free(loadedModel)
            model = nil
            llama_backend_free()
            throw LocalLLMError.contextInitFailed
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

        print("[LocalLLM] Model loaded. ctx=\(contextTokenLimit) gen_threads=\(genThreads) batch_threads=\(batchThreads)")
    }

    // MARK: - Generate

    func generate(prompt: String, maxTokens: Int, temperature: Float = 0.3) -> String? {
        lock.lock()
        resetCancellation()

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

        // 3. Decode prompt tokens. Reserve space for the generation window
        // plus a 16-token safety margin so the final assistant token never
        // overruns `n_ctx`. When the prompt is longer than the remaining
        // budget, keep the most recent tail — the active user request and
        // assistant tag survive truncation, which matters far more than the
        // leading system prompt for chat-template-formatted input.
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
                print("[LocalLLM] Failed to decode prompt chunk")
                lock.unlock()
                return nil
            }

            decodeCursor += chunkCount
        }

        // 4. Generate tokens
        var result = ""

        for i in 0..<maxTokens {
            // Check cancellation every ~8 tokens. Tightened from 10 to keep
            // the worst-case post-cancel latency under ~1s on CPU-bound runs
            // so a memory-pressure abort completes before jetsam fires.
            if i % 8 == 0 && isCancelled {
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
