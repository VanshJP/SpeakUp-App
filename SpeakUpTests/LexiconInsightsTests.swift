import Testing
import Foundation
@testable import SpeakUp

@Suite("Lexicon Insights Engine")
struct LexiconInsightsTests {

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

    @Test
    func emptyInputReturnsEmptyProfile() {
        let profile = LexiconInsightsEngine.profile(from: [])

        #expect(profile.analyzedSessionCount == 0)
        #expect(!profile.hasData)
        #expect(profile.interviewReadiness == nil)
        #expect(profile.suggestions.isEmpty)
    }

    @Test
    func countsFillersFromPipelineDictionary() {
        let profile = LexiconInsightsEngine.profile(from: [
            makeSession("So we built the whole thing from scratch and shipped it.", daysAgo: 3, fillers: ["um": 3])
        ])

        let um = profile.crutchWords.first { $0.word == "um" }
        #expect(um?.count == 3)
        #expect(um?.category == .filler)
    }

    @Test
    func dictionaryFillersAreNotDoubleCountedFromTokens() {
        let profile = LexiconInsightsEngine.profile(from: [
            makeSession("Um um okay basically the plan worked.", daysAgo: 2, fillers: ["um": 2])
        ])

        let um = profile.crutchWords.first { $0.word == "um" }
        #expect(um?.count == 2)

        let basically = profile.crutchWords.first { $0.word == "basically" }
        #expect(basically?.count == 1)
        #expect(basically?.category == .intensifier)
    }

    @Test
    func fallsBackToTokenFillerDetectionWithoutDictionary() {
        let profile = LexiconInsightsEngine.profile(from: [
            makeSession("Uh uh okay basically the launch went fine today.", daysAgo: 1)
        ])

        let uh = profile.crutchWords.first { $0.word == "uh" }
        #expect(uh?.count == 2)
        #expect(uh?.category == .filler)
    }

    @Test
    func detectsHedgePhrasesSoftenersAndVagueNouns() {
        let profile = LexiconInsightsEngine.profile(from: [
            makeSession("I think we kind of very really just improved things.", daysAgo: 1)
        ])

        let iThink = profile.crutchWords.first { $0.word == "i think" }
        #expect(iThink?.count == 1)
        #expect(iThink?.category == .hedge)

        let very = profile.crutchWords.first { $0.word == "very" }
        #expect(very?.count == 1)
        #expect(very?.category == .intensifier)

        let things = profile.crutchWords.first { $0.word == "things" }
        #expect(things?.count == 1)
        #expect(things?.category == .vague)
    }

    @Test
    func tracksPowerVerbsAndNumericEvidence() {
        let profile = LexiconInsightsEngine.profile(from: [
            makeSession("We led a team of 30 people and increased revenue by 40 percent last year.", daysAgo: 1)
        ])

        #expect(profile.powerVerbs.contains { $0.word == "led" && $0.count == 1 })
        #expect(profile.powerVerbs.contains { $0.word == "increased" && $0.count == 1 })
    }

    @Test
    func recentHalfDrivesFallingDirection() {
        let early = LexiconSessionInput(
            date: Date(timeIntervalSinceNow: -30 * 86_400),
            transcript: "We shipped the platform migration ahead of schedule this quarter.",
            fillerCounts: ["like": 4],
            overallScore: 60
        )
        let recent = LexiconSessionInput(
            date: Date(timeIntervalSinceNow: -2 * 86_400),
            transcript: "We delivered the redesigned checkout flow and conversion climbed steadily.",
            fillerCounts: [:],
            overallScore: 72
        )

        let profile = LexiconInsightsEngine.profile(from: [early, recent])

        let like = profile.crutchWords.first { $0.word == "like" }
        #expect(like?.count == 4)
        #expect(like?.direction == .falling)
        #expect(profile.weakRateDelta < 0)
    }

    @Test
    func risingUsageFlagsRisingDirection() {
        let early = LexiconSessionInput(
            date: Date(timeIntervalSinceNow: -40 * 86_400),
            transcript: "Honestly the rollout basically went fine and everyone noticed quickly.",
            fillerCounts: [:],
            overallScore: 70
        )
        let recent = LexiconSessionInput(
            date: Date(timeIntervalSinceNow: -1 * 86_400),
            transcript: "Honestly honestly honestly basically actually literally totally the rollout dragged.",
            fillerCounts: [:],
            overallScore: 58
        )

        let profile = LexiconInsightsEngine.profile(from: [early, recent])

        let honestly = profile.crutchWords.first { $0.word == "honestly" }
        #expect(honestly?.count == 4)
        #expect(honestly?.direction == .rising)
        #expect(profile.weakRateDelta > 0)
    }

    @Test
    func readinessIsBoundedWithAllComponents() {
        let profile = LexiconInsightsEngine.profile(from: [
            makeSession("We launched the product and grew revenue by 25 percent in six months.", daysAgo: 10, score: 74),
            makeSession("I led the redesign, mentored two engineers, and cut load times by half.", daysAgo: 3, score: 81)
        ])

        guard let readiness = profile.interviewReadiness else {
            Issue.record("Expected readiness for analyzed sessions")
            return
        }

        #expect(readiness.score >= 0 && readiness.score <= 100)
        #expect(readiness.components.count == 6)
    }

    @Test
    func suggestionsIncludeTopCrutchAlternative() {
        let profile = LexiconInsightsEngine.profile(from: [
            makeSession("Like the results were strong across every single metric reported.", daysAgo: 1, fillers: ["like": 8])
        ])

        let retire = profile.suggestions.first { $0.title.contains("Retire") }
        #expect(retire != nil)
        #expect(retire?.detail.contains("for example") == true)
    }

    @Test
    func piecewiseCurveInterpolatesAndClamps() {
        #expect(LexiconInsightsEngine.piecewiseScore(5, [(input: 0, score: 100), (input: 10, score: 0)]) == 50)
        #expect(LexiconInsightsEngine.piecewiseScore(-5, [(input: 0, score: 100), (input: 10, score: 0)]) == 100)
        #expect(LexiconInsightsEngine.piecewiseScore(99, [(input: 0, score: 100), (input: 10, score: 0)]) == 0)
    }

    @Test
    func alternativesLookupNormalizesCase() {
        #expect(LexiconInsightsEngine.alternativesFor("LIKE") != nil)
        #expect(LexiconInsightsEngine.alternativesFor("unknownword") == nil)
    }

    @Test
    func categoryBreakdownSeparatesPracticeTypes() {
        let interview = makeSession(
            "I think we led the migration and increased uptime by 40 percent.",
            daysAgo: 2,
            fillers: ["um": 6],
            score: 70,
            category: "Interview Prep"
        )
        let story = makeSession(
            "The whole tale unfolded beautifully with barely any hesitation anywhere at all.",
            daysAgo: 1,
            score: 80,
            category: "Story"
        )

        let profile = LexiconInsightsEngine.profile(from: [interview, story])

        let prep = profile.categoryBreakdown.first { $0.category == "Interview Prep" }
        let storyStat = profile.categoryBreakdown.first { $0.category == "Story" }

        #expect(prep?.sessions == 1)
        #expect(prep?.topCrutch == "um")
        #expect((prep?.weakRate ?? -1) > (storyStat?.weakRate ?? 0))
    }

    @Test
    func planNamesCrutchHabitWhenFillersIsTheFocus() {
        let fillerWeak = SpeechAnalysis(speechScore: SpeechScore(
            overall: 70,
            subscores: SpeechSubscores(clarity: 90, pace: 90, fillerUsage: 40, pauseQuality: 90)
        ))

        guard let plan = CoachPlanService.plan(
            window: Array(repeating: fillerWeak, count: 5),
            crutchHint: CrutchHint(word: "like", count: 9)
        ) else {
            Issue.record("Expected a plan")
            return
        }

        #expect(plan.focus == .fillers)
        #expect(plan.namedHabit == "like")
        #expect(plan.headline.contains("\u{201C}like\u{201D}"))
    }

    @Test
    func namedHabitStaysNilBelowThresholdOrOffFocus() {
        let fillerWeak = SpeechAnalysis(speechScore: SpeechScore(
            overall: 70,
            subscores: SpeechSubscores(clarity: 90, pace: 90, fillerUsage: 40, pauseQuality: 90)
        ))
        let paceWeak = SpeechAnalysis(speechScore: SpeechScore(
            overall: 70,
            subscores: SpeechSubscores(clarity: 90, pace: 30, fillerUsage: 95, pauseQuality: 90)
        ))

        let belowThreshold = CoachPlanService.plan(
            window: Array(repeating: fillerWeak, count: 5),
            crutchHint: CrutchHint(word: "like", count: 2)
        )
        #expect(belowThreshold?.namedHabit == nil)

        let offFocus = CoachPlanService.plan(
            window: Array(repeating: paceWeak, count: 5),
            crutchHint: CrutchHint(word: "like", count: 9)
        )
        #expect(offFocus?.focus == .pace)
        #expect(offFocus?.namedHabit == nil)
    }

    // MARK: Session hits

    private func timedWords(_ text: String, fillers: Set<String> = []) -> [TranscriptionWord] {
        var start = 0.0
        return text.split(separator: " ").map { raw in
            defer { start += 0.5 }
            return TranscriptionWord(
                word: String(raw),
                start: start,
                end: start + 0.4,
                isFiller: fillers.contains(String(raw))
            )
        }
    }

    @Test
    func sessionHitsCarryTimestampsAndCategories() {
        let words = timedWords(
            "um we basically launched like the product",
            fillers: ["um", "like"]
        )

        let hits = LexiconInsightsEngine.sessionHits(from: words)

        let um = hits.first { $0.word == "um" }
        #expect(um?.count == 1)
        #expect(um?.category == .filler)
        #expect(um?.timestamps == [0.0])

        let like = hits.first { $0.word == "like" }
        #expect(like?.category == .filler)
        #expect(like?.timestamps == [2.0])

        let basically = hits.first { $0.word == "basically" }
        #expect(basically?.count == 1)
        #expect(basically?.category == .intensifier)
    }

    @Test
    func repeatedWordsAccumulateSortedStamps() {
        let words = timedWords("um okay so um fine um done", fillers: ["um"])

        let um = LexiconInsightsEngine.sessionHits(from: words).first { $0.word == "um" }

        #expect(um?.count == 3)
        #expect(um?.timestamps == [0.0, 1.5, 2.5])
        #expect(hitsAreRankedByCount(LexiconInsightsEngine.sessionHits(from: words)))
    }

    private func hitsAreRankedByCount(_ hits: [SessionWordHit]) -> Bool {
        zip(hits, hits.dropFirst()).allSatisfy { $0.count >= $1.count }
    }

    @Test
    func hedgePhrasesConsumeTheirTokens() {
        let words = timedWords("not really sure about it i think")

        let hits = LexiconInsightsEngine.sessionHits(from: words)

        #expect(hits.first { $0.word == "not really sure" }?.category == .hedge)
        #expect(hits.contains { $0.word == "i think" })
        #expect(!hits.contains { $0.word == "really" })
    }

    @Test
    func swapsOfferSeveralAlternativesAndFallbacks() {
        // Every mapped word carries multiple options.
        for (_, options) in LexiconInsightsEngine.alternatives {
            #expect(!options.isEmpty)
        }

        let verySwaps = LexiconInsightsEngine.alternativesFor("very") ?? []
        #expect(verySwaps.count >= 3)

        // Unmapped words still get category-level advice instead of nothing.
        let fallback = SessionWordHit(word: "zzzunmapped", category: .vague, count: 4, timestamps: [])
        #expect(fallback.swaps == ["name the specifics"])
    }
}
