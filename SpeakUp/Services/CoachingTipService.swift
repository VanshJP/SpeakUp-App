import Foundation

// MARK: - Tip

nonisolated struct CoachingTip: Identifiable, Sendable {
    /// Why this tip is on screen. Drives ordering and presentation — the focus
    /// tip is the session's headline, a win is there so the screen is not a
    /// list of failures, and a signal note is a caveat about the measurement
    /// rather than advice about the speaking.
    enum Kind: Sendable {
        case focus
        case supporting
        case win
        case signal
    }

    let kind: Kind
    /// The dimension this tip trains. `nil` for wins and signal notes.
    let dimension: CoachDimension?
    let icon: String
    let title: String
    /// The observation: what happened, with the number and the moment.
    let message: String
    /// The technique: what to do about it, specifically enough to go do it.
    let teachingPoint: String
    /// Where this tip sends the speaker to train it.
    let suggestedPractice: CoachPracticeRoute?
    /// The moment in the recording this tip is about, when it has one.
    /// A tip that can be *heard* is worth several that can only be read.
    let evidenceTime: TimeInterval?

    var id: String {
        "\(dimension?.rawValue ?? "general")|\(title)|\(message)"
    }

    init(
        kind: Kind = .supporting,
        dimension: CoachDimension? = nil,
        icon: String,
        title: String,
        message: String,
        teachingPoint: String = "",
        suggestedPractice: CoachPracticeRoute? = nil,
        evidenceTime: TimeInterval? = nil
    ) {
        self.kind = kind
        self.dimension = dimension
        self.icon = icon
        self.title = title
        self.message = message
        self.teachingPoint = teachingPoint
        self.suggestedPractice = suggestedPractice
        self.evidenceTime = evidenceTime
    }
}

// MARK: - Context

/// Everything the tip service needs beyond the session itself.
///
/// Defaults reproduce the old context-free behaviour, so callers that only have
/// an analysis in hand (onboarding's first take, the LLM fallback) still work.
nonisolated struct CoachingContext: Sendable {
    var targetWPM: Int = 150
    var weights: ScoreWeights = .defaults
    /// Cross-session plan. When present its focus is pinned to the top, so the
    /// user is pointed at the same thing until they actually fix it.
    var plan: CoachPlan?
    var evidence: CoachEvidence = CoachEvidence()
    /// This take's worst crutch habits, preformatted for the LLM prompt,
    /// e.g. "\"like\" x7". Grounds the model in the lexicon engine's findings
    /// so it can name the habit instead of the category.
    var crutchLines: [String] = []
    /// Prompt category of the session ("Interview Prep", "Storytelling"), or
    /// "Story" for story-linked takes. Lets the prompt angle the advice at
    /// what the speaker was actually practicing.
    var sessionKind: String?

    init(
        targetWPM: Int = 150,
        weights: ScoreWeights = .defaults,
        plan: CoachPlan? = nil,
        evidence: CoachEvidence = CoachEvidence(),
        crutchLines: [String] = [],
        sessionKind: String? = nil
    ) {
        self.targetWPM = targetWPM
        self.weights = weights
        self.plan = plan
        self.evidence = evidence
        self.crutchLines = crutchLines
        self.sessionKind = sessionKind
    }
}

// MARK: - Service

nonisolated enum CoachingTipService {
    static let maximumTips = 3

    /// Evaluates a session and returns the tips worth the user's attention,
    /// most consequential first.
    ///
    /// Ordering is by weighted deficit, not by the order the checks happen to
    /// run in. The old version returned the first three branches that fired,
    /// which meant a noisy room could spend two of the three slots on
    /// microphone advice while a 41 in filler usage went unmentioned.
    static func generateTips(
        from analysis: SpeechAnalysis,
        context: CoachingContext = CoachingContext()
    ) -> [CoachingTip] {
        // The zero-word gate fired: there is nothing to coach, and pretending
        // otherwise ("your pace was 0 WPM") reads as broken.
        guard analysis.speechScore.overall > 0, analysis.totalWords > 0 else {
            return [
                CoachingTip(
                    kind: .supporting,
                    icon: "mic.slash.fill",
                    title: "Nothing to Score",
                    message: "This take came back empty, no speech was detected.",
                    teachingPoint: "Check that the microphone is not covered and that the app has microphone access, then run the take again."
                )
            ]
        }

        let weights = context.weights.normalized
        var candidates = dimensionTips(analysis: analysis, context: context)

        // Weighted deficit: how much overall score is recoverable here. A 60 in
        // a dimension worth 18% outranks a 45 in one worth 6%. Ties break on
        // the dimension name because `sort` is not stable — without it two
        // equal deficits could swap places between redraws and re-diff the list.
        candidates.sort { lhs, rhs in
            let left = deficit(lhs.dimension, analysis: analysis, weights: weights)
            let right = deficit(rhs.dimension, analysis: analysis, weights: weights)
            if left != right { return left > right }
            return (lhs.dimension?.rawValue ?? "") < (rhs.dimension?.rawValue ?? "")
        }

        // The plan's focus leads regardless of what this single session did.
        // Chasing whichever dimension dipped today is how users end up with
        // nine half-trained habits instead of one fixed one.
        if let focus = context.plan?.focus,
           let index = candidates.firstIndex(where: { $0.dimension == focus }) {
            let promoted = candidates.remove(at: index)
            candidates.insert(
                CoachingTip(
                    kind: .focus,
                    dimension: promoted.dimension,
                    icon: promoted.icon,
                    title: promoted.title,
                    message: promoted.message,
                    teachingPoint: promoted.teachingPoint,
                    suggestedPractice: promoted.suggestedPractice,
                    evidenceTime: promoted.evidenceTime
                ),
                at: 0
            )
        }

        var tips = Array(candidates.prefix(maximumTips))

        // Name one thing that worked. A screen that only lists faults trains
        // people to stop opening it, and the strength is real information —
        // it tells the speaker what to keep doing.
        if tips.count < maximumTips,
           let win = winTip(
               analysis: analysis,
               context: context,
               // The focus card already carries the trend line; repeating it
               // here would be the same sentence three times on one screen.
               allowTrendWin: !tips.contains { $0.kind == .focus }
           ) {
            tips.append(win)
        }

        // Measurement caveats go last and never take a coaching slot. They are
        // about the recording, not about the speaking.
        if tips.count < maximumTips, let signal = signalTip(analysis: analysis) {
            tips.append(signal)
        }

        if tips.isEmpty {
            tips.append(
                CoachingTip(
                    kind: .win,
                    icon: "checkmark.seal.fill",
                    title: "Clean Session",
                    message: "Nothing scored low enough to be worth changing. Bank another rep while it is working.",
                    teachingPoint: "Consistency is the whole game at this level. Same time, same length, every day, repetition is what turns a good session into your normal one."
                )
            )
        }

        return tips
    }

    // MARK: - Ranking

    private static func deficit(
        _ dimension: CoachDimension?,
        analysis: SpeechAnalysis,
        weights: ScoreWeights
    ) -> Double {
        guard let dimension else { return 0 }
        // A tip only exists here because something fired, so a dimension the
        // pipeline could not score is ranked from a neutral 55 rather than
        // dropped to the bottom on a missing number.
        let score = dimension.subscore(in: analysis.speechScore.subscores) ?? 55
        return Double(max(0, CoachPlanService.masteryTarget - score)) * dimension.weight(in: weights)
    }

    // MARK: - Dimension tips

    private static func dimensionTips(
        analysis: SpeechAnalysis,
        context: CoachingContext
    ) -> [CoachingTip] {
        let subscores = analysis.speechScore.subscores
        var tips: [CoachingTip] = []

        if let tip = fillerTip(analysis: analysis, context: context) { tips.append(tip) }
        if let tip = paceTip(analysis: analysis, context: context) { tips.append(tip) }
        if let tip = pauseTip(analysis: analysis, context: context) { tips.append(tip) }
        if let tip = clarityTip(analysis: analysis, context: context) { tips.append(tip) }
        if let tip = structureTip(analysis: analysis, context: context) { tips.append(tip) }
        if let tip = deliveryTip(analysis: analysis) { tips.append(tip) }
        if let tip = vocalVarietyTip(analysis: analysis) { tips.append(tip) }
        if let tip = vocabularyTip(analysis: analysis, context: context) { tips.append(tip) }
        if let tip = relevanceTip(analysis: analysis, context: context) { tips.append(tip) }

        // A dimension the plan is focused on always gets a tip, even on a
        // session where it happened to land above the threshold — otherwise the
        // focus silently disappears on a good day and the user loses the thread.
        if let focus = context.plan?.focus,
           !tips.contains(where: { $0.dimension == focus }),
           let score = focus.subscore(in: subscores) {
            tips.append(focusHoldTip(focus, score: score, plan: context.plan))
        }

        return tips
    }

    private static func focusHoldTip(_ focus: CoachDimension, score: Int, plan: CoachPlan?) -> CoachingTip {
        CoachingTip(
            kind: .focus,
            dimension: focus,
            icon: focus.icon,
            title: "\(focus.title): \(score) This Session",
            message: plan.map { "That is above your \($0.focusAverage) average. Two more like it and this stops being your focus." }
                ?? "Strong on your focus area this session. Keep the same approach.",
            teachingPoint: focus.technique.how,
            suggestedPractice: focus.practiceRoute
        )
    }

    // MARK: - Fillers

    private static func fillerTip(analysis: SpeechAnalysis, context: CoachingContext) -> CoachingTip? {
        let subscore = analysis.speechScore.subscores.fillerUsage
        guard subscore < CoachPlanService.masteryTarget else { return nil }

        let percentage = analysis.fillerPercentage
        let top = analysis.fillerWords.max(by: { $0.count < $1.count })
        let word = top?.word ?? "um"
        let count = top?.count ?? analysis.totalFillerCount
        guard count > 0 || percentage > 0 else { return nil }

        // The cluster is the coachable unit. Seven fillers spread over two
        // minutes is background texture; four in twelve seconds is the moment
        // the listener noticed.
        var message: String
        if let burst = context.evidence.fillerBurst, burst.count >= 3 {
            message = "\(burst.count) \"\(burst.word)\"s landed between \(CoachEvidence.stamp(burst.start)) and \(CoachEvidence.stamp(burst.end)), that stretch is where it was audible, not the \(analysis.totalFillerCount) across the whole take."
        } else if count > 0 {
            message = "\"\(word)\" \(count == 1 ? "once" : "\(count) times"), \(formatted(percentage))% of everything you said."
        } else {
            message = "Filler usage scored \(subscore)/100 this session."
        }

        if context.evidence.openingIsHesitant {
            message += " Your very first word was one of them."
        }

        // Hoisted out of the interpolation below: mixed numeric conversion and
        // a literal multiply inside a string is exactly the shape that stalls
        // the type checker, and it reports the failure somewhere else entirely.
        let wordBudget: Int = max(1, Int(Double(analysis.totalWords) * 0.03))
        let technique = CoachDimension.fillers.technique

        return CoachingTip(
            dimension: .fillers,
            icon: CoachDimension.fillers.icon,
            title: percentage > 8 ? "Name the Crutch" : "Trim the Fillers",
            message: message,
            teachingPoint: "\(technique.name): \(technique.how) Aim for under 3%, around \(wordBudget) in a take this length.",
            suggestedPractice: CoachDimension.fillers.practiceRoute,
            evidenceTime: context.evidence.fillerBurst?.start ?? top?.timestamps.min()
        )
    }

    // MARK: - Pace

    private static func paceTip(analysis: SpeechAnalysis, context: CoachingContext) -> CoachingTip? {
        let subscore = analysis.speechScore.subscores.pace
        guard subscore < CoachPlanService.masteryTarget else { return nil }

        let wpm = Int(analysis.wordsPerMinute.rounded())
        guard wpm > 0 else { return nil }
        // Read against the user's own target — auto-calibration moves it, and
        // the old fixed "130-170" advice contradicted the score whenever it did.
        let target = context.targetWPM
        let drift = wpm - target

        var message: String
        var title: String
        if drift > 25 {
            title = "Slow Down"
            message = "\(wpm) WPM against your \(target) target, \(drift) too fast."
        } else if drift > 12 {
            title = "Slightly Fast"
            message = "\(wpm) WPM, a touch over your \(target) target."
        } else if drift < -25 {
            title = "Pick Up the Pace"
            message = "\(wpm) WPM against your \(target) target, \(-drift) too slow."
        } else if drift < -12 {
            title = "A Little More Drive"
            message = "\(wpm) WPM, just under your \(target) target."
        } else if let metrics = analysis.enhancedMetrics, metrics.phonationTimeRatio < 0.45 {
            title = "Too Much Dead Air"
            message = "You were only speaking \(Int((metrics.phonationTimeRatio * 100).rounded()))% of the take. Your pace is fine, the silence between the words is what dropped the score."
        } else {
            title = "Steady the Pace"
            message = "\(wpm) WPM sits on your \(target) target, so the \(subscore)/100 is coming from how much the speed moved inside the take rather than from the average."
        }

        // A swing inside one session is invisible in an average and is usually
        // the real problem when the average looks fine.
        if let fastest = context.evidence.fastestStretch,
           let slowest = context.evidence.slowestStretch,
           fastest.wpm - slowest.wpm >= 40 {
            message += " You ran \(slowest.wpm) WPM at \(CoachEvidence.stamp(slowest.at)) and \(fastest.wpm) at \(CoachEvidence.stamp(fastest.at))."
        }

        return CoachingTip(
            dimension: .pace,
            icon: CoachDimension.pace.icon,
            title: title,
            message: message,
            teachingPoint: "\(CoachDimension.pace.technique.name): \(CoachDimension.pace.technique.how)",
            suggestedPractice: CoachDimension.pace.practiceRoute,
            evidenceTime: context.evidence.fastestStretch?.at
        )
    }

    // MARK: - Pauses

    private static func pauseTip(analysis: SpeechAnalysis, context: CoachingContext) -> CoachingTip? {
        let subscore = analysis.speechScore.subscores.pauseQuality
        guard subscore < CoachPlanService.masteryTarget else { return nil }

        var title: String
        var message: String

        if analysis.pauseCount == 0 {
            title = "You Never Stopped"
            message = "Not one pause across \(analysis.totalWords) words. Without a gap there is nowhere for a point to land."
        } else if analysis.hesitationPauseCount > analysis.strategicPauseCount {
            title = "Pauses Are Hesitations"
            message = "\(analysis.hesitationPauseCount) of your pauses read as searching for the next word, against \(analysis.strategicPauseCount) that read as deliberate."
        } else if let metrics = analysis.enhancedMetrics, metrics.meanLengthOfRun < 4, analysis.totalWords > 20 {
            title = "Speak in Longer Runs"
            message = "You averaged \(formatted(metrics.meanLengthOfRun)) words between pauses. Fluent delivery runs 7-12, the breaks are landing mid-phrase instead of at clause ends."
        } else if analysis.averagePauseLength > 3 {
            title = "Shorten the Gaps"
            message = "Your pauses averaged \(formatted(analysis.averagePauseLength))s. Past about two seconds a pause stops reading as emphasis and starts reading as a stall."
        } else {
            title = "Use Pauses on Purpose"
            message = "\(analysis.pauseCount) pauses, only \(analysis.strategicPauseCount) of them after a completed thought."
        }

        if let hesitation = context.evidence.longestHesitation, hesitation.seconds >= 2 {
            message += " The longest was \(formatted(hesitation.seconds))s at \(CoachEvidence.stamp(hesitation.at)), mid-thought."
        }

        return CoachingTip(
            dimension: .pauses,
            icon: CoachDimension.pauses.icon,
            title: title,
            message: message,
            teachingPoint: "\(CoachDimension.pauses.technique.name): \(CoachDimension.pauses.technique.how)",
            suggestedPractice: CoachDimension.pauses.practiceRoute,
            evidenceTime: context.evidence.longestHesitation?.at
        )
    }

    // MARK: - Clarity

    private static func clarityTip(analysis: SpeechAnalysis, context: CoachingContext) -> CoachingTip? {
        let subscore = analysis.speechScore.subscores.clarity
        guard subscore < CoachPlanService.masteryTarget else { return nil }

        var message = "\(subscore)/100. Words are arriving softer than you think they are, that is almost always word endings rather than volume."
        var title = "Sharpen Your Articulation"

        // Hedging is a clarity problem the speaker can hear themselves, unlike
        // articulation — so when it is present, lead with it.
        if context.evidence.hedgeCount >= 3 {
            title = "Drop the Hedging"
            message = "\(context.evidence.hedgeCount) hedges, \"maybe\", \"kind of\", \"I think\", in one take. Each one asks the listener to discount what follows it."
            return CoachingTip(
                dimension: .clarity,
                icon: CoachDimension.clarity.icon,
                title: title,
                message: message,
                teachingPoint: "Say the claim without the cushion. \"I think this might be the better option\" becomes \"This is the better option.\" If you are genuinely unsure, say why you are unsure, that is information. A hedge is not.",
                suggestedPractice: CoachDimension.clarity.practiceRoute
            )
        }

        if let ratio = analysis.pitchMetrics?.voicedFrameRatio, ratio < 0.25 {
            message = "Only \(Int((ratio * 100).rounded()))% of your frames carried a clear voiced signal. That is the acoustic signature of trailing off at the ends of words."
        }

        return CoachingTip(
            dimension: .clarity,
            icon: CoachDimension.clarity.icon,
            title: title,
            message: message,
            teachingPoint: "\(CoachDimension.clarity.technique.name): \(CoachDimension.clarity.technique.how)",
            suggestedPractice: CoachDimension.clarity.practiceRoute
        )
    }

    // MARK: - Structure

    private static func structureTip(analysis: SpeechAnalysis, context: CoachingContext) -> CoachingTip? {
        let subscore = analysis.speechScore.subscores.structure
        let substance = analysis.enhancedMetrics?.substanceScore
        // Structure is optional in the pipeline, but a thin answer is a
        // structure problem whether or not the subscore was produced.
        guard (subscore ?? 100) < CoachPlanService.masteryTarget || (substance ?? 100) < 60 else { return nil }

        var title = "Build the Shape"
        var message: String

        if let substance, substance < 35 {
            title = "Develop the Answer"
            message = "\(analysis.totalWords) words is not enough material to structure. A point needs a reason and an example behind it before it holds."
        } else if let restart = context.evidence.restart {
            title = "Finish the Sentence You Started"
            message = "You restarted mid-sentence: \"\(restart)\". Restarts are the sound of composing out loud instead of committing to a shape."
        } else if let quality = analysis.textQuality, quality.concisenessScore < 55 {
            title = "Tighten the Phrasing"
            message = "\(quality.weakPhraseCount) weak phrases padding the point. Conciseness scored \(quality.concisenessScore)/100."
        } else if let quality = analysis.textQuality, quality.transitionVariety < 3 {
            title = "Signpost the Turns"
            message = "You used \(quality.transitionVariety) distinct transitions. Without them the listener cannot tell a new idea from a continuation of the last one."
        } else if let subscore {
            message = "Structure scored \(subscore)/100, the ideas are there, the order is not doing work for them yet."
        } else {
            // Reached when substance is thin but the structure subscore was
            // never produced. Quoting a score we do not have would be a lie.
            message = "\(analysis.totalWords) words with no clear shape to them yet, the ideas are there, the order is not doing work for them."
        }

        return CoachingTip(
            dimension: .structure,
            icon: CoachDimension.structure.icon,
            title: title,
            message: message,
            teachingPoint: "\(CoachDimension.structure.technique.name): \(CoachDimension.structure.technique.how)",
            suggestedPractice: CoachDimension.structure.practiceRoute
        )
    }

    // MARK: - Delivery

    private static func deliveryTip(analysis: SpeechAnalysis) -> CoachingTip? {
        guard let subscore = analysis.speechScore.subscores.delivery,
              subscore < CoachPlanService.masteryTarget else { return nil }

        var message = "\(subscore)/100. Nothing in the take was marked as more important than anything else, so the listener has to decide what mattered."
        if let emphasis = analysis.emphasisMetrics?.emphasisPerMinute, emphasis < 3 {
            message = "\(formatted(emphasis)) emphasised words per minute. Without emphasis every word carries the same weight, so none of them carry any."
        } else if let energy = analysis.volumeMetrics?.energyScore, energy < 50 {
            message = "Vocal energy came in at \(energy)/100, the volume never rose to mark anything as important."
        }

        return CoachingTip(
            dimension: .delivery,
            icon: CoachDimension.delivery.icon,
            title: "Put Weight on the Key Words",
            message: message,
            teachingPoint: "\(CoachDimension.delivery.technique.name): \(CoachDimension.delivery.technique.how)",
            suggestedPractice: CoachDimension.delivery.practiceRoute
        )
    }

    // MARK: - Vocal variety

    private static func vocalVarietyTip(analysis: SpeechAnalysis) -> CoachingTip? {
        guard let subscore = analysis.speechScore.subscores.vocalVariety,
              subscore < CoachPlanService.masteryTarget else { return nil }

        var message = "\(subscore)/100. Your pitch and volume held a narrow band, which flattens the difference between a throwaway line and the point of the whole answer."
        if let range = analysis.pitchMetrics?.f0RangeSemitones, range < 6 {
            message = "Your pitch moved across \(formatted(Double(range))) semitones. Engaging conversational speech ranges over roughly 10-12, under about 6 the ear reads it as monotone."
        }

        return CoachingTip(
            dimension: .vocalVariety,
            icon: CoachDimension.vocalVariety.icon,
            title: "Widen Your Range",
            message: message,
            teachingPoint: "\(CoachDimension.vocalVariety.technique.name): \(CoachDimension.vocalVariety.technique.how)",
            suggestedPractice: CoachDimension.vocalVariety.practiceRoute
        )
    }

    // MARK: - Vocabulary

    private static func vocabularyTip(analysis: SpeechAnalysis, context: CoachingContext) -> CoachingTip? {
        guard let subscore = analysis.speechScore.subscores.vocabulary,
              subscore < CoachPlanService.masteryTarget else { return nil }

        var title = "Reach for the Precise Word"
        var message = "\(subscore)/100. The words are doing less work than the ideas behind them, reaching for the precise one is what makes a point land the first time."

        if let crutch = context.evidence.crutchPhrase {
            title = "You Have a Crutch Phrase"
            message = "\"\(crutch.phrase)\" came up \(crutch.count) times. A repeated phrase stops being heard after the second use."
        } else if let mattr = analysis.enhancedMetrics?.mattr, mattr < 0.6 {
            message = "Your type-token ratio was \(formatted(mattr, places: 2)), you were recycling the same words rather than reaching for new ones. Rich speech runs 0.72 and up."
        }

        return CoachingTip(
            dimension: .vocabulary,
            icon: CoachDimension.vocabulary.icon,
            title: title,
            message: message,
            teachingPoint: "\(CoachDimension.vocabulary.technique.name): \(CoachDimension.vocabulary.technique.how)",
            suggestedPractice: CoachDimension.vocabulary.practiceRoute
        )
    }

    // MARK: - Relevance

    private static func relevanceTip(analysis: SpeechAnalysis, context: CoachingContext) -> CoachingTip? {
        guard let subscore = analysis.speechScore.subscores.relevance,
              subscore < CoachPlanService.masteryTarget else { return nil }

        let answeringPrompt = analysis.promptRelevanceScore != nil
        var message = answeringPrompt
            ? "Relevance to the prompt scored \(subscore)/100, the answer drifted from what was asked."
            : "Coherence scored \(subscore)/100, the ideas are there but the thread between them is loose."

        if let opening = context.evidence.opening {
            message += " You opened with \"\(opening)\"."
        }

        return CoachingTip(
            dimension: .relevance,
            icon: CoachDimension.relevance.icon,
            title: answeringPrompt ? "Answer the Question First" : "Tighten the Thread",
            message: message,
            teachingPoint: answeringPrompt
                ? "\(CoachDimension.relevance.technique.name): \(CoachDimension.relevance.technique.how)"
                : "Bridge every idea to the one before it out loud, \"which means\", \"the flip side of that\", \"so what that gives you is\". The connection is obvious to you because you thought it; it is invisible to a listener until you say it.",
            suggestedPractice: CoachDimension.relevance.practiceRoute,
            evidenceTime: context.evidence.opening == nil ? nil : 0
        )
    }

    // MARK: - Wins

    /// The strongest dimension worth naming. Specific praise is usable — it
    /// tells the speaker which behaviour produced the result.
    private static func winTip(
        analysis: SpeechAnalysis,
        context: CoachingContext,
        allowTrendWin: Bool
    ) -> CoachingTip? {
        if allowTrendWin, let plan = context.plan, case .improving(let delta) = plan.trend {
            return CoachingTip(
                kind: .win,
                dimension: plan.focus,
                icon: "chart.line.uptrend.xyaxis",
                title: "\(plan.focus.title) Is Moving",
                message: "Up \(delta) points across your last \(plan.sessionCount) sessions. \(plan.graduationLine)",
                teachingPoint: "Whatever changed in the last few sessions is working. Do not add anything new until this one is banked, one habit at a time is what makes it stick."
            )
        }

        let subscores = analysis.speechScore.subscores
        let best = CoachDimension.allCases
            .compactMap { dimension -> (CoachDimension, Int)? in
                dimension.subscore(in: subscores).map { (dimension, $0) }
            }
            .max { $0.1 < $1.1 }

        guard let best, best.1 >= CoachPlanService.masteryTarget else { return nil }

        return CoachingTip(
            kind: .win,
            dimension: best.0,
            icon: "checkmark.seal.fill",
            title: "\(best.0.title) Is Working",
            message: "\(best.1)/100 this session, that one is not costing you anything.",
            teachingPoint: "Leave it alone. Attention spent on a dimension that is already strong is attention not spent on the one holding your score down."
        )
    }

    // MARK: - Signal quality

    /// A caveat about the measurement, never a coaching slot.
    ///
    /// These used to be evaluated first and could take two of the three slots,
    /// pushing out the actual coaching. Now they only appear in leftover space.
    private static func signalTip(analysis: SpeechAnalysis) -> CoachingTip? {
        if let speaker = analysis.speakerIsolationMetrics, speaker.conversationDetected {
            return CoachingTip(
                kind: .signal,
                icon: "person.2.wave.2.fill",
                title: "Scored on Your Voice Only",
                message: "Multiple speakers were detected. \(Int(speaker.primarySpeakerWordRatio * 100))% of the words were matched to you, and only those were scored.",
                teachingPoint: "For the cleanest separation in a group, start with five seconds of just your voice and keep the microphone nearer to you than to anyone else."
            )
        }
        if let audio = analysis.audioIsolationMetrics, audio.residualNoiseScore < 45 {
            return CoachingTip(
                kind: .signal,
                icon: "waveform.badge.exclamationmark",
                title: "Noisy Recording",
                message: "Background noise was high enough to affect the transcript, so the clarity and filler numbers here are less certain than usual.",
                teachingPoint: "Scoring is most stable when your voice clearly dominates the room. A quieter space or a headset microphone will tighten these numbers."
            )
        }
        if let speaker = analysis.speakerIsolationMetrics, speaker.separationConfidence < 50 {
            return CoachingTip(
                kind: .signal,
                icon: "person.crop.circle.badge.questionmark",
                title: "Overlapping Voices",
                message: "Some words could not be confidently attributed to you, so this session's numbers carry more uncertainty than usual.",
                teachingPoint: "Separation improves when your voice sits consistently above nearby speakers. Keep the microphone close when you are scoring yourself."
            )
        }
        return nil
    }

    // MARK: - Formatting

    private static func formatted(_ value: Double, places: Int = 1) -> String {
        String(format: "%.\(places)f", value)
    }
}
