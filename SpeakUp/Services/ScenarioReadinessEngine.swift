import Foundation

// MARK: - Scenario taxonomy

/// The named situations readiness is reported against. Sessions are bucketed
/// by their prompt category so each scenario card aggregates real, labeled
/// practice instead of one opaque composite.
nonisolated enum PracticeScenario: String, CaseIterable, Sendable, Hashable, Identifiable {
    case interviews = "Interviews"
    case publicSpeaking = "Public Speaking"
    case storytelling = "Storytelling"
    case conversation = "Everyday Conversation"
    /// Freeform takes and unrecognized custom categories. Rendered only when
    /// such sessions exist; never shown as an invitation.
    case other = "Everything Else"

    var id: String { rawValue }

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .interviews: return "briefcase.fill"
        case .publicSpeaking: return "arrow.up.right.circle.fill"
        case .storytelling: return "book.fill"
        case .conversation: return "person.2.wave.2.fill"
        case .other: return "square.stack.3d.up.fill"
        }
    }

    /// One line under the title on an invitation row — what practicing here builds.
    var blurb: String {
        switch self {
        case .interviews: return "Behavioral answers, case questions, career stories."
        case .publicSpeaking: return "Pitches, debate takes, thinking on your feet."
        case .storytelling: return "Narrative arcs from story sessions."
        case .conversation: return "Small talk, opinions, explaining clearly."
        case .other: return ""
        }
    }

    /// Core scenarios get invitation rows while unpracticed; `other` does not.
    var isCore: Bool { self != .other }
}

// MARK: - Momentum

nonisolated enum ScenarioMomentum: Sendable, Hashable {
    case improving
    case steady
    case slipping
}

// MARK: - Readiness model

/// One scenario's verdict: a 0–100 composite reused from the interview-readiness
/// weights, an honest thin-data flag, the direction of travel, and the habit
/// most responsible for whatever is holding it back.
nonisolated struct ScenarioReadiness: Identifiable, Sendable, Hashable {
    let scenario: PracticeScenario
    let sessions: Int
    /// Nil when the bucket exists but carries too little language to score.
    let score: Int?
    let isEarlyRead: Bool
    let momentum: ScenarioMomentum
    /// The dominant crutch in this bucket, e.g. ("like", 12).
    let holdingBackWord: String?
    let holdingBackCount: Int?

    var id: PracticeScenario { scenario }

    /// Below this many sessions a read is honest but thin.
    static let confidenceThreshold = 4
    /// Thin buckets never reach the "Ready" band boundary (85).
    static let earlyReadScoreCap = 84

    var bandLabel: String {
        switch score {
        case .some(85...): return "Ready"
        case .some(70..<85): return "Strong position"
        case .some(55..<70): return "Getting there"
        case .some: return "Building blocks"
        case .none: return "Needs more language"
        }
    }
}

// MARK: - Trajectory summary

/// Glanceable answer to "which way am I moving": latest, best, average, and a
/// momentum verdict comparing the mean of recent sessions against earlier ones.
nonisolated struct TrajectorySummary: Sendable, Equatable {
    let latestScore: Int?
    let bestScore: Int
    let averageScore: Int
    /// Recent-half mean minus early-half mean; 0 until two sessions exist.
    let delta: Int
    let momentum: ScenarioMomentum

    /// `scores` must be chronological (oldest first).
    static func summarize(_ chronologicalScores: [Int]) -> TrajectorySummary {
        guard let latest = chronologicalScores.last else {
            return TrajectorySummary(latestScore: nil, bestScore: 0, averageScore: 0, delta: 0, momentum: .steady)
        }
        guard chronologicalScores.count >= 2 else {
            return TrajectorySummary(
                latestScore: latest,
                bestScore: max(latest, 0),
                averageScore: latest,
                delta: 0,
                momentum: .steady
            )
        }

        let midIndex = chronologicalScores.count / 2
        let earlyMean = mean(chronologicalScores.prefix(midIndex))
        let recentMean = mean(chronologicalScores.suffix(from: midIndex))
        let delta = Int((recentMean - earlyMean).rounded())

        let momentum: ScenarioMomentum
        if delta >= 3 {
            momentum = .improving
        } else if delta <= -3 {
            momentum = .slipping
        } else {
            momentum = .steady
        }

        return TrajectorySummary(
            latestScore: latest,
            bestScore: chronologicalScores.max() ?? latest,
            averageScore: Int(mean(chronologicalScores).rounded()),
            delta: delta,
            momentum: momentum
        )
    }

    private static func mean<S: Sequence>(_ values: S) -> Double where S.Element == Int {
        let array = Array(values)
        guard !array.isEmpty else { return 0 }
        return Double(array.reduce(0, +)) / Double(array.count)
    }
}

// MARK: - Engine

nonisolated enum ScenarioReadinessEngine {

    /// Marker ProgressChartsContent passes for story-linked sessions instead
    /// of a prompt category.
    static let storyMarker = "Story"

    /// Compiler-checked map from every prompt category to its scenario.
    /// Categories land where the skill gets performed: evaluation settings
    /// feed Interviews, audience-facing pressure feeds Public Speaking,
    /// day-to-day talk feeds Everyday Conversation.
    static func scenario(for category: PromptCategory) -> PracticeScenario {
        switch category {
        case .interviewPrep, .professionalDevelopment, .problemSolving:
            return .interviews
        case .elevatorPitch, .debatePersuasion, .quickFire:
            return .publicSpeaking
        case .storytelling:
            return .storytelling
        case .conversationStarters, .communicationSkills, .personalGrowth,
             .describeExplain, .currentEvents:
            return .conversation
        }
    }

    /// Resolves the session-level category string. Anything unrecognizable
    /// (freeform takes, user-created categories) lands in `.other`.
    static func scenario(forRawCategory raw: String?) -> PracticeScenario {
        if raw == storyMarker { return .storytelling }
        guard let raw, !raw.isEmpty else { return .other }
        guard let category = PromptCategory(rawValue: raw) else { return .other }
        return scenario(for: category)
    }

    /// One readiness card per practiced scenario, weakest first — after the
    /// hero band answers trajectory, attention goes to the highest-leverage gap.
    /// Unpracticed core scenarios are omitted; callers render invitations.
    static func readiness(from sessions: [LexiconSessionInput]) -> [ScenarioReadiness] {
        var buckets: [PracticeScenario: [LexiconSessionInput]] = [:]
        for session in sessions {
            buckets[scenario(forRawCategory: session.category), default: []].append(session)
        }

        return buckets.compactMap { target, bucket -> ScenarioReadiness? in
            readinessCard(scenario: target, sessions: bucket.sorted { $0.date < $1.date })
        }
        .sorted { lhs, rhs in
            // Strongest signal first: lowest readiness leads, then whichever
            // bucket has more evidence behind its number.
            let lhsKey = lhs.score ?? Int.max
            let rhsKey = rhs.score ?? Int.max
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            if lhs.sessions != rhs.sessions { return lhs.sessions > rhs.sessions }
            return lhs.scenario.rawValue < rhs.scenario.rawValue
        }
    }

    private static func readinessCard(
        scenario target: PracticeScenario,
        sessions orderedBucket: [LexiconSessionInput]
    ) -> ScenarioReadiness? {
        guard !orderedBucket.isEmpty else { return nil }

        // Reuses the exact composite weights of the former aggregate
        // Interview Readiness (fluency .18, authority .20, impact .22,
        // evidence .12, depth .14, consistency .14), computed per bucket.
        let profile = LexiconInsightsEngine.profile(from: orderedBucket)

        let early = orderedBucket.count < ScenarioReadiness.confidenceThreshold
        let rawScore = profile.interviewReadiness?.score

        let momentumScores = orderedBucket.compactMap(\.overallScore)
        let trajectory = TrajectorySummary.summarize(momentumScores)

        return ScenarioReadiness(
            scenario: target,
            sessions: orderedBucket.count,
            score: early ? rawScore.map { min($0, ScenarioReadiness.earlyReadScoreCap) } : rawScore,
            isEarlyRead: early,
            momentum: trajectory.momentum,
            holdingBackWord: profile.crutchWords.first?.word,
            holdingBackCount: profile.crutchWords.first?.count
        )
    }
}
