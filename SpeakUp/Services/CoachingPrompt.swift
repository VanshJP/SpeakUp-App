import Foundation

/// The prompt both LLM backends are given for coaching.
///
/// There used to be two copies of this, one in `LLMService`, one in
/// `LocalLLMService`, and they had already drifted. One builder, one place
/// to improve the coaching.
///
/// What makes the output usable rather than a metric paraphrase:
/// - The dimension the user is actually working on, pinned to tip one.
/// - Their own pace target, not a textbook band.
/// - Quotable moments from the session (evidence the model could not invent).
/// - Crutch habits from the lexicon engine, so advice names "your 'like'".
/// - A worked example: small models copy examples far more reliably than rules.
/// - Head-and-tail transcript excerpt; conclusions live at the end, and a
///   naive prefix chop was coaching the opening while ignoring the close.
nonisolated enum CoachingPrompt {
    /// Transcript characters per backend. Apple Intelligence reasons over a
    /// whole answer; the local Gemma builds are small enough that a long
    /// transcript crowds out the instructions. The local budget is also
    /// shrunk further at call time when the profile runs a 512-token window.
    static let appleTranscriptBudget = 1600
    static let localTranscriptBudget = 600

    /// The subscore display names, verbatim from `CoachDimension`. Quoted into
    /// the prompt so the model labels scores with the same words the rest of
    /// the app uses, and reused by the sanitizer that catches whatever slips
    /// past this instruction.
    static let dimensionNameList = CoachDimension.allCases.map(\.title).joined(separator: ", ")

    // MARK: - System

    static func system(context: CoachingContext, compact: Bool = false) -> String {
        var rules = """
        You are a speech coach reviewing a take the speaker just finished. You have their numbers and their transcript. Your job is to name the one or two changes that would most improve how they land, each with one concrete action.

        Format, exactly:
        - Write 2 to 3 tips. Each is one line starting with "- ".
        - Every tip has two halves. First, what happened: cite a number from THIS SESSION or quote a short phrase from their transcript. Never invent numbers or quotes. Second, what to do: one specific action for the next take.
        - At most 28 words per tip.

        Scores:
        - A score is never written as a bare number. Always prefix it with its metric name, using these names exactly: \(dimensionNameList). Write "Vocal variety 44/100", "Clarity 71/100" — never just "44/100".

        Never do these:
        - No praise opener, no "great job", no restating the overall score.
        - No preamble, sign-off, headings, or emoji.
        - Never quote the benchmark numbers below as if they were this speaker's.
        - Never suggest adding filler words or frame a verbal tic as technique.
        - Vague advice ("be more concise", "slow down") counts as failure. "Cut the sentence at the first comma" does not.
        """

        if let plan = context.plan {
            rules += """


            The speaker is working on \(plan.focus.title.lowercased()). Tip one must be about that and nothing else. \(planDirection(plan))
            """
        }

        if !context.crutchLines.isEmpty {
            let list = context.crutchLines.joined(separator: ", ")
            rules += """


            CRUTCH HABITS measured in this take: \(list). One tip must name the top habit by its word and give the swap (pause instead, or the stronger word). Use the swaps only if they fit what the transcript shows.
            """
        }

        if let kind = kindDirective(context.sessionKind) {
            rules += """


            Session type: \(kind)
            """
        }

        if !compact {
            rules += """


            Benchmarks, context only, never quote them:
            - Their pace target is \(context.targetWPM) WPM; about 25 either side reads as rushing or dragging.
            - Fillers over 5% of words cost credibility; under 3% is where good speakers sit.
            - A 1-2 second pause after a point is what lets it land.
            - Hedging ("I think", "kind of") asks the listener to discount the sentence.

            Example of a good tip line:
            - You said "like" 7 times, mostly mid-sentence. Hold your mouth closed for one beat where it would go and the sentence carries itself.
            """
        }

        return rules
    }

    private static func planDirection(_ plan: CoachPlan) -> String {
        switch plan.trend {
        case .new:
            return "This is their starting point, so name what it is costing them rather than commenting on progress."
        case .improving(let delta):
            return "It has improved \(delta) points recently, acknowledge that in a few words, then push it further."
        case .flat:
            return "It has not moved in \(plan.sessionCount) sessions, so what they are currently doing is not working. Suggest a different approach, not more of the same."
        case .slipping(let delta):
            return "It has slipped \(delta) points recently, say so plainly and give them the correction."
        case .holding:
            return "They have this at a good level; the tip should be about keeping it there under harder conditions."
        }
    }

    /// One line of type-specific coaching angle. Matched on substrings so
    /// free-form user categories still land somewhere sensible.
    static func kindDirective(_ kind: String?) -> String? {
        guard let kind, !kind.isEmpty else { return nil }
        let lowered = kind.lowercased()

        if lowered.contains("interview") || lowered.contains("professional") || lowered.contains("elevator") {
            return "Answer as an interviewee. Lead with the direct answer, use ownership verbs (led, built, drove), and land one concrete number as proof."
        }
        if lowered.contains("story") {
            return "Shape it as a story: one concrete scene, a turn, and a payoff sentence at the end."
        }
        if lowered.contains("debate") || lowered.contains("persuasion") || lowered.contains("opinion") || lowered.contains("current") {
            return "Take one clear position, concede the strongest counterpoint in a sentence, then rebut it with evidence."
        }
        if lowered.contains("quick fire") {
            return "Give the direct answer in your first sentence, then one reason. No warm-up."
        }
        if lowered.contains("description") || lowered.contains("explain") {
            return "Open with the one-sentence definition, then two specifics that make it vivid."
        }
        return nil
    }

    // MARK: - User

    static func user(
        analysis: SpeechAnalysis,
        transcript: String,
        context: CoachingContext,
        transcriptBudget: Int
    ) -> String {
        var parts: [String] = ["THIS SESSION"]

        let subscores = analysis.speechScore.subscores
        parts.append("- Pace: \(Int(analysis.wordsPerMinute.rounded())) WPM against a \(context.targetWPM) target (scored \(subscores.pace)/100)")
        parts.append("- Fillers: \(analysis.totalFillerCount) in \(analysis.totalWords) words (scored \(subscores.fillerUsage)/100)")
        if let top = analysis.fillerWords.max(by: { $0.count < $1.count }), top.count > 0 {
            parts.append("- Most used filler: \"\(top.word)\", \(top.count) times")
        }
        parts.append("- Pauses: \(analysis.pauseCount) total, \(analysis.strategicPauseCount) deliberate, \(analysis.hesitationPauseCount) hesitations (scored \(subscores.pauseQuality)/100)")
        parts.append("- Answer size: \(analysis.totalWords) words")
        parts.append("- Clarity: \(subscores.clarity)/100")
        appendIfPresent(&parts, "Vocal variety", subscores.vocalVariety)
        appendIfPresent(&parts, "Delivery", subscores.delivery)
        appendIfPresent(&parts, "Vocabulary", subscores.vocabulary)
        appendIfPresent(&parts, "Structure", subscores.structure)
        appendIfPresent(&parts, "Staying on point", subscores.relevance)

        if let metrics = analysis.enhancedMetrics {
            parts.append("- Speaking \(Int((metrics.phonationTimeRatio * 100).rounded()))% of the take, \(String(format: "%.1f", metrics.meanLengthOfRun)) words between pauses")
        }

        // Reliability caveats belong in the prompt, not just in the UI: a model
        // told nothing will confidently coach a filler count that came out of a
        // noisy room or somebody else's voice.
        if let audio = analysis.audioIsolationMetrics, audio.residualNoiseScore < 45 {
            parts.append("- CAUTION: the recording was noisy, so the transcript and filler counts are less reliable than usual. Do not build a whole tip on them.")
        }
        if let speaker = analysis.speakerIsolationMetrics, speaker.conversationDetected {
            parts.append("- CAUTION: more than one person was speaking; only this speaker's words were scored.")
        }

        if !context.crutchLines.isEmpty {
            parts.append("")
            parts.append("CRUTCH HABITS")
            parts.append(contentsOf: context.crutchLines.map { "- " + $0 })
        }

        let evidence = context.evidence.promptLines
        if !evidence.isEmpty {
            parts.append("")
            parts.append("MOMENTS FROM THE RECORDING")
            parts.append(contentsOf: evidence)
        }

        if let plan = context.plan {
            parts.append("")
            parts.append("WHAT THEY ARE WORKING ON")
            parts.append("- \(plan.focus.title): \(plan.focusAverage)/100 averaged over \(plan.sessionCount) sessions, target \(plan.target).")
            parts.append("- \(plan.headline)")
            if !plan.holding.isEmpty {
                parts.append("- Already solid: \(plan.holding.map(\.title).joined(separator: ", ")). Do not spend a tip on these.")
            }
        }

        let excerpt = transcriptExcerpt(transcript, budget: transcriptBudget)
        if !excerpt.isEmpty {
            parts.append("")
            parts.append("TRANSCRIPT")
            parts.append(excerpt)
        }

        parts.append("")
        parts.append("Write the tips now.")

        return parts.joined(separator: "\n")
    }

    // MARK: - Transcript excerpt

    /// Head plus tail of the transcript within `budget` characters.
    ///
    /// Interview answers put their payoff in the close; a naive prefix chop
    /// hid exactly the material structure tips need to quote. Cuts land on
    /// word boundaries so neither half ends mid-word.
    static func transcriptExcerpt(_ transcript: String, budget: Int) -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        guard text.count > budget else { return text }

        let headBudget = Int(Double(budget) * 0.6)
        let tailBudget = budget - headBudget

        let head = truncatedToWordBoundary(String(text.prefix(headBudget)), atEnd: true)
        let tail = truncatedToWordBoundary(String(text.suffix(tailBudget)), atEnd: false)

        return head + "\n[...]\n" + tail
    }

    private static func truncatedToWordBoundary(_ chunk: String, atEnd: Bool) -> String {
        var trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if atEnd {
            if let lastSpace = trimmed.lastIndex(of: " ") {
                trimmed = String(trimmed[..<lastSpace])
            }
        } else {
            if let firstSpace = trimmed.firstIndex(of: " ") {
                trimmed = String(trimmed[trimmed.index(after: firstSpace)...])
            }
        }
        return trimmed
    }

    private static func appendIfPresent(_ parts: inout [String], _ label: String, _ score: Int?) {
        guard let score else { return }
        parts.append("- \(label): \(score)/100")
    }
}

// MARK: - Output sanitizer

/// Pure post-processing for LLM coaching output, split out of `LLMService`
/// so the acceptance rules are testable without a model or an actor hop.
nonisolated enum CoachingInsightSanitizer {

    /// Turns raw model output into at most three clean tip lines.
    static func tips(from raw: String) -> [String] {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var bulletTips: [String] = []
        for line in lines {
            let stripped = line
                .replacingOccurrences(of: #"^[\-\*\•\d\.\)\s]+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stripped.isEmpty else { continue }
            bulletTips.append(stripped)
        }

        if bulletTips.isEmpty {
            let paragraph = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                bulletTips = [paragraph]
            }
        }

        var seen: Set<String> = []
        var deduped: [String] = []
        for tip in bulletTips {
            if containsDisallowedAdvice(tip) {
                continue
            }
            let key = tip
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted {
                deduped.append(tip)
            }
            if deduped.count == 3 { break }
        }
        return deduped
    }

    /// Accepts output grounded in either the metrics or the speaker's own
    /// words. The old check scanned only the first 24 transcript tokens, so a
    /// tip quoting the answer's close (where interview payoffs live) was
    /// thrown away even when it was the best line in the batch.
    static func isSpecificEnough(_ tips: [String], transcript: String) -> Bool {
        let combined = tips.joined(separator: " ").lowercased()

        let hasNumericSignal = combined.range(of: #"\b\d+\b"#, options: .regularExpression) != nil
        let metricKeywords = [
            "wpm", "filler", "fillers", "pause", "pauses", "clarity", "pace",
            "words", "seconds", "vocabulary", "structure", "relevance"
        ]
        let hasMetricKeyword = metricKeywords.contains { combined.contains($0) }
        if hasMetricKeyword && hasNumericSignal {
            return true
        }

        let tokens = transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 5 }
        guard !tokens.isEmpty else { return false }

        // Distinct content words across the whole transcript, capped so very
        // long takes cannot make the scan quadratic against every tip.
        let tokenSet = Set(tokens.prefix(150))
        let overlapCount = tokenSet.filter { combined.contains($0) }.count
        return overlapCount >= 2
    }

    /// Drops a tip that recommends filler words as a technique.
    ///
    /// Distinguishes "add an 'um' to sound natural" from "swap the 'um' for a
    /// pause": any removal verb clears the line, which is why naming a filler
    /// alone is not enough to reject.
    static func containsDisallowedAdvice(_ tip: String) -> Bool {
        let lowered = tip.lowercased()
        let containsFillerTerm = lowered.range(
            of: #"\b(um|uh|like|you know|i mean|basically)\b"#,
            options: .regularExpression
        ) != nil
        let encouragesAction = lowered.range(
            of: #"\b(use|add|include|say|insert|try)\b"#,
            options: .regularExpression
        ) != nil
        let isAboutRemoval = lowered.range(
            of: #"\b(instead|replace|replacing|swap|cut|cutting|drop|dropping|remove|removing|without|avoid|avoiding|eliminate|eliminating|reduce|reducing|fewer|less|hold|close)\b"#,
            options: .regularExpression
        ) != nil

        if containsFillerTerm && encouragesAction && !isAboutRemoval {
            return true
        }
        if lowered.contains("filler word") && lowered.contains("help") {
            return true
        }
        return false
    }

    // MARK: - Bare score naming

    /// A score cited without its metric: "44/100", "44 / 100", "44 out of 100".
    private static let bareScorePattern = #"\b(\d{1,3})(?:\s*/\s*100|\s+out of\s+100)\b"#

    /// If one of these appears shortly before a score, the metric is already
    /// named and the score is left alone. Covers every `CoachDimension` title
    /// plus the shorthands models actually write ("vocab", "wpm") and
    /// "overall", which must never be relabelled as a subscore.
    private static let metricNameHints: Set<String> = [
        "filler words", "filler", "fillers",
        "pace", "wpm",
        "pauses", "pause",
        "clarity",
        "structure",
        "delivery",
        "vocal variety", "vocal",
        "vocabulary", "vocab",
        "staying on point", "on point", "relevance",
        "overall"
    ]

    /// How far back a bare-score match looks for an already-named metric.
    /// Long enough to cross "you scored a" or "came in at"; short enough that
    /// a previous sentence's metric cannot bleed into this sentence's score.
    private static let metricLookback = 40

    /// Rewrites bare score citations so each carries its metric name.
    ///
    /// The prompt instructs the model to write "Vocal variety 44/100"; small
    /// local models drop the label anyway, and a bare verdict-number was the
    /// first thing users read. A match is only rewritten when its number
    /// equals one of THIS session's subscores and no metric word sits within
    /// the look-back window — anything else stays exactly as written rather
    /// than guessing a label. Ties (two dimensions sharing a value) resolve to
    /// the first in `CoachDimension` order, deterministically.
    static func namingBareScores(_ tips: [String], subscores: SpeechSubscores) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: bareScorePattern) else { return tips }

        return tips.map { tip in
            let nsTip = tip as NSString
            let matches = regex.matches(
                in: tip,
                range: NSRange(location: 0, length: nsTip.length)
            )
            guard !matches.isEmpty else { return tip }

            var result = ""
            var cursor = 0
            for match in matches {
                let range = match.range

                let lookStart = max(0, range.location - metricLookback)
                let lookLength = range.location - lookStart
                let before = nsTip.substring(with: NSRange(location: lookStart, length: lookLength)).lowercased()
                if metricNameHints.contains(where: before.contains) {
                    continue
                }

                let digits = nsTip.substring(with: match.range(at: 1))
                guard let value = Int(digits),
                      let name = CoachDimension.allCases.first(where: { $0.subscore(in: subscores) == value })?.title
                else { continue }

                result += nsTip.substring(with: NSRange(location: cursor, length: range.location - cursor))
                result += "\(name) \(value)/100"
                cursor = range.location + range.length
            }
            guard cursor > 0 else { return tip }
            result += nsTip.substring(from: cursor)
            return result
        }
    }
}
