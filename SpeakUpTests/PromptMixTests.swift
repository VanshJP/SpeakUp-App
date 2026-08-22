import Testing
import Foundation
@testable import SpeakUp

// The prompt mix decides what a user meets on Today every morning. Getting it
// wrong is either invisible (goals do nothing) or loud (the pool collapses to
// one category, or empties entirely), so the weighting and every fallback are
// pinned here.

struct PromptMixWeightTests {
    private let allCategories = Set(PromptCategory.allCases.map(\.rawValue))

    @Test func goalCategoriesOutweighTheRest() {
        let mix = PromptMix(goals: [.interviews], enabledCategoryNames: allCategories)

        #expect(mix.weight(forCategory: PromptCategory.interviewPrep.rawValue) == PromptMix.favoredWeight)
        #expect(mix.weight(forCategory: PromptCategory.storytelling.rawValue) == PromptMix.neutralWeight)
    }

    @Test func everyGoalContributesItsCategories() {
        let mix = PromptMix(
            goals: [.interviews, .storytelling],
            enabledCategoryNames: allCategories
        )

        #expect(mix.weight(forCategory: PromptCategory.interviewPrep.rawValue) == PromptMix.favoredWeight)
        #expect(mix.weight(forCategory: PromptCategory.storytelling.rawValue) == PromptMix.favoredWeight)
    }

    @Test func nonGoalCategoriesStayReachable() {
        let mix = PromptMix(goals: [.interviews], enabledCategoryNames: allCategories)

        // Bias, not filter: an unfavored-but-enabled category must never be
        // weighted to zero, or the "full pool stays available" promise breaks.
        for category in PromptCategory.allCases where !OnboardingGoal.interviews.promptCategories.contains(category) {
            #expect(mix.weight(forCategory: category.rawValue) > 0)
        }
    }

    @Test func disabledCategoriesAreExcluded() {
        // Settings beats onboarding: Interview Prep is favored by the goal but
        // switched off by the user, so it must not surface at all.
        let enabled = allCategories.subtracting([PromptCategory.interviewPrep.rawValue])
        let mix = PromptMix(goals: [.interviews], enabledCategoryNames: enabled)

        #expect(mix.weight(forCategory: PromptCategory.interviewPrep.rawValue) == 0)
        #expect(mix.weight(forCategory: PromptCategory.professionalDevelopment.rawValue) == PromptMix.favoredWeight)
    }

    @Test func emptyGateMeansNoGate() {
        // An empty stored category list is "nothing recorded yet", not "user
        // disabled everything" — treating it as the latter empties Today.
        let mix = PromptMix(goals: [.meetings], enabledCategoryNames: [])

        #expect(mix.weight(forCategory: PromptCategory.communicationSkills.rawValue) == PromptMix.favoredWeight)
        #expect(mix.weight(forCategory: PromptCategory.quickFire.rawValue) == PromptMix.neutralWeight)
    }

    @Test func noGoalsIsUniform() {
        let mix = PromptMix(goals: [], enabledCategoryNames: [])

        for category in PromptCategory.allCases {
            #expect(mix.weight(forCategory: category.rawValue) == PromptMix.neutralWeight)
        }
    }

    @Test func unknownCategoryIsNeutral() {
        // User-created prompts carry free-form categories; they should still be
        // drawable rather than silently weighted out.
        let mix = PromptMix(goals: [.interviews], enabledCategoryNames: allCategories)

        #expect(mix.weight(forCategory: "My Own Category") == PromptMix.neutralWeight)
    }
}

struct PromptMixSelectionTests {
    private struct Item {
        let name: String
        let category: String
    }

    private let allCategories = Set(PromptCategory.allCases.map(\.rawValue))

    @Test func emptyCandidatesReturnsNil() {
        let mix = PromptMix.uniform
        #expect(mix.pick(from: [Item](), seed: 7, category: \.category) == nil)
    }

    @Test func fullyGatedPoolReturnsNil() {
        // The caller needs to know the pool was gated out so it can widen the
        // search, rather than being handed a prompt the user disabled.
        let enabled = allCategories.subtracting([PromptCategory.quickFire.rawValue])
        let mix = PromptMix(goals: [], enabledCategoryNames: enabled)
        let candidates = [Item(name: "a", category: PromptCategory.quickFire.rawValue)]

        #expect(mix.pick(from: candidates, seed: 3, category: \.category) == nil)
    }

    @Test func sameSeedPicksSameItem() {
        let mix = PromptMix(goals: [.interviews], enabledCategoryNames: allCategories)
        let candidates = PromptCategory.allCases.map { Item(name: $0.rawValue, category: $0.rawValue) }

        let first = mix.pick(from: candidates, seed: 4242, category: \.category)
        let second = mix.pick(from: candidates, seed: 4242, category: \.category)

        #expect(first?.name == second?.name)
    }

    @Test func favoredCategoriesWinTheLongRun() {
        let mix = PromptMix(goals: [.interviews], enabledCategoryNames: allCategories)
        let candidates = PromptCategory.allCases.map { Item(name: $0.rawValue, category: $0.rawValue) }
        let favored = Set(OnboardingGoal.interviews.promptCategories.map(\.rawValue))

        var favoredHits = 0
        for seed in 0..<600 {
            if let pick = mix.pick(from: candidates, seed: seed, category: \.category),
               favored.contains(pick.category) {
                favoredHits += 1
            }
        }

        // 3 favored of 12 categories at 3x weight ≈ 9/18 of draws. Asserting a
        // band rather than an exact count so weight tuning doesn't break the
        // test, but a regression to unweighted (3/12 = 25%) still fails.
        let share = Double(favoredHits) / 600
        #expect(share > 0.4)
        #expect(share < 0.6)
    }
}

struct PromptMixAdaptationTests {
    private let allCategories = Set(PromptCategory.allCases.map(\.rawValue))

    private var baseMix: PromptMix {
        PromptMix(goals: [.interviews], enabledCategoryNames: allCategories)
    }

    @Test func strugglingNeutralCategoryGetsBoosted() {
        let adapted = baseMix.adapted(weakRatesByCategory: [
            PromptCategory.storytelling.rawValue: (sessions: 4, weakRate: 10.0)
        ])

        #expect(adapted.weight(forCategory: PromptCategory.storytelling.rawValue) == PromptMix.neutralWeight * 2)
    }

    @Test func favoredCategoryAlsoBoosts() {
        let adapted = baseMix.adapted(weakRatesByCategory: [
            PromptCategory.interviewPrep.rawValue: (sessions: 5, weakRate: 14.0)
        ])

        #expect(adapted.weight(forCategory: PromptCategory.interviewPrep.rawValue) == PromptMix.favoredWeight * 2)
    }

    @Test func healthyOrThinEvidenceChangesNothing() {
        let base = baseMix

        let belowThreshold = base.adapted(weakRatesByCategory: [
            PromptCategory.storytelling.rawValue: (sessions: 6, weakRate: 5.0)
        ])
        #expect(belowThreshold == base)

        let thinEvidence = base.adapted(weakRatesByCategory: [
            PromptCategory.storytelling.rawValue: (sessions: 1, weakRate: 20.0)
        ])
        #expect(thinEvidence == base)

        let emptyInput = base.adapted(weakRatesByCategory: [:])
        #expect(emptyInput == base)
    }

    @Test func settingsGateBeatsWeakness() {
        let enabled = allCategories.subtracting([PromptCategory.storytelling.rawValue])
        let gated = PromptMix(goals: [.storytelling], enabledCategoryNames: enabled)

        let adapted = gated.adapted(weakRatesByCategory: [
            PromptCategory.storytelling.rawValue: (sessions: 9, weakRate: 18.0)
        ])

        #expect(adapted.weight(forCategory: PromptCategory.storytelling.rawValue) == 0)
    }

    @Test func adaptationSteersTheDailyPick() {
        // The point of the feature: with interview prep measurably weak, a
        // seed sweep must surface it more often than the unadapted mix does.
        let weakCategory = PromptCategory.interviewPrep.rawValue
        let candidates = PromptCategory.allCases.map { Item(name: $0.rawValue, category: $0.rawValue) }
        let adapted = baseMix.adapted(weakRatesByCategory: [weakCategory: (sessions: 6, weakRate: 12.0)])

        func hits(_ mix: PromptMix) -> Int {
            (0..<600).reduce(0) { count, seed in
                if let pick = mix.pick(from: candidates, seed: seed, category: \.category),
                   pick.category == weakCategory {
                    return count + 1
                }
                return count
            }
        }

        #expect(hits(adapted) > hits(baseMix))
    }

    private struct Item {
        let name: String
        let category: String
    }
}

struct DefaultPromptsMixTests {
    @Test func todaysPromptIsStableAcrossCalls() {
        let mix = PromptMix(
            goals: [.storytelling],
            enabledCategoryNames: Set(PromptCategory.allCases.map(\.rawValue))
        )

        let first = DefaultPrompts.getTodaysPrompt(for: .intermediate, mix: mix)
        let second = DefaultPrompts.getTodaysPrompt(for: .intermediate, mix: mix)

        #expect(first.id == second.id)
    }

    @Test func mixNeverBreaksTheDifficultyRamp() {
        // Goals steer category only. A beginner's daily prompt must still come
        // from the difficulty bucket the speaker level chose.
        let mix = PromptMix(
            goals: [.interviews],
            enabledCategoryNames: Set(PromptCategory.allCases.map(\.rawValue))
        )
        let unbiased = DefaultPrompts.getTodaysPrompt(for: .beginner, mix: .uniform)
        let biased = DefaultPrompts.getTodaysPrompt(for: .beginner, mix: mix)

        #expect(biased.difficulty == unbiased.difficulty)
    }

    @Test func everyGoalMapsToRealCategoriesWithPrompts() {
        // A typo in the goal → category map would silently de-weight a whole
        // goal, so assert each mapped category actually has prompts behind it.
        let categoriesInUse = Set(DefaultPrompts.all.map(\.category))

        for goal in OnboardingGoal.allCases {
            #expect(!goal.promptCategories.isEmpty)
            for category in goal.promptCategories {
                #expect(categoriesInUse.contains(category.rawValue))
            }
        }
    }

    @Test func disabledFavoredCategoryStillYieldsAPrompt() {
        // Worst case: the user disabled every category their goal favors. They
        // must still get a prompt rather than an empty Today card.
        let favored = Set(OnboardingGoal.interviews.promptCategories.map(\.rawValue))
        let enabled = Set(PromptCategory.allCases.map(\.rawValue)).subtracting(favored)
        let mix = PromptMix(goals: [.interviews], enabledCategoryNames: enabled)

        let prompt = DefaultPrompts.getTodaysPrompt(for: .intermediate, mix: mix)

        #expect(!favored.contains(prompt.category))
    }
}
