import Foundation

// MARK: - Dimension

/// The trainable dimensions of speech, one per subscore.
///
/// Coaching copy hangs off these rather than off free-form strings so the tip
/// service, the next-step card, and the LLM prompt all name the same thing.
nonisolated enum CoachDimension: String, CaseIterable, Sendable, Identifiable {
    case fillers
    case pace
    case pauses
    case clarity
    case structure
    case delivery
    case vocalVariety
    case vocabulary
    case relevance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fillers: return "Filler words"
        case .pace: return "Pace"
        case .pauses: return "Pauses"
        case .clarity: return "Clarity"
        case .structure: return "Structure"
        case .delivery: return "Delivery"
        case .vocalVariety: return "Vocal variety"
        case .vocabulary: return "Vocabulary"
        case .relevance: return "Staying on point"
        }
    }

    var icon: String {
        switch self {
        case .fillers: return "exclamationmark.bubble.fill"
        case .pace: return "gauge.with.dots.needle.50percent"
        case .pauses: return "pause.circle.fill"
        case .clarity: return "waveform.badge.magnifyingglass"
        case .structure: return "list.bullet.rectangle"
        case .delivery: return "speaker.wave.3.fill"
        case .vocalVariety: return "waveform.path.ecg"
        case .vocabulary: return "textformat.abc"
        case .relevance: return "target"
        }
    }

    /// The named technique the speaker drills for this dimension. Coaching that
    /// says "be clearer" changes nothing; a technique with a name and a rep
    /// count is something you can actually go do.
    var technique: (name: String, how: String) {
        switch self {
        case .fillers:
            return ("The silent swap",
                    "The instant you feel a filler coming, close your mouth and hold it for one beat. The pause buys the same thinking time the filler did, it just reads as control instead of hesitation.")
        case .pace:
            return ("One idea, one breath",
                    "Take a breath at the end of each idea, not in the middle of one. Breathing on the idea boundary sets your speed automatically and stops the runaway sentence before it starts.")
        case .pauses:
            return ("Land it and count two",
                    "After your strongest sentence, stop and count two full beats before the next word. It feels far longer to you than it does to a listener, that gap is where the point sinks in.")
        case .clarity:
            return ("Finish the consonant",
                    "Over-pronounce the last consonant of every word for one full session, the T in 'about', the D in 'would'. Dropped word endings, not volume, are what makes speech read as mumbled.")
        case .structure:
            return ("PREP",
                    "Point, Reason, Example, Point. Say your claim first, give one reason, give one concrete example, then restate the claim. Four sentences, in that order, every time until it is automatic.")
        case .delivery:
            return ("Pick the one word",
                    "Choose a single word per sentence to hit, slightly louder, slightly slower. One emphasised word per sentence is the whole difference between reading and speaking.")
        case .vocalVariety:
            return ("Three keys",
                    "Deliver a sentence low, then mid, then high in pitch, and notice how differently each lands. Rotating deliberately through your range in practice widens the range you reach for unconsciously.")
        case .vocabulary:
            return ("Upgrade one word",
                    "Each time you catch yourself reaching for 'good', 'thing', or 'stuff', stop and swap in the precise word. One upgrade per answer, not ten, the reach is what builds the habit.")
        case .relevance:
            return ("Answer in sentence one",
                    "Give the direct answer in your first sentence, then support it. Warming up on the listener before you commit to a position is what reads as rambling.")
        }
    }

    /// Stable identifier reported to the outcome funnel. Deliberately separate
    /// from `rawValue`: these strings predate this enum and renaming one forks
    /// the analytics series it belongs to.
    var analyticsSlug: String {
        switch self {
        case .fillers: return "filler"
        case .pauses: return "pause"
        case .vocalVariety: return "vocal_variety"
        case .pace, .clarity, .structure, .delivery, .vocabulary, .relevance: return rawValue
        }
    }

    /// The practice tool that trains this dimension.
    ///
    /// Three dimensions route away from the drills, and forcing them into the
    /// nearest one produced advice that read as broken: a tip about widening
    /// your pitch range suggesting Pause Practice, a tip about articulation
    /// suggesting Pace Control. Articulation is mechanical and reading aloud
    /// trains the mouth; a flat voice belongs on Vocal Variety, and punchy
    /// delivery belongs on Emphasis — both scored drills.
    ///
    /// One definition, used by both the tip rows and `NextStep` — they used to
    /// carry separate mappings and had already disagreed.
    var practiceRoute: CoachPracticeRoute {
        switch self {
        case .fillers: return .drill("fillerElimination")
        case .pace: return .drill("paceControl")
        case .pauses: return .drill("pausePractice")
        case .structure, .vocabulary, .relevance: return .drill("impromptuSprint")
        case .clarity: return .readAloud
        case .delivery: return .drill("emphasis")
        case .vocalVariety: return .drill("vocalVariety")
        }
    }

    func subscore(in subscores: SpeechSubscores) -> Int? {
        switch self {
        case .fillers: return subscores.fillerUsage
        case .pace: return subscores.pace
        case .pauses: return subscores.pauseQuality
        case .clarity: return subscores.clarity
        case .structure: return subscores.structure
        case .delivery: return subscores.delivery
        case .vocalVariety: return subscores.vocalVariety
        case .vocabulary: return subscores.vocabulary
        case .relevance: return subscores.relevance
        }
    }

    /// How much of the overall score this dimension controls. Ranking by
    /// weighted deficit rather than by raw subscore is what stops the coach
    /// sending the user after a 60 in a dimension worth 6% of the score while a
    /// 68 worth 18% goes unmentioned.
    func weight(in weights: ScoreWeights) -> Double {
        switch self {
        case .fillers: return weights.filler
        case .pace: return weights.pace
        case .pauses: return weights.pause
        case .clarity: return weights.clarity
        case .structure: return weights.structure
        case .delivery: return weights.delivery
        case .vocalVariety: return weights.vocalVariety
        case .vocabulary: return weights.vocabulary
        case .relevance: return weights.relevance
        }
    }
}

// MARK: - Practice route

/// Where a dimension sends the speaker to train it.
///
/// Lives beside `CoachDimension` rather than in the view layer so the tip
/// service — which is `nonisolated` and knows nothing about SwiftUI — can name
/// a destination without reaching for `NextStep.Action`.
nonisolated enum CoachPracticeRoute: Sendable, Equatable {
    /// A `DrillMode` raw value.
    case drill(String)
    case readAloud
    case warmUp
}

// MARK: - Crutch hint

/// The user's single most-repeated crutch word, produced by
/// `LexiconInsightsEngine` and handed to the plan so filler coaching names the
/// actual habit instead of the category.
nonisolated struct CrutchHint: Sendable, Equatable {
    let word: String
    let count: Int

    /// Below this the word is noise, not a habit.
    static let minimumCount = 4
}

// MARK: - Plan

/// What the speaker is working on right now, and whether it is moving.
///
/// A per-session tip list can only ever say "this is what happened". A coach
/// says "this is what you are working on, here is where it started, here is
/// where it is now". That difference is this type: the focus is chosen from a
/// rolling window rather than from the session in hand, so it stays put long
/// enough to actually be trained instead of ping-ponging every recording.
nonisolated struct CoachPlan: Sendable {
    enum Trend: Sendable, Equatable {
        /// Not enough history to say anything honest about direction yet.
        case new
        case improving(delta: Int)
        case flat
        case slipping(delta: Int)
        /// Sitting at or above the mastery bar across the window.
        case holding

        var isPositive: Bool {
            switch self {
            case .improving, .holding: return true
            case .new, .flat, .slipping: return false
            }
        }
    }

    /// The one dimension to work on now.
    let focus: CoachDimension
    /// Rolling-window mean for `focus` — the number the plan is actually about.
    let focusAverage: Int
    /// `focus` in the session being viewed. Diverges from the average on a
    /// standout or off day, which is worth saying out loud.
    let focusLatest: Int
    let trend: Trend
    /// Analyzed sessions the plan was built from, current session included.
    let sessionCount: Int
    /// Dimensions already at or above the mastery bar across the window.
    let holding: [CoachDimension]
    /// Score the focus has to reach — and hold — to graduate.
    let target: Int
    /// The user's most-repeated crutch word when the focus is fillers, else nil.
    /// Turns "watch the filler words" into "cut 'like'" — a named target trains
    /// faster than a category.
    let namedHabit: String?

    /// True once the focus has cleared the bar: time to move the user on.
    var isGraduating: Bool { focusAverage >= target }

    /// One line naming the work, the number, and the direction. This is the
    /// headline the whole coaching screen is built around.
    var headline: String {
        let base: String
        switch trend {
        case .new:
            base = "\(focus.title) is your biggest lever right now, \(focusAverage)/100 to start from."
        case .improving(let delta):
            base = "\(focus.title) is up \(delta) points across your last \(sessionCount) sessions, \(focusAverage)/100 and climbing."
        case .flat:
            base = "\(focus.title) has held at \(focusAverage)/100 for \(sessionCount) sessions. Try one small technique change next."
        case .slipping(let delta):
            base = "\(focus.title) has slipped \(delta) points lately, back to \(focusAverage)/100."
        case .holding:
            base = "\(focus.title) is holding at \(focusAverage)/100. Keeping it there is the work now."
        }

        if let namedHabit {
            return base + " Most common right now: \u{201C}\(namedHabit)\u{201D}."
        }
        return base
    }

    /// What earns graduation off this focus, stated as a bar the user can aim
    /// at. Open-ended practice is what makes people quit; a finish line is what
    /// makes them come back.
    var graduationLine: String {
        // The focus is the largest deficit, so a focus at the bar means every
        // dimension is at the bar. There is no next weakness to hand over to —
        // the work stops being repair and starts being difficulty.
        isGraduating
            ? "Every dimension is at or above \(target). The next gains come from harder conditions, not fixes, longer takes, no prep, a real audience."
            : "Get \(focus.title.lowercased()) to \(target) and hold it for three sessions to move on."
    }
}

// MARK: - Service

nonisolated enum CoachPlanService {
    /// The bar a dimension has to clear to stop being the focus. Deliberately
    /// above "fine" — 85 is where a dimension stops costing the speaker
    /// anything, and there is no point coaching toward mediocre.
    static let masteryTarget = 85

    /// Sessions needed before a direction claim is honest. Below this the plan
    /// reports `.new` rather than reading noise as a trend.
    static let minimumSessionsForTrend = 4

    /// Builds the plan from a newest-first window of analyses.
    ///
    /// Pure and cheap — no persistence and no per-focus bookkeeping. Stickiness
    /// comes from averaging the window instead of storing a chosen focus: an
    /// average moves slowly by construction, so the focus survives one good day
    /// without anyone having to remember it was picked.
    static func plan(
        window: [SpeechAnalysis],
        weights: ScoreWeights = .defaults,
        crutchHint: CrutchHint? = nil
    ) -> CoachPlan? {
        // A zero overall means the zero-word gate fired — a failed capture, not
        // a measurement of how the speaker speaks. Averaging those in would
        // invent weaknesses out of dead microphones.
        let scored = window.filter { $0.speechScore.overall > 0 }
        guard !scored.isEmpty else { return nil }

        let normalized = weights.normalized
        let subscores = scored.map(\.speechScore.subscores)

        var averages: [CoachDimension: Int] = [:]
        for dimension in CoachDimension.allCases {
            let values = subscores.compactMap { dimension.subscore(in: $0) }
            // A dimension the pipeline could not measure this window has no
            // deficit to rank — better silent than guessed.
            guard values.count >= max(1, scored.count / 2) else { continue }
            averages[dimension] = mean(values)
        }
        guard !averages.isEmpty else { return nil }

        var ranked: [Ranking] = []
        ranked.reserveCapacity(averages.count)
        for (dimension, average) in averages {
            ranked.append(
                Ranking(
                    dimension: dimension,
                    average: average,
                    impact: impact(dimension, average: average, weights: normalized)
                )
            )
        }
        ranked.sort { outranks($0, $1, weights: normalized) }

        guard let top = ranked.first else { return nil }

        let latest = top.dimension.subscore(in: subscores[0]) ?? top.average
        let holding = ranked
            .filter { $0.average >= masteryTarget }
            .map(\.dimension)

        // The named habit only exists when the plan is actually about fillers —
        // attaching "cut 'like'" to a pace focus would be noise.
        let namedHabit: String?
        if top.dimension == .fillers, let hint = crutchHint, hint.count >= CrutchHint.minimumCount {
            namedHabit = hint.word
        } else {
            namedHabit = nil
        }

        return CoachPlan(
            focus: top.dimension,
            focusAverage: top.average,
            focusLatest: latest,
            trend: trend(for: top.dimension, subscores: subscores, average: top.average),
            sessionCount: scored.count,
            holding: holding,
            target: masteryTarget,
            namedHabit: namedHabit
        )
    }

    // MARK: - Ranking

    /// A dimension with the numbers its ranking is decided on.
    ///
    /// A named type rather than a labelled tuple: the tuple version pushed the
    /// sort comparator past what the type checker would solve, and the error it
    /// produced pointed at the key path two lines further down.
    private nonisolated struct Ranking {
        let dimension: CoachDimension
        let average: Int
        let impact: Double
    }

    /// Ordering for the focus. Ties break on weight, then on name, so the focus
    /// is stable across launches instead of following dictionary order.
    private static func outranks(_ lhs: Ranking, _ rhs: Ranking, weights: ScoreWeights) -> Bool {
        if lhs.impact != rhs.impact { return lhs.impact > rhs.impact }
        let leftWeight = lhs.dimension.weight(in: weights)
        let rightWeight = rhs.dimension.weight(in: weights)
        if leftWeight != rightWeight { return leftWeight > rightWeight }
        return lhs.dimension.rawValue < rhs.dimension.rawValue
    }

    /// Points of overall score recoverable by getting this dimension to the
    /// mastery bar. A dimension already at the bar scores 0 and drops out.
    private static func impact(_ dimension: CoachDimension, average: Int, weights: ScoreWeights) -> Double {
        Double(max(0, masteryTarget - average)) * dimension.weight(in: weights)
    }

    // MARK: - Trend

    /// Newest half against oldest half. Cruder than a regression and far easier
    /// to explain in one sentence, which is what the user actually reads.
    private static func trend(
        for dimension: CoachDimension,
        subscores: [SpeechSubscores],
        average: Int
    ) -> CoachPlan.Trend {
        let values = subscores.compactMap { dimension.subscore(in: $0) }
        guard values.count >= minimumSessionsForTrend else {
            return average >= masteryTarget ? .holding : .new
        }

        // `values` is newest-first.
        let half = values.count / 2
        let recent = mean(Array(values.prefix(half)))
        let older = mean(Array(values.suffix(values.count - half)))
        let delta = recent - older

        if average >= masteryTarget && delta >= -2 { return .holding }
        // ±3 is inside session-to-session noise for a 0-100 subscore; calling
        // that "improving" would burn the word on nothing.
        if delta >= 3 { return .improving(delta: delta) }
        if delta <= -3 { return .slipping(delta: -delta) }
        return .flat
    }

    private static func mean(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
