import Foundation
import FoundationModels
import os.log

// MARK: - Types

struct CoherenceResult: Sendable {
    let score: Int
    let topicFocus: String
    let logicalFlow: String
    let reason: String
}

enum LLMBackend: Equatable, Sendable {
    case appleIntelligence
    case localLLM
    case none
}

// MARK: - LLMService

@MainActor @Observable
final class LLMService {
    var isGenerating = false

    /// Local on-device LLM for devices without Apple Intelligence.
    let localLLM = LocalLLMService()

    /// When `true`, route inference to the local Gemma model even on devices
    /// where Apple Intelligence is available. Persisted across launches so the
    /// preference survives backgrounding. Defaults to `false` (Apple
    /// Intelligence preferred), matching the original behaviour.
    var preferLocalLLM: Bool {
        didSet {
            UserDefaults.standard.set(preferLocalLLM, forKey: Self.preferLocalDefaultsKey)
        }
    }

    private static let preferLocalDefaultsKey = "llm_prefer_local"

    nonisolated private let memoryPressureSource: DispatchSourceMemoryPressure

    init() {
        preferLocalLLM = UserDefaults.standard.bool(forKey: Self.preferLocalDefaultsKey)
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        setupMemoryPressureMonitor()
    }

    deinit {
        memoryPressureSource.cancel()
    }

    // MARK: - Memory Pressure

    private func setupMemoryPressureMonitor() {
        memoryPressureSource.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.memoryPressureSource.data
            let isCritical = event.contains(.critical)
            // Read the preference directly from UserDefaults to avoid hopping
            // to the main actor just to check a Bool.
            let preferLocal = UserDefaults.standard.bool(forKey: Self.preferLocalDefaultsKey)
            // When the user has explicitly opted into the local Gemma path
            // (hackathon / on-device demo), large models intentionally sit
            // near the per-process budget. `.warning` fires routinely in that
            // band; treating it as a mandate to unload defeats the feature.
            // Only react to `.critical` in that mode — iOS will jetsam the
            // process anyway if real exhaustion follows.
            if preferLocal && !isCritical {
                print("[LLMService] Memory pressure .warning ignored, preferLocalLLM is on")
                return
            }
            print("[LLMService] Memory pressure (\(isCritical ? "critical" : "warning")), unloading local LLM")
            // Abort any in-flight generation first. `unloadModel` schedules a
            // detached `engine.unload()` that has to take the inference lock,
            // which `generate` holds for the full token-decode loop — without
            // a prior cancel, unload can sit blocked for 10+ seconds while
            // jetsam fires. `cancelInflight` is non-blocking and lets the
            // generate loop break at its next per-8-token cancellation poll.
            self.localLLM.cancelInflight()
            Task { @MainActor in
                self.localLLM.unloadModel()
            }
        }
        memoryPressureSource.resume()
    }

    // MARK: - Availability

    var appleIntelligenceAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// True when any LLM backend is ready to generate.
    var isAvailable: Bool {
        appleIntelligenceAvailable || localLLM.isModelReady
    }

    /// The backend that will be used for the next generation request.
    /// Honors `preferLocalLLM` so the user can force the on-device Gemma path
    /// even when Apple Intelligence is available.
    var activeBackend: LLMBackend {
        if preferLocalLLM && localLLM.isModelReady { return .localLLM }
        if appleIntelligenceAvailable { return .appleIntelligence }
        if localLLM.isModelReady { return .localLLM }
        return .none
    }

    /// Whether the next inference request should route to Apple Intelligence
    /// first. False when the user has explicitly opted into the local model and
    /// the local model is loaded.
    private var prefersAppleIntelligence: Bool {
        guard appleIntelligenceAvailable else { return false }
        if preferLocalLLM && localLLM.isModelReady { return false }
        return true
    }

    // MARK: - Local Model Management

    /// Download and immediately load the local model.
    func setupLocalModel() async {
        await localLLM.downloadModel()
        await localLLM.loadModel()
    }

    /// Loads the local model if it's downloaded but not yet loaded.
    func loadLocalModelIfNeeded() async {
        // Load when (a) Apple Intelligence is unavailable, OR (b) the user has
        // opted to prefer the local model — in both cases the local engine
        // needs to be ready before the next inference call.
        let shouldLoad = (!appleIntelligenceAvailable || preferLocalLLM)
            && localLLM.isModelDownloaded
            && !localLLM.isModelReady
        guard shouldLoad else { return }
        // Avoid re-loading if already loading
        if case .loading = localLLM.modelState { return }
        await localLLM.loadModel()
    }

    // MARK: - General-Purpose Generation

    /// Public general-purpose text generation using the best available backend.
    /// Falls back from Apple Intelligence to the local model if the AI call
    /// returns nil (e.g. simulator, feature disabled).
    func generateText(prompt: String, systemPrompt: String) async -> String? {
        if prefersAppleIntelligence {
            if let result = await generateWithAppleIntelligence(prompt: prompt, systemPrompt: systemPrompt) {
                return result
            }
        }
        if localLLM.isModelReady {
            return await localLLM.generate(prompt: prompt, systemPrompt: systemPrompt)
        }
        return nil
    }

    // MARK: - Dictation Formatting

    /// Cleans up raw dictated speech into lightly-formatted Markdown for the story editor.
    /// The editor parses the returned Markdown into rich text (bold, italic, headings, lists,
    /// paragraphs). Preserves the speaker's wording, voice, and meaning. Falls back to the
    /// input on failure. The returned string is Markdown, not plain text.
    ///
    /// IMPORTANT: local llama backends are more fragile with this long formatting prompt and
    /// can trigger low-level batch assertions on some devices/builds. To keep dictation stable,
    /// only Apple Intelligence is used for formatting; local model callers get passthrough text.
    func formatDictation(_ raw: String) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isAvailable else { return raw }
        guard appleIntelligenceAvailable else { return raw }

        let systemPrompt = """
        You format raw dictated speech into lightly-styled Markdown for a personal journal/story entry. \
        The input is a verbatim transcript of someone speaking out loud. Your output will be parsed into rich text, \
        so it MUST use Markdown syntax, not plain paragraphs. Keep the speaker's exact voice, wording, tense, \
        and meaning intact. The goal is to make the raw transcript feel like a written entry.

        === CLEAN THE TEXT ===
        - Add sentence punctuation (. ? !) and internal punctuation (, ; :, "…" ').
        - Capitalize sentence starts, the pronoun "I", and proper nouns (names, places, brands, titles).
        - Remove filler words with no meaning: "um", "uh", "er", "ah", "hmm", and filler uses of "like", "you know", "I mean", "sort of", "kind of", "basically", "literally".
        - Remove false starts and stuttered repeats. "I, I went to" → "I went to". "so so yesterday" → "so yesterday".
        - Collapse spoken self-corrections to the corrected version. "I went to the store, I mean the market" → "I went to the market".
        - Fix clearly-wrong homophone/transcription slips only when unambiguous (e.g. "their" vs "there"). When in doubt, leave the words alone.

        === APPLY MARKDOWN FORMATTING ===
        Use formatting SPARINGLY and only when the speaker's content actually calls for it. Default is plain paragraphs. Never format everything.

        Paragraphs:
        - Separate paragraphs with a blank line (two newlines). Break whenever the topic, scene, time, place, or speaker shifts. Long dictation MUST become multiple paragraphs, never return one wall of text.

        Headings (`# Title`, `## Subheading`):
        - Only if the speaker explicitly announces a title or section header ("Chapter one: the beginning", "Part two", "Section titled Morning Routine"). Strip the announcer words and keep the title on its own heading line.
        - Do NOT invent headings. Most entries will have zero headings.

        Bold (`**word**`):
        - The input is a text transcript, so you cannot hear vocal tone. Infer emphasis from TEXTUAL cues only:
          1. Repetition: "really really important" → "**really** important" (collapse the doubled word).
          2. Explicit intensifiers: "seriously", "literally" (when used for emphasis, not as filler), "I mean", "I want to emphasize", "the key point is", "the main thing is", bold the phrase they modify, not the intensifier itself.
          3. Exclamation sentences with a clear emphatic target: "That was **huge**!"
          4. Self-labeled takeaways: "the takeaway was **trust your team**", "the lesson is **start small**".
        - Cap at roughly 1–3 short bolded phrases per entry. Never bold whole sentences, never bold every noun, never bold just for decoration.

        Italic (`*word*`):
        - Inner thoughts or self-talk: "I thought, *this can't be happening*", "in my head I was like, *just breathe*".
        - Titles of books, movies, shows, songs, podcasts, albums: *The Great Gatsby*, *Inception*.
        - Foreign words or phrases: *je ne sais quoi*.
        - Do NOT italicize for generic emphasis, that's what bold is for.

        Bullet list (`- item` per line):
        - Only when the speaker verbally enumerates 2+ discrete items with no ordering ("I need to buy eggs, milk, and bread" → three bullets: `- eggs`, `- milk`, `- bread`). Keep each item short.

        Numbered list (`1. item`, `2. item`):
        - Use when the speaker announces an enumerated sequence with ANY of these spoken ordinal forms:
          • Cardinal numbers: "one, ... two, ... three, ..."  → `1. ...`, `2. ...`, `3. ...`
          • Ordinal numbers: "first, ... second, ... third, ..."
          • Step form: "step one, ... step two, ..."
          • Number form: "number one, ... number two, ..."
        - CRITICAL: strip the spoken ordinal word (and any trailing comma) from the item text. Do not leave it in.
        - Worked example. Input: "one, I like to play guitar. two, I enjoy cooking. three, I read books."
          Output:
          1. I like to play guitar.
          2. I enjoy cooking.
          3. I read books.
        - Worked example. Input: "first I woke up, then second I made coffee, and third I went for a walk."
          Output:
          1. I woke up.
          2. I made coffee.
          3. I went for a walk.
        - Each numbered item goes on its own line with a single newline between items (no blank line between list items). Put a blank line BEFORE the list and AFTER the list to separate it from surrounding paragraphs.

        === HARD RULES ===
        - DO NOT paraphrase, rewrite, summarize, shorten, or "improve" the writing style.
        - DO NOT add new sentences, facts, transitions, or commentary the speaker did not say.
        - DO NOT change the speaker's tense, slang, informal phrasing, or point of view.
        - DO NOT wrap the output in code fences, quotes, or a preface like "Here is".
        - DO NOT use Markdown features not listed above (no links, images, tables, blockquotes, horizontal rules, inline code).
        - Output ONLY the Markdown body. Nothing else.
        """
        let userPrompt = "Format this dictated text as Markdown:\n\n\(trimmed)"

        guard let output = await generateText(prompt: userPrompt, systemPrompt: systemPrompt) else {
            return raw
        }

        var cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip accidental code fences if the model wrapped its reply.
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Sanity check: length must be in sensible range — otherwise model hallucinated.
        // Floor is loose (1/3) because filler/false-start removal can legitimately shrink text.
        // Ceiling is 2.5x because added Markdown punctuation (**, -, #) inflates character count.
        let inputLen = trimmed.count
        let outputLen = cleaned.count
        guard outputLen > 0,
              outputLen >= inputLen / 3,
              Double(outputLen) <= Double(inputLen) * 2.5 else {
            return raw
        }
        return cleaned
    }

    // MARK: - Coherence Evaluation

    func evaluateCoherence(transcript: String, promptText: String? = nil) async -> CoherenceResult? {
        if prefersAppleIntelligence {
            if let result = await evaluateCoherenceWithAppleIntelligence(transcript: transcript, promptText: promptText) {
                return result
            }
        }

        if localLLM.isModelReady {
            return await localLLM.evaluateCoherence(transcript: transcript, promptText: promptText)
        }

        return nil
    }

    // MARK: - Coaching Tips

    /// - Parameter context: the speaker's pace target, focus, and this
    ///   session's quotable moments. Without it the model can only paraphrase
    ///   the metrics back; with it, it can coach.
    func generateCoachingInsight(
        from analysis: SpeechAnalysis,
        transcript: String,
        context: CoachingContext = CoachingContext()
    ) async -> String? {
        isGenerating = true
        defer { isGenerating = false }

        if prefersAppleIntelligence {
            if let raw = await generateCoachingWithAppleIntelligence(
                analysis: analysis,
                transcript: transcript,
                context: context
            ) {
                return sanitizeCoachingInsight(raw, analysis: analysis, transcript: transcript, context: context)
            }
            // Apple Intelligence returned nil — try the local model rather than
            // surfacing nothing to the user.
        }

        if localLLM.isModelReady {
            if let raw = await localLLM.generateCoachingInsight(
                from: analysis,
                transcript: transcript,
                context: context
            ) {
                return sanitizeCoachingInsight(raw, analysis: analysis, transcript: transcript, context: context)
            }
            return nil
        }

        return nil
    }

    // MARK: - Transcript Quality Evaluation

    func evaluateTranscriptQuality(transcript: String) async -> (structure: Int, vocabulary: Int)? {
        if prefersAppleIntelligence {
            if let result = await evaluateTranscriptQualityWithAppleIntelligence(transcript: transcript) {
                return result
            }
        }

        // Fall back to local LLM
        if localLLM.isModelReady {
            return await localLLM.evaluateTranscriptQuality(transcript: transcript)
        }

        return nil
    }

    // MARK: - Apple Intelligence Backend

    private func evaluateCoherenceWithAppleIntelligence(transcript: String, promptText: String? = nil) async -> CoherenceResult? {
        let truncated = String(transcript.prefix(800))

        let systemPrompt: String
        let userPrompt: String

        if let promptText, !promptText.isEmpty {
            systemPrompt = """
            You are a speech evaluator. Score this speech 0-100 based on:
            1. Prompt relevance, Does the speech address the given topic?
            2. Logical flow, Are ideas connected with transitions?
            3. Completeness, Does it have an opening, body, and conclusion?
            4. Fluency, Are sentences well-formed and clear?
            Output EXACTLY in this format with no other text:
            SCORE: <number>
            TOPIC_FOCUS: <one sentence>
            LOGICAL_FLOW: <one sentence>
            REASON: <one sentence>
            """
            userPrompt = "Prompt: \(promptText)\n\nSpeech transcript:\n\(truncated)"
        } else {
            systemPrompt = """
            You are a speech coherence evaluator. Score this speech 0-100 based on:
            1. Internal consistency, Do sentences relate to each other?
            2. Logical flow, Are ideas connected and ordered logically?
            3. Topical focus, Does the speaker stay on one thread or ramble?
            4. Fluency, Are sentences well-formed and clear?
            Output EXACTLY in this format with no other text:
            SCORE: <number>
            TOPIC_FOCUS: <one sentence>
            LOGICAL_FLOW: <one sentence>
            REASON: <one sentence>
            """
            userPrompt = "Evaluate the coherence of this speech transcript:\n\n\(truncated)"
        }

        guard let output = await generateWithAppleIntelligence(prompt: userPrompt, systemPrompt: systemPrompt) else {
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

    private func evaluateTranscriptQualityWithAppleIntelligence(transcript: String) async -> (structure: Int, vocabulary: Int)? {
        let truncated = String(transcript.prefix(800))

        let systemPrompt = """
        You are a speech evaluator. Rate this transcript on two dimensions, each 0-100:
        STRUCTURE: Are sentences complete? Is there logical progression? Are ideas organized?
        VOCABULARY: Is word choice varied and specific? Does the speaker use precise language?
        Output EXACTLY in this format with no other text:
        STRUCTURE: <number>
        VOCABULARY: <number>
        """

        let userPrompt = "Rate this speech transcript:\n\n\(truncated)"

        guard let output = await generateWithAppleIntelligence(prompt: userPrompt, systemPrompt: systemPrompt) else {
            return nil
        }

        // Parse STRUCTURE and VOCABULARY lines
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

        guard let s = structure, let v = vocabulary else { return nil }
        return (structure: max(0, min(100, s)), vocabulary: max(0, min(100, v)))
    }

    private func generateCoachingWithAppleIntelligence(
        analysis: SpeechAnalysis,
        transcript: String,
        context: CoachingContext
    ) async -> String? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let prompt = CoachingPrompt.user(
            analysis: analysis,
            transcript: transcript,
            context: context,
            transcriptBudget: CoachingPrompt.appleTranscriptBudget
        )

        do {
            let session = LanguageModelSession(
                model: model,
                instructions: CoachingPrompt.system(context: context)
            )
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            print("FoundationModels coaching error: \(error)")
            return nil
        }
    }

    private func generateWithAppleIntelligence(prompt: String, systemPrompt: String) async -> String? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let session = LanguageModelSession(
                model: model,
                instructions: systemPrompt
            )
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            print("FoundationModels generation error: \(error)")
            return nil
        }
    }

    // MARK: - Parsing

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

    private func sanitizeCoachingInsight(
        _ raw: String,
        analysis: SpeechAnalysis,
        transcript: String,
        context: CoachingContext
    ) -> String {
        // Pure rules live in `CoachingInsightSanitizer` (testable without a
        // model); this wrapper only owns the fallback decision.
        let extracted = CoachingInsightSanitizer.tips(from: raw)
        // Small local models drop the metric label despite the prompt rule,
        // and a bare "44/100" reads as a verdict from nowhere. The naming
        // pass runs before specificity so a relabelled score still counts as
        // its numeric signal.
        let tips = CoachingInsightSanitizer.namingBareScores(
            extracted,
            subscores: analysis.speechScore.subscores
        )

        guard !tips.isEmpty, CoachingInsightSanitizer.isSpecificEnough(tips, transcript: transcript) else {
            return deterministicCoachingFallback(analysis: analysis, context: context)
        }

        return tips.map { "- \($0)" }.joined(separator: "\n")
    }

    /// What the user sees when the model produced nothing usable.
    ///
    /// Not a placeholder. The rule-based tips already carry both halves of a
    /// real tip, the observation with its evidence and the named technique,
    /// so the fallback is coaching written by the deterministic path rather
    /// than an apology for the model.
    private func deterministicCoachingFallback(
        analysis: SpeechAnalysis,
        context: CoachingContext
    ) -> String {
        CoachingTipService.generateTips(from: analysis, context: context)
            .prefix(3)
            .map { tip in
                tip.teachingPoint.isEmpty
                    ? "- \(tip.message)"
                    : "- \(tip.message) \(tip.teachingPoint)"
            }
            .joined(separator: "\n")
    }
}
