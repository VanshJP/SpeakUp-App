import Testing
import Foundation
@testable import SpeakUp

// The free/paid boundary decides whether someone can practise, so its
// arithmetic gets tests rather than a manual pass through the paywall.
// Everything here is pure: no StoreKit, no SwiftData, injected clock.

private let day: TimeInterval = 24 * 60 * 60
private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

struct FreeTierPolicyTests {
    @Test func defaultPolicyMatchesTheShippedOffer() {
        #expect(FreeTierPolicy.default.introAnalyses == 3)
        #expect(FreeTierPolicy.default.monthlyAnalyses == 3)
        #expect(FreeTierPolicy.default.gates(.unlimitedAnalyses))
        #expect(FreeTierPolicy.default.gates(.journalExport))
        #expect(FreeTierPolicy.default.gates(.fullCurriculum))
        #expect(FreeTierPolicy.default.gates(.iCloudSync))
    }

    /// The share loop is the plan's primary distribution channel. Gating it
    /// behind the purchase would mean only buyers can recruit users.
    @Test func progressCardsStayFree() {
        #expect(!FreeTierPolicy.default.gates(.progressCards))
    }

    @Test func unrestrictedPolicyGatesNothing() {
        #expect(FreeTierPolicy.unrestricted.gatedFeatures.isEmpty)
        for feature in PaidFeature.allCases {
            #expect(!FreeTierPolicy.unrestricted.gates(feature))
        }
    }
}

// A comparison price is a claim about money, and the only one in the app that
// StoreKit cannot supply. These pin the conditions under which it may be shown.
struct FoundingComparisonPriceTests {
    private let future = t0.addingTimeInterval(30 * day)

    @Test func noComparisonWhileTheOfferIsOff() {
        // Ships with deadline nil, so this is the shipped state.
        #expect(FoundingOffer.comparisonPrice(currencyCode: "USD", now: t0) == nil)
    }

    @Test func noComparisonBeforeStoreKitNamesACurrency() {
        #expect(FoundingOffer.comparisonPrice(currencyCode: nil, now: t0) == nil)
    }

    /// The whole point: a dollar figure must never appear beside a price in
    /// another currency.
    @Test func noComparisonOnAForeignStorefront() {
        for code in ["GBP", "EUR", "JPY", "AUD", "CAD"] {
            #expect(FoundingOffer.comparisonPrice(currencyCode: code, now: future) == nil)
        }
    }

    @Test func theLiteralIsWrittenInTheCurrencyItClaims() {
        #expect(FoundingOffer.standardPriceCurrencyCode == "USD")
        #expect(FoundingOffer.standardDisplayPrice.hasPrefix("$"))
    }
}

// The limit has to be legible before it is spent, not only after. These pin the
// copy that says so, including the plural that reads wrong exactly once — at
// one remaining, which is the moment it matters most.
struct AllowanceDisclosureTests {
    @Test func anEntitledUserIsToldNothing() {
        #expect(AllowanceDecision.unlimited.shortSummary == nil)
    }

    @Test func remainingAnalysesAreCounted() {
        #expect(AllowanceDecision.intro(remaining: 3).shortSummary == "3 free analyses left")
    }

    @Test func oneRemainingIsSingular() {
        #expect(AllowanceDecision.intro(remaining: 1).shortSummary == "1 free analysis left")
    }

    @Test func aCycleNamesItsResetDay() {
        let summary = AllowanceDecision.cycle(remaining: 2, resetsOn: t0).shortSummary
        #expect(summary?.hasPrefix("2 free analyses left · resets ") == true)
    }

    @Test func exhaustedSaysSoRatherThanShowingZero() {
        let summary = AllowanceDecision.exhausted(resetsOn: t0).shortSummary
        #expect(summary?.hasPrefix("No free analyses left · resets ") == true)
        #expect(summary?.contains("0 free") == false)
    }
}

struct PracticeAllowanceTests {
    @Test func entitledUsersAreNeverCounted() {
        let decision = PracticeAllowance.decision(state: AllowanceState(), isEntitled: true, now: t0)
        #expect(decision == .unlimited)

        let after = PracticeAllowance.consume(
            state: AllowanceState(introUsed: 2), isEntitled: true, now: t0
        )
        #expect(after.introUsed == 2)
    }

    @Test func introAllowanceCountsDownFromThree() {
        var state = AllowanceState()
        for expected in [3, 2, 1] {
            #expect(PracticeAllowance.decision(state: state, isEntitled: false, now: t0)
                    == .intro(remaining: expected))
            state = PracticeAllowance.consume(state: state, isEntitled: false, now: t0)
        }
        #expect(state.introUsed == 3)
    }

    @Test func monthlyCycleOpensAfterTheIntroAllowance() {
        let state = AllowanceState(introUsed: 3)
        #expect(PracticeAllowance.decision(state: state, isEntitled: false, now: t0)
                == .cycle(remaining: 3, resetsOn: t0.addingTimeInterval(30 * day)))
    }

    @Test func cycleStartDoesNotDriftAsAnalysesAreUsed() {
        var state = AllowanceState(introUsed: 3)
        state = PracticeAllowance.consume(state: state, isEntitled: false, now: t0)
        state = PracticeAllowance.consume(state: state, isEntitled: false, now: t0.addingTimeInterval(5 * day))
        #expect(state.cycleStart == t0)
        #expect(state.cycleUsed == 2)
    }

    @Test func fourthAnalysisInTheWindowIsBlocked() {
        var state = AllowanceState(introUsed: 3)
        for offset in [0.0, 2.0, 5.0] {
            state = PracticeAllowance.consume(
                state: state, isEntitled: false, now: t0.addingTimeInterval(offset * day)
            )
        }
        let decision = PracticeAllowance.decision(
            state: state, isEntitled: false, now: t0.addingTimeInterval(6 * day)
        )
        #expect(decision == .exhausted(resetsOn: t0.addingTimeInterval(30 * day)))
        #expect(!decision.isAllowed)
        #expect(decision.remaining == 0)
    }

    @Test func allowanceReturnsExactlyAtTheResetBoundary() {
        var state = AllowanceState(introUsed: 3)
        for _ in 0..<3 {
            state = PracticeAllowance.consume(state: state, isEntitled: false, now: t0)
        }

        let justBefore = t0.addingTimeInterval(30 * day - 60)
        #expect(PracticeAllowance.decision(state: state, isEntitled: false, now: justBefore)
                == .exhausted(resetsOn: t0.addingTimeInterval(30 * day)))

        let justAfter = t0.addingTimeInterval(30 * day + 60)
        #expect(PracticeAllowance.decision(state: state, isEntitled: false, now: justAfter)
                == .cycle(remaining: 3, resetsOn: t0.addingTimeInterval(60 * day)))
    }

    /// Someone who comes back after a year gets one allowance, not one for
    /// every month they were away.
    @Test func longAbsenceGrantsOneAllowance() {
        var state = AllowanceState(introUsed: 3)
        for _ in 0..<3 {
            state = PracticeAllowance.consume(state: state, isEntitled: false, now: t0)
        }

        let muchLater = t0.addingTimeInterval(365 * day)
        let decision = PracticeAllowance.decision(state: state, isEntitled: false, now: muchLater)
        #expect(decision.remaining == 3)

        guard case .cycle(_, let resetsOn) = decision else {
            Issue.record("expected a cycle decision after a long absence")
            return
        }
        #expect(resetsOn > muchLater)
        #expect(resetsOn.timeIntervalSince(muchLater) <= 30 * day)

        let consumed = PracticeAllowance.consume(state: state, isEntitled: false, now: muchLater)
        #expect(consumed.cycleUsed == 1)
    }

    @Test func purchasingWhileExhaustedUnblocksImmediately() {
        var state = AllowanceState(introUsed: 3)
        for _ in 0..<3 {
            state = PracticeAllowance.consume(state: state, isEntitled: false, now: t0)
        }
        #expect(PracticeAllowance.decision(state: state, isEntitled: true, now: t0) == .unlimited)
    }
}

struct AnalyticsPrivacyTests {
    @Test func continuousValuesAreBucketed() {
        #expect(AnalyticsBucket.elapsed(5) == "0-10s")
        #expect(AnalyticsBucket.elapsed(45) == "30-60s")
        #expect(AnalyticsBucket.elapsed(600) == "5m+")
        #expect(AnalyticsBucket.minutes(3.5) == "2-4m")
        #expect(AnalyticsBucket.sessionNumber(1) == "1")
        #expect(AnalyticsBucket.sessionNumber(7) == "6-10")
        #expect(AnalyticsBucket.sessionNumber(99) == "11+")
        #expect(AnalyticsBucket.sentiment(scale: 1) == "negative")
        #expect(AnalyticsBucket.sentiment(scale: 3) == "mixed")
        #expect(AnalyticsBucket.sentiment(scale: 5) == "positive")
    }

    /// The schema is the privacy control. If a score or a recipient ever
    /// appears in a dimension, this is where it should be caught.
    @Test func eventsCarryNoIdentifyingDetail() {
        let analysis = AnalyticsEvent.analysisCompleted(
            sessionNumber: 4, processingPath: "whisper", elapsed: 42
        )
        #expect(analysis.dimensions["session_bucket"] == "3-5")
        #expect(analysis.dimensions["elapsed_bucket"] == "30-60s")
        #expect(analysis.dimensions["score"] == nil)

        let share = AnalyticsEvent.shareCompleted(cardType: "then_vs_now", trigger: "detail")
        #expect(share.dimensions["recipient"] == nil)
        #expect(share.dimensions["transcript"] == nil)

        // Feedback questions can be written by the user, so the event carries
        // the shape of the answer and nothing that was typed.
        let feedback = AnalyticsEvent.sessionFeedback(sentiment: "positive")
        #expect(feedback.dimensions == ["sentiment": "positive"])
    }

    /// The paywall shows no price until StoreKit returns one, so a purchase
    /// attempt can be logged before there is a price to log. That must read as
    /// its own outcome rather than dropping out of the dimension set.
    @Test func aPurchaseLoggedBeforeStoreKitAnsweredIsMarkedUnpriced() {
        let event = AnalyticsEvent.purchaseResult("failed", price: nil, source: nil)
        #expect(event.dimensions["price_tier"] == "unpriced")
        #expect(event.dimensions["source"] == "organic")
    }

    @Test func emptyDimensionsAreDropped() {
        let event = AnalyticsEvent("t", funnel: .quality, dimensions: ["a": "", "b": "x"])
        #expect(event.dimensions.count == 1)
        #expect(event.dimensions["b"] == "x")
    }

    @Test func missingAttributionReportsAsOrganic() {
        let event = AnalyticsEvent.firstOpen(source: nil, campaign: nil, page: nil)
        #expect(event.dimensions["source"] == "organic")
        #expect(event.dimensions["campaign"] == "none")
    }
}

struct FoundingOfferTests {
    /// Shipping urgency the developer never configured would be a false claim.
    @Test func urgencyIsOffUntilADeadlineIsSet() {
        #expect(!FoundingOffer.isActive(now: t0))
    }
}
