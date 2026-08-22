import Testing
import Foundation
@testable import SpeakUp

@Suite("Scenario Readiness Engine")
struct ScenarioReadinessTests {

    private func makeSession(
        _ text: String,
        daysAgo: Double,
        fillers: [String: Int] = [:],
        score: Int? = nil,
        category: String? = nil
    ) -> LexiconSessionInput {
        LexiconSessionInput(
            date: Date(timeIntervalSinceNow: -daysAgo * 86_400),
            transcript: text,
            fillerCounts: fillers,
            overallScore: score,
            category: category
        )
    }

    /// A transcript with enough substance that depth/evidence components are
    /// stable across comparisons.
    private let substantiveText =
        "I led the migration project and delivered it two weeks early. " +
        "The team reduced build time by forty percent and saved real money. "

    // MARK: Bucketing

    @Test
    func promptCategoriesMapToScenariosExhaustively() {
        for category in PromptCategory.allCases {
            let expected: PracticeScenario
            switch category {
            case .interviewPrep, .professionalDevelopment, .problemSolving:
                expected = .interviews
            case .elevatorPitch, .debatePersuasion, .quickFire:
                expected = .publicSpeaking
            case .storytelling:
                expected = .storytelling
            case .conversationStarters, .communicationSkills, .personalGrowth,
                 .describeExplain, .currentEvents:
                expected = .conversation
            }

            #expect(ScenarioReadinessEngine.scenario(for: category) == expected)
            #expect(ScenarioReadinessEngine.scenario(forRawCategory: category.rawValue) == expected)
        }
    }

    @Test
    func storyMarkerBucketsIntoStorytelling() {
        #expect(ScenarioReadinessEngine.scenario(forRawCategory: ScenarioReadinessEngine.storyMarker) == .storytelling)
    }

    @Test
    func freeformAndUnknownCategoriesLandInEverythingElse() {
        #expect(ScenarioReadinessEngine.scenario(forRawCategory: nil) == .other)
        #expect(ScenarioReadinessEngine.scenario(forRawCategory: "") == .other)
        #expect(ScenarioReadinessEngine.scenario(forRawCategory: "My Custom Category") == .other)
    }

    @Test
    func emptyInputYieldsNoCards() {
        #expect(ScenarioReadinessEngine.readiness(from: []).isEmpty)
    }

    @Test
    func bucketsSplitByScenarioAndOmitUnpracticedOnes() {
        let cards = ScenarioReadinessEngine.readiness(from: [
            makeSession(substantiveText, daysAgo: 5, score: 70, category: PromptCategory.interviewPrep.rawValue),
            makeSession(substantiveText, daysAgo: 3, score: 72, category: PromptCategory.interviewPrep.rawValue),
            makeSession(substantiveText, daysAgo: 2, score: 74, category: ScenarioReadinessEngine.storyMarker),
        ])

        #expect(cards.count == 2)
        #expect(Set(cards.map(\.scenario)) == [.interviews, .storytelling])
        #expect(cards.first { $0.scenario == .storytelling }?.sessions == 1)

        // Unpracticed core scenarios never appear as cards.
        #expect(!cards.contains { $0.scenario == .publicSpeaking })
        #expect(!cards.contains { $0.scenario == .conversation })
    }

    // MARK: Thin data honesty

    @Test
    func thinDataIsFlaggedAsEarlyRead() throws {
        let cards = ScenarioReadinessEngine.readiness(from: [
            makeSession(substantiveText, daysAgo: 4, score: 90, category: PromptCategory.interviewPrep.rawValue),
            makeSession(substantiveText, daysAgo: 2, score: 92, category: PromptCategory.interviewPrep.rawValue),
        ])

        let interviews = try #require(cards.first)
        #expect(interviews.isEarlyRead)
        #expect(interviews.sessions == 2)
    }

    @Test
    func thinBucketCannotReachReadyBandEvenWithStrongInputs() throws {
        let cards = ScenarioReadinessEngine.readiness(from: [
            makeSession(substantiveText, daysAgo: 6, score: 95, category: PromptCategory.interviewPrep.rawValue),
            makeSession(substantiveText, daysAgo: 5, score: 96, category: PromptCategory.interviewPrep.rawValue),
            makeSession(substantiveText, daysAgo: 4, score: 97, category: PromptCategory.interviewPrep.rawValue),
        ])

        let interviews = try #require(cards.first)
        let score = try #require(interviews.score)
        #expect(interviews.isEarlyRead)
        #expect(score <= ScenarioReadiness.earlyReadScoreCap)
        #expect(interviews.bandLabel != "Ready")
    }

    @Test
    func fourSessionsClearTheThinDataFlag() throws {
        let sessions = (1...4).map { index in
            makeSession(substantiveText, daysAgo: Double(index), score: 80, category: PromptCategory.storytelling.rawValue)
        }

        let cards = ScenarioReadinessEngine.readiness(from: sessions)
        let storytelling = try #require(cards.first)
        #expect(!storytelling.isEarlyRead)
    }

    // MARK: Monotonicity

    @Test
    func betterInputsNeverLowerTheScore() throws {
        let messy = (1...4).map { index in
            makeSession(
                substantiveText,
                daysAgo: Double(index),
                fillers: ["um": 4],
                score: 60,
                category: PromptCategory.interviewPrep.rawValue
            )
        }
        let clean = (1...4).map { index in
            makeSession(
                substantiveText,
                daysAgo: Double(index),
                fillers: ["um": 1],
                score: 75,
                category: PromptCategory.interviewPrep.rawValue
            )
        }

        // Same bucket merges; per-bucket scores stay independent.
        #expect(ScenarioReadinessEngine.readiness(from: messy + clean).count == 1)

        let messyScore = try #require(
            ScenarioReadinessEngine.readiness(from: messy).first?.score
        )
        let cleanScore = try #require(
            ScenarioReadinessEngine.readiness(from: clean).first?.score
        )
        #expect(cleanScore >= messyScore)
    }

    // MARK: Ordering

    @Test
    func weakestScenarioSortsFirst() {
        var messyInterviews = [LexiconSessionInput]()
        for index in 1...4 {
            messyInterviews.append(makeSession(
                substantiveText,
                daysAgo: Double(index + 10),
                fillers: ["um": 5],
                score: 55,
                category: PromptCategory.interviewPrep.rawValue
            ))
        }
        var strongStories = [LexiconSessionInput]()
        for index in 1...4 {
            strongStories.append(makeSession(
                substantiveText,
                daysAgo: Double(index),
                score: 88,
                category: ScenarioReadinessEngine.storyMarker
            ))
        }

        let cards = ScenarioReadinessEngine.readiness(from: messyInterviews + strongStories)
        #expect(cards.first?.scenario == .interviews)
        #expect(cards.last?.scenario == .storytelling)
    }

    // MARK: Momentum

    @Test
    func trajectorySummaryVerdicts() {
        let empty = TrajectorySummary.summarize([])
        #expect(empty.latestScore == nil)
        #expect(empty.momentum == .steady)

        let flat = TrajectorySummary.summarize([60, 62])
        #expect(flat.momentum == .steady)
        #expect(flat.delta == 2)

        let rising = TrajectorySummary.summarize([50, 50, 70, 70])
        #expect(rising.latestScore == 70)
        #expect(rising.bestScore == 70)
        #expect(rising.averageScore == 60)
        #expect(rising.delta == 20)
        #expect(rising.momentum == .improving)

        let falling = TrajectorySummary.summarize([80, 80, 55, 55])
        #expect(falling.momentum == .slipping)
    }
}
