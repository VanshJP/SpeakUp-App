import Foundation

// MARK: - Goal → Category Mapping

extension OnboardingGoal {
    nonisolated var promptCategories: [PromptCategory] {
        switch self {
        case .interviews:
            return [.interviewPrep, .professionalDevelopment, .quickFire]
        case .meetings:
            return [.professionalDevelopment, .communicationSkills, .describeExplain]
        case .presentations:
            return [.elevatorPitch, .debatePersuasion, .communicationSkills]
        case .everydayConfidence:
            return [.conversationStarters, .personalGrowth, .describeExplain]
        case .storytelling:
            return [.storytelling, .personalGrowth, .currentEvents]
        }
    }
}

// MARK: - Prompt Mix

/// How often each prompt category should surface, given the goals the user
/// picked during onboarding and the categories they left enabled in Settings.
///
nonisolated struct PromptMix: Equatable, Sendable {
    static let favoredWeight = 3
    static let neutralWeight = 1

    /// Category name → weight. Names rather than `PromptCategory` cases because
    /// prompts (including user-created ones) carry free-form category strings,
    /// and a category that isn't in the enum should still be reachable.
    private let weights: [String: Int]

    /// Every category weighted equally. The fallback whenever there is nothing
    /// to bias with, and the behaviour the app had before goals steered anything.
    static let uniform = PromptMix(weights: [:])

    private init(weights: [String: Int]) {
        self.weights = weights
    }

    /// - Parameters:
    ///   - goals: Goals picked during onboarding. Empty means no bias.
    ///   - enabledCategoryNames: The user's Settings gate. Empty means "no
    ///     gate recorded" (fresh install, or a settings row that predates the
    ///     field), which is treated as everything enabled rather than nothing.
    init(goals: [OnboardingGoal], enabledCategoryNames: Set<String>) {
        let favored = Set(goals.flatMap { $0.promptCategories }.map(\.rawValue))

        let gate: Set<String>? = enabledCategoryNames.isEmpty ? nil : enabledCategoryNames

        guard !favored.isEmpty || gate != nil else {
            self = .uniform
            return
        }

        var weights: [String: Int] = [:]
        for category in PromptCategory.allCases {
            let name = category.rawValue
            if let gate, !gate.contains(name) {
                weights[name] = 0
                continue
            }
            weights[name] = favored.contains(name) ? Self.favoredWeight : Self.neutralWeight
        }
        self.weights = weights
    }

    func weight(forCategory category: String) -> Int {
        weights[category] ?? Self.neutralWeight
    }

    // MARK: Weakness adaptation

    /// Sessions of one practice type before its language stats count as
    /// evidence rather than noise.
    static let adaptiveMinimumSessions = 2

    static let adaptiveBoostThreshold: Double = 6.0

    /// A copy of this mix with struggling practice types weighted up, built
    /// from the cross-session lexicon profile (`LexiconInsightsEngine`).
    ///
    nonisolated func adapted(weakRatesByCategory: [String: (sessions: Int, weakRate: Double)]) -> PromptMix {
        guard !weakRatesByCategory.isEmpty else { return self }

        var adjusted = weights
        var didChange = false

        for (category, sample) in weakRatesByCategory {
            guard sample.sessions >= Self.adaptiveMinimumSessions,
                  let base = adjusted[category], base > 0,
                  sample.weakRate > Self.adaptiveBoostThreshold
            else { continue }

            let strength = min(1.0, (sample.weakRate - Self.adaptiveBoostThreshold) / 8.0)
            let boosted = min(
                Int((Double(base) * (1.0 + strength)).rounded()),
                base * 2
            )
            if boosted > base {
                adjusted[category] = boosted
                didChange = true
            }
        }

        return didChange ? PromptMix(weights: adjusted) : self
    }

    func pick<T>(from candidates: [T], seed: Int, category: (T) -> String) -> T? {
        guard !candidates.isEmpty else { return nil }

        let weighted = candidates.map { (item: $0, weight: weight(forCategory: category($0))) }
        let total = weighted.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }

        var remaining = abs(seed) % total
        for entry in weighted {
            guard entry.weight > 0 else { continue }
            if remaining < entry.weight { return entry.item }
            remaining -= entry.weight
        }
        // Unreachable while `total` is the sum of the same weights, but a
        // last-resort element beats a crash if that ever stops being true.
        return weighted.last(where: { $0.weight > 0 })?.item
    }

    func pickRandom<T>(from candidates: [T], category: (T) -> String) -> T? {
        pick(from: candidates, seed: Int.random(in: 0..<1_000_000), category: category)
    }
}
