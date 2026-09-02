import Testing
import Foundation
@testable import SpeakUp

// The coaching layer is pure functions over PODs, so all of it is testable
// without a container. What is worth testing is the judgement: does the focus
// stay put, does the ranking follow impact rather than declaration order, and
// does the advanced-metric round-trip actually survive.

// MARK: - Helpers

private func analysis(
    overall: Int = 70,
    clarity: Int = 70,
    pace: Int = 70,
    filler: Int = 70,
    pause: Int = 70,
    vocalVariety: Int? = nil,
    delivery: Int? = nil,
    vocabulary: Int? = nil,
    structure: Int? = nil,
    relevance: Int? = nil,
    wpm: Double = 150,
    totalWords: Int = 120,
    fillerWords: [FillerWord] = []
) -> SpeechAnalysis {
    SpeechAnalysis(
        fillerWords: fillerWords,
        totalWords: totalWords,
        wordsPerMinute: wpm,
        pauseCount: 6,
        averagePauseLength: 1.1,
        strategicPauseCount: 4,
        hesitationPauseCount: 2,
        clarity: Double(clarity),
        speechScore: SpeechScore(
            overall: overall,
            subscores: SpeechSubscores(
                clarity: clarity,
                pace: pace,
                fillerUsage: filler,
                pauseQuality: pause,
                vocalVariety: vocalVariety,
                delivery: delivery,
                vocabulary: vocabulary,
                structure: structure,
                relevance: relevance
            )
        )
    )
}

// MARK: - Plan

@MainActor
struct CoachPlanTests {
    @Test func emptyWindowHasNoPlan() {
        #expect(CoachPlanService.plan(window: []) == nil)
    }

    @Test func zeroScoredSessionsAreIgnored() {
        // A zero overall is the zero-word gate firing — a dead microphone, not
        // a weakness. Coaching off those invents problems the user never had.
        let dead = analysis(overall: 0, clarity: 0, pace: 0, filler: 0, pause: 0)
        #expect(CoachPlanService.plan(window: [dead, dead]) == nil)
    }

    @Test func focusIsTheLargestWeightedDeficitNotTheLowestScore() {
        // Relevance is lower, but it carries 0.06 of the score while clarity
        // carries 0.18 — clarity is the bigger lever and must win.
        let session = analysis(clarity: 55, pace: 90, filler: 90, pause: 90, relevance: 50)
        let plan = CoachPlanService.plan(window: Array(repeating: session, count: 5))
        #expect(plan?.focus == .clarity)
    }

    @Test func focusSurvivesOneOffSession() {
        // The point of averaging: a single good day must not move the focus,
        // or the user is sent somewhere new every session and trains nothing.
        let weak = analysis(clarity: 50)
        let strong = analysis(clarity: 95)
        let plan = CoachPlanService.plan(window: [strong] + Array(repeating: weak, count: 5))
        #expect(plan?.focus == .clarity)
    }

    @Test func trendNeedsHistoryBeforeItClaimsDirection() {
        let session = analysis(clarity: 50)
        let plan = CoachPlanService.plan(window: Array(repeating: session, count: 2))
        #expect(plan?.trend == .new)
    }

    @Test func improvingTrendReadsNewestHalfAgainstOldest() {
        // Newest-first: four recent 80s against four older 50s.
        let window = Array(repeating: analysis(clarity: 80), count: 4)
            + Array(repeating: analysis(clarity: 50), count: 4)
        let plan = CoachPlanService.plan(window: window)
        guard case .improving(let delta)? = plan?.trend else {
            Issue.record("expected improving, got \(String(describing: plan?.trend))")
            return
        }
        #expect(delta == 30)
    }

    @Test func slippingTrendIsReportedAsPositiveMagnitude() {
        let window = Array(repeating: analysis(clarity: 50), count: 4)
            + Array(repeating: analysis(clarity: 80), count: 4)
        guard case .slipping(let delta)? = CoachPlanService.plan(window: window)?.trend else {
            Issue.record("expected slipping")
            return
        }
        #expect(delta == 30)
    }

    @Test func noiseInsideThreebPointsReadsAsFlat() {
        let window = [analysis(clarity: 62), analysis(clarity: 61), analysis(clarity: 60), analysis(clarity: 60)]
        #expect(CoachPlanService.plan(window: window)?.trend == .flat)
    }

    @Test func masteredDimensionsAreListedAsHolding() {
        let session = analysis(clarity: 60, pace: 92, filler: 95, pause: 90)
        let plan = CoachPlanService.plan(window: Array(repeating: session, count: 5))
        #expect(plan?.holding.contains(.pace) == true)
        #expect(plan?.holding.contains(.clarity) == false)
    }

    @Test func failedCapturesDoNotRedirectThePlan() {
        // Today used to run its own focus logic that averaged these in, so a
        // single silent recording could redirect the whole practice plan.
        let real = analysis(clarity: 80, pace: 80, filler: 55, pause: 80)
        let dead = analysis(overall: 0, clarity: 0, pace: 0, filler: 0, pause: 0)
        let plan = CoachPlanService.plan(window: [dead, real, real, real, real])
        #expect(plan?.focus == .fillers)
        #expect(plan?.sessionCount == 4)
    }

    @Test func userWeightsChangeTheFocus() {
        // Same session, different weights: whichever dimension the user says
        // matters is the one they get sent after.
        let session = analysis(clarity: 60, pace: 60, filler: 90, pause: 90)
        var paceHeavy = ScoreWeights.defaults
        paceHeavy.pace = 0.9
        paceHeavy.clarity = 0.01
        let plan = CoachPlanService.plan(window: Array(repeating: session, count: 5), weights: paceHeavy)
        #expect(plan?.focus == .pace)
    }

    @Test func analyticsSlugsMatchTheShippedFunnelNames() {
        // These strings predate CoachDimension. Renaming one forks its series.
        #expect(CoachDimension.fillers.analyticsSlug == "filler")
        #expect(CoachDimension.pauses.analyticsSlug == "pause")
        #expect(CoachDimension.vocalVariety.analyticsSlug == "vocal_variety")
        #expect(CoachDimension.clarity.analyticsSlug == "clarity")
    }

    @Test func everyDimensionRoutesSomewhereReal() {
        // A wrong suggestion is worse than none: routing vocal variety at
        // Pause Practice put "Try Pause Practice" under a tip about widening
        // your pitch range, which reads as the app being broken.
        for dimension in CoachDimension.allCases {
            guard case .drill(let raw) = dimension.practiceRoute else { continue }
            #expect(
                DrillMode(rawValue: raw) != nil,
                "\(dimension.rawValue) points at a drill that does not exist"
            )
        }
    }

    @Test func scoredDimensionsLandOnMatchingTools() {
        #expect(CoachDimension.clarity.practiceRoute == .readAloud)
        #expect(CoachDimension.vocalVariety.practiceRoute == .drill("vocalVariety"))
        #expect(CoachDimension.delivery.practiceRoute == .drill("emphasis"))
        #expect(CoachDimension.fillers.practiceRoute == .drill("fillerElimination"))
    }
}

// MARK: - Tips

@MainActor
struct CoachingTipTests {
    @Test func emptySessionSaysSoInsteadOfCoachingZeros() {
        let empty = analysis(overall: 0, clarity: 0, pace: 0, filler: 0, pause: 0, wpm: 0, totalWords: 0)
        let tips = CoachingTipService.generateTips(from: empty)
        #expect(tips.count == 1)
        #expect(tips[0].dimension == nil)
    }

    @Test func neverReturnsNothing() {
        let perfect = analysis(overall: 95, clarity: 95, pace: 95, filler: 95, pause: 95)
        #expect(!CoachingTipService.generateTips(from: perfect).isEmpty)
    }

    @Test func capsAtThree() {
        let bad = analysis(
            overall: 30, clarity: 20, pace: 20, filler: 20, pause: 20,
            vocalVariety: 20, delivery: 20, vocabulary: 20, structure: 20, relevance: 20
        )
        #expect(CoachingTipService.generateTips(from: bad).count <= CoachingTipService.maximumTips)
    }

    @Test func signalWarningsNeverDisplaceCoaching() {
        // The old ordering evaluated these first, so a noisy room could spend
        // two of three slots on microphone advice while a 20 went unmentioned.
        var noisy = analysis(
            overall: 30, clarity: 20, pace: 20, filler: 20, pause: 20,
            vocalVariety: 20, delivery: 20
        )
        noisy.audioIsolationMetrics = AudioIsolationMetrics(
            estimatedInputSNRDb: 2, estimatedOutputSNRDb: 4,
            suppressionDeltaDb: 2, suppressionScore: 30, residualNoiseScore: 20
        )
        let tips = CoachingTipService.generateTips(from: noisy)
        #expect(tips.allSatisfy { $0.kind != .signal })
    }

    @Test func paceAdviceFollowsTheUsersTargetNotAFixedBand() {
        // 175 WPM is "too fast" against a 150 target and correct against 180.
        // The old copy hardcoded 130-170 and contradicted the score whenever
        // auto-calibration moved the target.
        let fast = analysis(pace: 60, wpm: 175)
        let againstDefault = CoachingTipService.generateTips(
            from: fast,
            context: CoachingContext(targetWPM: 150)
        )
        #expect(againstDefault.contains { $0.message.contains("150") })

        let againstFastTarget = CoachingTipService.generateTips(
            from: fast,
            context: CoachingContext(targetWPM: 180)
        )
        #expect(againstFastTarget.contains { $0.message.contains("180") })
        #expect(!againstFastTarget.contains { $0.title == "Slow Down" })
    }

    @Test func focusLeadsEvenWhenAnotherDimensionScoredWorse() {
        let session = analysis(clarity: 40, pace: 80, filler: 20, pause: 80)
        let plan = CoachPlanService.plan(window: Array(repeating: analysis(clarity: 40), count: 5))
        let tips = CoachingTipService.generateTips(
            from: session,
            context: CoachingContext(plan: plan)
        )
        #expect(tips.first?.dimension == plan?.focus)
        #expect(tips.first?.kind == .focus)
    }

    @Test func focusStillAppearsOnASessionWhereItWentWell() {
        // Otherwise the thread the user is following silently disappears on a
        // good day and they lose track of what they were working on.
        let session = analysis(clarity: 95, pace: 40, filler: 40, pause: 40)
        let plan = CoachPlanService.plan(window: Array(repeating: analysis(clarity: 40), count: 5))
        let tips = CoachingTipService.generateTips(
            from: session,
            context: CoachingContext(plan: plan)
        )
        #expect(tips.contains { $0.dimension == .clarity })
    }

    @Test func tipsCarryAHearableMomentWhenOneExists() {
        // A tip the user can play is worth several they can only read. If this
        // is nil the "Hear it" pill disappears and the coaching goes back to
        // being a number they have no memory of.
        var evidence = CoachEvidence()
        evidence.fillerBurst = (count: 4, start: 38, end: 52, word: "um")
        evidence.longestHesitation = (at: 71, seconds: 2.4)

        let tips = CoachingTipService.generateTips(
            from: analysis(filler: 40, pause: 40, fillerWords: [FillerWord(word: "um", count: 7, timestamps: [38, 41, 47, 52])]),
            context: CoachingContext(evidence: evidence)
        )
        #expect(tips.first { $0.dimension == .fillers }?.evidenceTime == 38)
        #expect(tips.first { $0.dimension == .pauses }?.evidenceTime == 71)
    }

    @Test func fillerTipFallsBackToTheFirstOccurrence() {
        // No cluster, but the timestamps still exist — the tip should still be
        // playable rather than silently losing the affordance.
        let tips = CoachingTipService.generateTips(
            from: analysis(filler: 40, fillerWords: [FillerWord(word: "uh", count: 2, timestamps: [12, 90])])
        )
        #expect(tips.first { $0.dimension == .fillers }?.evidenceTime == 12)
    }

    @Test func fillerTipTitleIsDirectNotShameful() {
        // High filler load should name the habit, not moralize about "costing you."
        let heavy = analysis(
            filler: 30,
            totalWords: 100,
            fillerWords: [FillerWord(word: "um", count: 12, timestamps: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])]
        )
        let tips = CoachingTipService.generateTips(from: heavy)
        let filler = tips.first { $0.dimension == .fillers }
        #expect(filler?.title == "Name the Crutch")
        #expect(filler?.title.contains("Costing") != true)
    }

    @Test func winTipsHaveNothingToPlay() {
        let strong = analysis(overall: 92, clarity: 92, pace: 90, filler: 95, pause: 90)
        let tips = CoachingTipService.generateTips(from: strong)
        #expect(tips.allSatisfy { $0.kind != .win || $0.evidenceTime == nil })
    }

    @Test func evidenceIsQuotedWhenAvailable() {
        var evidence = CoachEvidence()
        evidence.fillerBurst = (count: 4, start: 38, end: 52, word: "um")
        let tips = CoachingTipService.generateTips(
            from: analysis(filler: 40, fillerWords: [FillerWord(word: "um", count: 7, timestamps: [38, 41, 47, 52])]),
            context: CoachingContext(evidence: evidence)
        )
        #expect(tips.contains { $0.message.contains("0:38") && $0.message.contains("0:52") })
    }

    @Test func structuralTipUsesStructureCopyAndPracticeRoute() throws {
        var evidence = CoachEvidence()
        evidence.structuralRepetition = (
            frame: "i'm going to get",
            count: 3,
            start: 4.0,
            example: "I'm going to get socks / I'm going to get tomatoes / I'm going to get eggs"
        )
        let tips = CoachingTipService.generateTips(
            from: analysis(
                filler: 40,
                structure: 90,
                fillerWords: [
                    FillerWord(
                        word: "i'm going to get",
                        count: 3,
                        timestamps: [4, 8, 12],
                        kind: .structural
                    )
                ]
            ),
            context: CoachingContext(evidence: evidence)
        )
        let tip = try #require(tips.first { $0.dimension == .structure })
        #expect(tip.title == "Vary the Opening")
        #expect(tip.message.contains("i'm going to get"))
        #expect(tip.message.contains("socks"))
        #expect(tip.suggestedPractice == CoachDimension.structure.practiceRoute)
        #expect(tip.suggestedPractice != CoachDimension.fillers.practiceRoute)
        #expect(tip.evidenceTime == 4.0)
        // Must not also moralize structural frames as classic filler tips.
        #expect(tips.first { $0.dimension == .fillers } == nil)
    }

    @Test func classicFillerTipIgnoresStructuralRows() throws {
        let tips = CoachingTipService.generateTips(
            from: analysis(
                filler: 40,
                fillerWords: [
                    FillerWord(word: "um", count: 4, timestamps: [1, 2, 3, 4], kind: .filler),
                    FillerWord(
                        word: "i'm going to get",
                        count: 3,
                        timestamps: [10, 20, 30],
                        kind: .structural
                    )
                ]
            )
        )
        let filler = try #require(tips.first { $0.dimension == .fillers })
        #expect(filler.message.contains("um"))
        #expect(!filler.message.contains("i'm going to get"))
    }
}

// MARK: - Evidence

@MainActor
struct CoachEvidenceTests {
    @Test func findsTheDensestBurstNotTheWholeCount() {
        // Seven "um"s over two minutes sounds fine; four inside twelve seconds
        // is what the listener actually noticed.
        let fillers = [FillerWord(word: "um", count: 7, timestamps: [2, 40, 44, 48, 52, 95, 110])]
        let evidence = CoachEvidenceService.evidence(
            for: analysis(fillerWords: fillers),
            words: nil
        )
        #expect(evidence.fillerBurst?.count == 4)
        #expect(evidence.fillerBurst?.start == 40)
        #expect(evidence.fillerBurst?.end == 52)
    }

    @Test func structuralBurstDoesNotPolluteClassicFillerBurst() {
        // Classic ums must sit inside the 15s burst window; structural stamps
        // stay out of fillerBurst even when denser.
        let fillers = [
            FillerWord(word: "um", count: 3, timestamps: [10, 12, 14], kind: .filler),
            FillerWord(
                word: "i'm going to get",
                count: 3,
                timestamps: [20, 25, 30],
                kind: .structural
            )
        ]
        let evidence = CoachEvidenceService.evidence(
            for: analysis(fillerWords: fillers),
            words: nil
        )
        #expect(evidence.fillerBurst?.word == "um")
        #expect(evidence.fillerBurst?.count == 3)
        #expect(evidence.structuralRepetition?.frame == "i'm going to get")
        #expect(evidence.structuralRepetition?.count == 3)
        #expect(evidence.structuralRepetition?.start == 20)
    }

    @Test func structuralEvidenceQuotesTheTriad() {
        var cursor: TimeInterval = 0
        var spoken: [TranscriptionWord] = []
        func append(_ tokens: [String]) -> TimeInterval {
            let stamp = cursor
            for token in tokens {
                let start = cursor
                let end = start + 0.25
                spoken.append(TranscriptionWord(
                    word: token, start: start, end: end,
                    isFiller: false, isPrimarySpeaker: true
                ))
                cursor = end + 0.1
            }
            cursor += 0.5
            return stamp
        }
        let t0 = append(["I'm", "going", "to", "get", "socks,"])
        let t1 = append(["I'm", "going", "to", "get", "tomatoes,"])
        let t2 = append(["I'm", "going", "to", "get", "eggs."])

        let fillers = [
            FillerWord(
                word: "i'm going to get",
                count: 3,
                timestamps: [t0, t1, t2],
                kind: .structural
            )
        ]
        let evidence = CoachEvidenceService.evidence(
            for: analysis(fillerWords: fillers),
            words: spoken
        )
        #expect(evidence.structuralRepetition?.example.contains("socks") == true)
        #expect(evidence.structuralRepetition?.example.contains("/") == true)
        #expect(evidence.promptLines.contains { $0.contains("i'm going to get") })
    }

    @Test func ignoresPausesAfterFullStops() {
        // A pause after a sentence is craft; the same gap mid-clause is the
        // speaker searching for a word. Only the second is coachable.
        let words = [
            TranscriptionWord(word: "done.", start: 0, end: 1),
            TranscriptionWord(word: "next", start: 5, end: 5.5),
            TranscriptionWord(word: "and", start: 6, end: 6.4),
            TranscriptionWord(word: "then", start: 9, end: 9.5)
        ]
        let evidence = CoachEvidenceService.evidence(for: analysis(), words: words)
        #expect(evidence.longestHesitation?.at == 6.4)
    }

    @Test func quotesOnlyThePrimarySpeaker() {
        let words = [
            TranscriptionWord(word: "so", start: 0, end: 0.3, isFiller: true, isPrimarySpeaker: false),
            TranscriptionWord(word: "what", start: 0.4, end: 0.7, isPrimarySpeaker: false),
            TranscriptionWord(word: "the", start: 1, end: 1.2),
            TranscriptionWord(word: "answer", start: 1.3, end: 1.8),
            TranscriptionWord(word: "is", start: 1.9, end: 2.1),
            TranscriptionWord(word: "simple", start: 2.2, end: 2.8)
        ]
        let evidence = CoachEvidenceService.evidence(for: analysis(), words: words)
        #expect(evidence.opening?.hasPrefix("the answer") == true)
        #expect(evidence.openingIsHesitant == false)
    }

    @Test func stampsAreMinutesAndSeconds() {
        #expect(CoachEvidence.stamp(0) == "0:00")
        #expect(CoachEvidence.stamp(9) == "0:09")
        #expect(CoachEvidence.stamp(75) == "1:15")
    }

    @Test func promptLinesAreEmptyWhenThereIsNothingToQuote() {
        #expect(CoachEvidence().promptLines.isEmpty)
    }
}

// MARK: - Full-fidelity round trip

@MainActor
struct AnalysisMirrorTests {
    private func rich() -> SpeechAnalysis {
        var value = analysis()
        value.textQuality = TextQualityMetrics(hedgeWordCount: 5, powerWordCount: 2)
        value.sentenceAnalysis = SentenceAnalysis(totalSentences: 6, restartCount: 1, restartExamples: ["I was going to — actually"])
        value.promptRelevanceScore = 64
        return value
    }

    @Test func mirrorKeepsWhatSwiftDataDrops() {
        // The whole point: `analysis` comes back from the store without these,
        // which is most of what the coaching layer reasons about.
        guard let data = rich().encodedMirror(),
              let restored = SpeechAnalysis.decodedMirror(data) else {
            Issue.record("mirror did not round-trip")
            return
        }
        #expect(restored.textQuality?.hedgeWordCount == 5)
        #expect(restored.sentenceAnalysis?.restartExamples.first == "I was going to — actually")
        #expect(restored.promptRelevanceScore == 64)
    }

    @Test func plainDecodeStillDropsThem() {
        // The SwiftData path must keep skipping these — decoding them there
        // traps rather than throwing.
        guard let data = rich().encodedMirror(),
              let plain = try? JSONDecoder().decode(SpeechAnalysis.self, from: data) else {
            Issue.record("plain decode failed")
            return
        }
        #expect(plain.textQuality == nil)
        #expect(plain.speechScore.subscores.clarity == 70)
    }

    @Test func mirrorDropsTheRawSampleArrays() {
        // Per-frame series are consumed inside analyze() and never read back,
        // but they would dominate the blob.
        var value = analysis()
        value.pitchMetrics = PitchMetrics(f0Contour: Array(repeating: 120, count: 5000))
        guard let data = value.encodedMirror(),
              let restored = SpeechAnalysis.decodedMirror(data) else {
            Issue.record("mirror did not round-trip")
            return
        }
        #expect(restored.pitchMetrics?.f0Contour == nil)
    }
}

// MARK: - Next step

@MainActor
struct NextStepTests {
    @Test func followsThePlanRatherThanTodaysWeakest() {
        let subscores = SpeechSubscores(clarity: 40, pace: 80, fillerUsage: 20, pauseQuality: 80)
        let plan = CoachPlanService.plan(window: Array(repeating: analysis(clarity: 40), count: 5))
        let step = NextStep.from(subscores, plan: plan)
        #expect(step.areaSlug == plan?.focus.analyticsSlug)
    }

    @Test func fallsBackToWeakestWithoutAPlan() {
        let subscores = SpeechSubscores(clarity: 80, pace: 80, fillerUsage: 30, pauseQuality: 80)
        #expect(NextStep.from(subscores).areaSlug == "filler")
    }

    @Test func strongSessionOffersAnotherRep() {
        let subscores = SpeechSubscores(clarity: 88, pace: 84, fillerUsage: 91, pauseQuality: 79)
        #expect(NextStep.from(subscores).action == .practiceAgain)
    }
}

// MARK: - Coaching prompt v2

struct CoachingPromptTests {

    @Test func pinsFocusAndNamesCrutchHabits() {
        let context = CoachingContext(
            plan: CoachPlanService.plan(window: Array(repeating: analysis(filler: 40), count: 5)),
            crutchLines: ["\"like\" x7"]
        )

        let system = CoachingPrompt.system(context: context)
        let user = CoachingPrompt.user(
            analysis: analysis(),
            transcript: "A short transcript.",
            context: context,
            transcriptBudget: 600
        )

        #expect(system.contains("filler words. Tip one must be about that"))
        #expect(system.contains("\"like\" x7"))
        #expect(system.contains("Example of a good tip line"))
        #expect(user.contains("CRUTCH HABITS"))
        #expect(user.contains("- \"like\" x7"))
    }

    @Test func compactModeDropsExampleButKeepsRules() {
        let system = CoachingPrompt.system(context: CoachingContext(), compact: true)

        #expect(!system.contains("Example of a good tip line"))
        #expect(system.contains("Never do these"))
    }

    @Test func sessionKindSteersTheAngle() {
        #expect(
            CoachingPrompt.kindDirective("Interview Prep")?
                .contains("ownership verbs") == true
        )
        #expect(CoachingPrompt.kindDirective("Storytelling")?.contains("story") == true)
        #expect(CoachingPrompt.kindDirective("Something Obscure") == nil)
        #expect(CoachingPrompt.kindDirective(nil) == nil)
    }

    @Test func excerptKeepsHeadAndTail() {
        let opening = "The project started in chaos and nobody owned the roadmap at all."
        let fillerMiddle = String(repeating: "we kept iterating slowly ", count: 80)
        let close = "Final result, revenue grew forty percent that quarter."

        let transcript = opening + " " + fillerMiddle + " " + close
        let excerpt = CoachingPrompt.transcriptExcerpt(transcript, budget: 400)

        #expect(excerpt.count <= 420)
        #expect(excerpt.contains("[...]"))
        #expect(excerpt.contains(opening.prefix(30)))
        #expect(excerpt.contains(close.suffix(30)))
    }

    @Test func excerptShortCircuitsSmallTranscripts() {
        let text = "Short answer, already complete."
        #expect(CoachingPrompt.transcriptExcerpt(text, budget: 600) == text)
    }

    @Test func scoreRuleCarriesMetricNamesInBothModes() {
        // The bare-score ban has to survive compact mode — the E4B local
        // profile is exactly the backend most likely to drop the label.
        let full = CoachingPrompt.system(context: CoachingContext())
        let compact = CoachingPrompt.system(context: CoachingContext(), compact: true)

        // Compact only declines to append the benchmarks tail, so it is a
        // strict prefix of full. Asserting the shape means a reworded rule
        // can't fail this test while the rule is still there — the previous
        // version pinned a hand-copied sentence and broke on an edit that
        // changed nothing about the behaviour.
        #expect(full.hasPrefix(compact))

        // The ban itself, and the names that make it enforceable. Short
        // fragment on purpose: if "bare number" stops appearing, the rule
        // really has changed and this SHOULD fail.
        #expect(compact.contains("bare number"))
        #expect(compact.contains(CoachingPrompt.dimensionNameList))
        for title in CoachDimension.allCases.map(\.title) {
            #expect(compact.contains(title))
        }
    }
}

// MARK: - Insight sanitizer

struct CoachingInsightSanitizerTests {

    @Test func stripsBulletsDedupesAndCaps() {
        let raw = """
        Here are your tips:
        - You used 9 fillers in 120 words, swap "um" for a closed mouth.
        * You used 9 fillers in 120 words, swap "um" for a closed mouth!
        1. Pauses: only 2 were deliberate, land one after each claim.
        - Random trailing thought
        - Another trailing thought
        """

        let tips = CoachingInsightSanitizer.tips(from: raw)

        #expect(tips.count <= 3)
        #expect(tips.contains { $0.contains("9 fillers") })
    }

    @Test func rejectsFillerAsTechniqueButAcceptsTheSwap() {
        #expect(CoachingInsightSanitizer.containsDisallowedAdvice(
            "Add an um now and then to sound natural"
        ))
        #expect(!CoachingInsightSanitizer.containsDisallowedAdvice(
            "You said like 7 times, hold a pause instead of the word"
        ))
    }

    @Test func specificityAcceptsMetricsNumbersOrLateQuotes() {
        // Metric plus number: always accepted.
        #expect(CoachingInsightSanitizer.isSpecificEnough(
            ["Fillers hit 9 in 120 words"],
            transcript: "irrelevant"
        ))

        // A quote from deep in the answer must pass; the old check scanned
        // only the first 24 tokens and discarded exactly these.
        let lateQuote = String(repeating: "wandering setup material ", count: 40) + "revenue doubled"
        #expect(CoachingInsightSanitizer.isSpecificEnough(
            ["Your close said revenue doubled, lead with it next time"],
            transcript: lateQuote
        ))

        // Pure generic advice fails.
        #expect(!CoachingInsightSanitizer.isSpecificEnough(
            ["Be more confident and engaging overall"],
            transcript: "something something else entirely different here"
        ))
    }

    // MARK: Bare score naming

    /// Distinct subscores so each bare number maps to exactly one metric.
    private let namingSubscores = SpeechSubscores(
        clarity: 71,
        pace: 82,
        fillerUsage: 65,
        pauseQuality: 90,
        vocalVariety: 44
    )

    @Test func prefixesBareScoreWithMatchingMetric() {
        let tips = CoachingInsightSanitizer.namingBareScores(
            ["You landed 44/100 here, so vary your pitch more."],
            subscores: namingSubscores
        )
        #expect(tips[0] == "You landed Vocal variety 44/100 here, so vary your pitch more.")
    }

    @Test func normalizesTheSpelledOutForm() {
        let tips = CoachingInsightSanitizer.namingBareScores(
            ["You came in at 82 out of 100 on this take, quick again."],
            subscores: namingSubscores
        )
        #expect(tips[0] == "You came in at Pace 82/100 on this take, quick again.")
    }

    @Test func leavesAlreadyNamedScoresUntouched() {
        let original = "Clarity came in at 71/100, finish your consonants."
        #expect(
            CoachingInsightSanitizer.namingBareScores([original], subscores: namingSubscores) == [original]
        )
    }

    @Test func overallIsNeverRelabelledAsASubscore() {
        // clarity also scores 71 — the look-back must still protect a score
        // the model explicitly called the overall.
        let original = "Overall you scored 71/100."
        #expect(
            CoachingInsightSanitizer.namingBareScores([original], subscores: namingSubscores) == [original]
        )
    }

    @Test func unmatchedNumbersStayAsWritten() {
        // Nothing in this session scored 58; inventing a label would be worse
        // than the bare number.
        let original = "You scored 58/100 on this take."
        #expect(
            CoachingInsightSanitizer.namingBareScores([original], subscores: namingSubscores) == [original]
        )
    }

    @Test func rewritesEveryBareScoreInOneLine() {
        let tips = CoachingInsightSanitizer.namingBareScores(
            ["You opened at 65/100 and closed at 44/100, tighten both."],
            subscores: namingSubscores
        )
        #expect(
            tips[0] == "You opened at Filler words 65/100 and closed at Vocal variety 44/100, tighten both."
        )
    }

    @Test func hintInsideLookBackProtectsTheLaterScore() {
        // Both scores sit close enough to a named metric that relabelling
        // could only guess wrong; the safety net leaves them alone.
        let original = "Clarity came in at 71/100 while vocal variety sat 44/100 low."
        #expect(
            CoachingInsightSanitizer.namingBareScores([original], subscores: namingSubscores) == [original]
        )
    }
}

// MARK: - Framework hints

struct SpeechFrameworkHintTests {
    @Test func parsesCurriculumHints() {
        #expect(SpeechFramework.fromCurriculumHint("PREP") == .prep)
        #expect(SpeechFramework.fromCurriculumHint("star") == .star)
        #expect(SpeechFramework.fromCurriculumHint("Problem-Solution") == .problemSolution)
        #expect(SpeechFramework.fromCurriculumHint(nil) == nil)
        #expect(SpeechFramework.fromCurriculumHint("  ") == nil)
        #expect(SpeechFramework.fromCurriculumHint("AREA") == nil)
    }
}
