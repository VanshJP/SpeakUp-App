import Foundation

// MARK: - Goal → Category Mapping

extension OnboardingGoal {
    /// Prompt categories this goal leans on. Deliberately overlapping across
    /// goals: a user who picks Meetings and Presentations should see the
    /// shared communication material more often than either goal alone would
    /// suggest, which is what "the app listened" means for a multi-pick.
    var promptCategories: [PromptCategory] {
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
/// Two rules, in this order:
/// 1. **Settings is a gate.** A category the user switched off in
///    `PromptSettingsView` gets weight 0 and never appears. Onboarding is a
///    first-run guess; an explicit toggle is a decision, and the decision wins.
/// 2. **Goals are a bias, not a filter.** Categories the picked goals lean on
///    are weighted up; every other enabled category still shows up. A user who
///    picked Interviews should mostly get interview-shaped prompts without the
///    prompt pool silently shrinking to one drawer.
///
/// Pure value type — no SwiftData, no `Prompt` rows — so the distribution is
/// testable on its own and callers can build one per load instead of querying
/// settings per prompt.
struct PromptMix: Equatable, Sendable {
    /// Multiplier applied to categories the user's goals lean on. Three means a
    /// favored category is drawn roughly three times as often as a neutral one.
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

        // A gate that excludes every favored category and leaves nothing to
        // draw from would strand the user on an empty pool, so treat an empty
        // gate as no gate at all.
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

    /// Weight for a prompt's category string. Unknown categories (user-created
    /// prompts, or a category added to the enum after a settings row was
    /// written) count as neutral so they stay reachable.
    func weight(forCategory category: String) -> Int {
        weights[category] ?? Self.neutralWeight
    }

    /// Deterministic weighted pick over `candidates`, keyed on `seed`. The same
    /// seed and the same pool always return the same element, which is what
    /// keeps the daily prompt stable across re-fetches.
    ///
    /// Returns nil only when `candidates` is empty or every candidate is gated
    /// out — the caller decides what to fall back to, since it knows whether it
    /// is picking a daily prompt or a reroll.
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

    /// Weighted pick with a random seed, for rerolls and the prompt wheel.
    func pickRandom<T>(from candidates: [T], category: (T) -> String) -> T? {
        pick(from: candidates, seed: Int.random(in: 0..<1_000_000), category: category)
    }
}
