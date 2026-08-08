import Testing
import Foundation
@testable import SpeakUp

// The free/paid boundary decides whether someone can practise, so its
// arithmetic gets tests rather than a manual pass through the paywall.
// Everything here is pure: no StoreKit, no SwiftData, injected clock.

private let day: TimeInterval = 24 * 60 * 60
private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

@MainActor
struct FreeTierPolicyTests {
    /// The whole offer during the 14 days: see everything, then decide. iCloud
    /// sync is the one exception, so it is the one thing pinned as gated.
    @Test func theTrialGatesOnlyICloudSync() {
        #expect(FreeTierPolicy.trial.gatedFeatures == [.iCloudSync])
        #expect(!FreeTierPolicy.trial.gates(.unlimitedAnalyses))
        #expect(!FreeTierPolicy.trial.gates(.fullCurriculum))
        #expect(!FreeTierPolicy.trial.gates(.journalExport))
    }

    @Test func expiredPolicyMatchesTheShippedOffer() {
        #expect(FreeTierPolicy.expired.monthlyAnalyses == 3)
        #expect(FreeTierPolicy.expired.gates(.unlimitedAnalyses))
        #expect(FreeTierPolicy.expired.gates(.journalExport))
        #expect(FreeTierPolicy.expired.gates(.fullCurriculum))
        #expect(FreeTierPolicy.expired.gates(.iCloudSync))
    }

    /// The share loop is the plan's primary distribution channel. Gating it
    /// behind the purchase would mean only buyers can recruit users.
    @Test func progressCardsStayFree() {
        #expect(!FreeTierPolicy.expired.gates(.progressCards))
        #expect(!FreeTierPolicy.trial.gates(.progressCards))
    }

    @Test func unrestrictedPolicyGatesNothing() {
        #expect(FreeTierPolicy.unrestricted.gatedFeatures.isEmpty)
        for feature in PaidFeature.allCases {
            #expect(!FreeTierPolicy.unrestricted.gates(feature))
        }
    }
}

// The clock the whole offer hangs on. It starts at the first score, so an
// unstarted trial is a full trial, and it must end at exactly 14 days.
@MainActor
struct PracticeTrialTests {
    @Test func anUnstartedClockIsNotRunning() {
        #expect(PracticeTrial.state(startedAt: nil, now: t0) == .notStarted)
    }

    @Test func theTrialEndsExactlyFourteenDaysAfterItStarts() {
        let endsOn = t0.addingTimeInterval(14 * day)

        #expect(PracticeTrial.state(startedAt: t0, now: t0) == .active(endsOn: endsOn))
        #expect(PracticeTrial.state(startedAt: t0, now: endsOn.addingTimeInterval(-60))
                == .active(endsOn: endsOn))
        #expect(PracticeTrial.state(startedAt: t0, now: endsOn) == .expired)
        #expect(PracticeTrial.state(startedAt: t0, now: t0.addingTimeInterval(365 * day)) == .expired)
    }

    /// Any time left has to read as at least one day — a countdown showing zero
    /// while the trial still works is a bug report.
    @Test func daysRemainingRoundsUp() {
        let endsOn = t0.addingTimeInterval(14 * day)
        #expect(PracticeTrial.daysRemaining(until: endsOn, now: t0) == 14)
        #expect(PracticeTrial.daysRemaining(until: endsOn, now: t0.addingTimeInterval(13 * day)) == 1)
        #expect(PracticeTrial.daysRemaining(until: endsOn, now: endsOn.addingTimeInterval(-60)) == 1)
        #expect(PracticeTrial.daysRemaining(until: endsOn, now: endsOn) == 0)
    }
}

// A comparison price is a claim about money, and the only one in the app that
// StoreKit cannot supply. These pin the conditions under which it may be shown.
@MainActor
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
@MainActor
struct AllowanceDisclosureTests {
    @Test func anEntitledUserIsToldNothing() {
        #expect(AllowanceDecision.unlimited.shortSummary == nil)
    }

    @Test func remainingAnalysesAreCounted() {
        #expect(AllowanceDecision.cycle(remaining: 3, resetsOn: t0).summary(now: t0)?
            .hasPrefix("3 free analyses left") == true)
    }

    @Test func oneRemainingIsSingular() {
        #expect(AllowanceDecision.cycle(remaining: 1, resetsOn: t0).summary(now: t0)?
            .hasPrefix("1 free analysis left") == true)
    }

    @Test func theTrialCountsDaysRatherThanAnalyses() {
        let decision = AllowanceDecision.trial(endsOn: t0.addingTimeInterval(14 * day))
        #expect(decision.summary(now: t0) == "Free trial · 14 days left")
        #expect(decision.summary(now: t0.addingTimeInterval(11 * day)) == "Free trial · 3 days left")
        // Nothing is being counted down during the trial.
        #expect(decision.remaining == nil)
    }

    /// The last day says so rather than reading "1 days left", and it is the one
    /// day the line has a job to do.
    @Test func theLastTrialDayIsNamed() {
        let decision = AllowanceDecision.trial(endsOn: t0.addingTimeInterval(14 * day))
        #expect(decision.summary(now: t0.addingTimeInterval(13 * day)) == "Free trial · last day")
        #expect(decision.summary(now: t0.addingTimeInterval(14 * day - 60)) == "Free trial · last day")
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

@MainActor
struct PracticeAllowanceTests {
    // Every free user in these tests is past the 14 days unless the test is
    // about the trial itself; that is where the counting starts.
    private func decide(
        _ state: AllowanceState,
        trial: TrialState = .expired,
        isEntitled: Bool = false,
        at now: Date
    ) -> AllowanceDecision {
        PracticeAllowance.decision(
            state: state,
            isEntitled: isEntitled,
            trial: trial,
            policy: isEntitled ? .unrestricted : (trial.isExpired ? .expired : .trial),
            now: now
        )
    }

    private func spend(
        _ state: AllowanceState,
        trial: TrialState = .expired,
        isEntitled: Bool = false,
        at now: Date
    ) -> AllowanceState {
        PracticeAllowance.consume(
            state: state,
            isEntitled: isEntitled,
            trial: trial,
            policy: isEntitled ? .unrestricted : (trial.isExpired ? .expired : .trial),
            now: now
        )
    }

    @Test func entitledUsersAreNeverCounted() {
        #expect(decide(AllowanceState(), isEntitled: true, at: t0) == .unlimited)

        let after = spend(AllowanceState(cycleStart: t0, cycleUsed: 2), isEntitled: true, at: t0)
        #expect(after.cycleUsed == 2)
    }

    // MARK: - Trial

    /// The clock has not started, so nothing has been spent and the line reports
    /// the full fourteen.
    @Test func anUnstartedTrialReportsItsFullLength() {
        #expect(decide(AllowanceState(), trial: .notStarted, at: t0)
                == .trial(endsOn: t0.addingTimeInterval(14 * day)))
    }

    @Test func theTrialIsUnlimitedAndUncounted() {
        let endsOn = t0.addingTimeInterval(14 * day)
        var state = AllowanceState()

        for offset in 0..<20 {
            let now = t0.addingTimeInterval(Double(offset) * 0.5 * day)
            let decision = decide(state, trial: .active(endsOn: endsOn), at: now)
            #expect(decision == .trial(endsOn: endsOn))
            #expect(decision.isAllowed)
            state = spend(state, trial: .active(endsOn: endsOn), at: now)
        }

        // Twenty scored analyses inside the trial leave the cycle untouched, so
        // the month after expiry still opens at three.
        #expect(state == AllowanceState())
    }

    @Test func theCycleOpensAtThreeWhenTheTrialExpires() {
        let expiry = t0.addingTimeInterval(14 * day)
        #expect(decide(AllowanceState(), trial: .expired, at: expiry)
                == .cycle(remaining: 3, resetsOn: expiry.addingTimeInterval(30 * day)))
    }

    // MARK: - Post-trial cycle

    @Test func cycleStartDoesNotDriftAsAnalysesAreUsed() {
        var state = spend(AllowanceState(), at: t0)
        state = spend(state, at: t0.addingTimeInterval(5 * day))
        #expect(state.cycleStart == t0)
        #expect(state.cycleUsed == 2)
    }

    @Test func fourthAnalysisInTheWindowIsBlocked() {
        var state = AllowanceState()
        for offset in [0.0, 2.0, 5.0] {
            state = spend(state, at: t0.addingTimeInterval(offset * day))
        }
        let decision = decide(state, at: t0.addingTimeInterval(6 * day))
        #expect(decision == .exhausted(resetsOn: t0.addingTimeInterval(30 * day)))
        #expect(!decision.isAllowed)
        #expect(decision.remaining == 0)
    }

    @Test func allowanceReturnsExactlyAtTheResetBoundary() {
        var state = AllowanceState()
        for _ in 0..<3 { state = spend(state, at: t0) }

        let justBefore = t0.addingTimeInterval(30 * day - 60)
        #expect(decide(state, at: justBefore) == .exhausted(resetsOn: t0.addingTimeInterval(30 * day)))

        let justAfter = t0.addingTimeInterval(30 * day + 60)
        #expect(decide(state, at: justAfter)
                == .cycle(remaining: 3, resetsOn: t0.addingTimeInterval(60 * day)))
    }

    /// Someone who comes back after a year gets one allowance, not one for
    /// every month they were away.
    @Test func longAbsenceGrantsOneAllowance() {
        var state = AllowanceState()
        for _ in 0..<3 { state = spend(state, at: t0) }

        let muchLater = t0.addingTimeInterval(365 * day)
        let decision = decide(state, at: muchLater)
        #expect(decision.remaining == 3)

        guard case .cycle(_, let resetsOn) = decision else {
            Issue.record("expected a cycle decision after a long absence")
            return
        }
        #expect(resetsOn > muchLater)
        #expect(resetsOn.timeIntervalSince(muchLater) <= 30 * day)

        #expect(spend(state, at: muchLater).cycleUsed == 1)
    }

    @Test func purchasingWhileExhaustedUnblocksImmediately() {
        var state = AllowanceState()
        for _ in 0..<3 { state = spend(state, at: t0) }
        #expect(decide(state, isEntitled: true, at: t0) == .unlimited)
    }
}

@MainActor
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

@MainActor
struct FoundingOfferTests {
    /// Shipping urgency the developer never configured would be a false claim.
    @Test func urgencyIsOffUntilADeadlineIsSet() {
        #expect(!FoundingOffer.isActive(now: t0))
    }
}
