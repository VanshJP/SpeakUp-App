import Testing
import Foundation
@testable import SpeakUp


private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

@MainActor
struct ProcessingReservationTests {
    private func reservation(
        _ decision: AllowanceDecision,
        reservedAnalyses: Int = 0
    ) -> ProcessingPolicy.Reservation {
        ProcessingPolicy.reservation(for: decision, reservedAnalyses: reservedAnalyses)
    }

    @Test func aCountableFreeAnalysisReservesBeforeProcessing() {
        let decision = AllowanceDecision.cycle(remaining: 3, resetsOn: t0)
        let result = reservation(decision)

        #expect(!result.shouldDefer)
        #expect(result.holdsReservation)
    }

    @Test func aRecordingBeyondTheReservedSlotsDefers() {
        let decision = AllowanceDecision.cycle(remaining: 1, resetsOn: t0)

        #expect(!reservation(decision, reservedAnalyses: 0).shouldDefer)
        #expect(reservation(decision, reservedAnalyses: 1).shouldDefer)
    }

    @Test func anExhaustedAllowanceDefers() {
        let result = reservation(.exhausted(resetsOn: t0))

        #expect(result.shouldDefer)
        #expect(!result.holdsReservation)
    }

    // MARK: - Not counted

    @Test func anEntitledUserNeitherDefersNorReserves() {
        let result = reservation(.unlimited, reservedAnalyses: 5)

        #expect(!result.shouldDefer)
        #expect(!result.holdsReservation)
    }

    @Test func theTrialNeitherDefersNorReserves() {
        let result = reservation(.trial(endsOn: t0))

        #expect(!result.shouldDefer)
        #expect(!result.holdsReservation)
    }
}


@MainActor
struct ProcessingChargePathTests {
    private let policy = FreeTierPolicy.expired

    @Test func successChargesOnceAndTheNextRecordingDefers() {
        var state = AllowanceState(cycleStart: t0, cycleUsed: policy.monthlyAnalyses - 1)
        var reserved = 0

        let first = ProcessingPolicy.reservation(
            for: PracticeAllowance.decision(state: state, isEntitled: false, trial: .expired, policy: policy, now: t0),
            reservedAnalyses: reserved
        )
        #expect(first.holdsReservation)
        reserved += 1

        let second = ProcessingPolicy.reservation(
            for: PracticeAllowance.decision(state: state, isEntitled: false, trial: .expired, policy: policy, now: t0),
            reservedAnalyses: reserved
        )
        #expect(second.shouldDefer)

        state = PracticeAllowance.consume(state: state, isEntitled: false, trial: .expired, policy: policy, now: t0)
        reserved -= 1
        #expect(reserved == 0)

        let after = ProcessingPolicy.reservation(
            for: PracticeAllowance.decision(state: state, isEntitled: false, trial: .expired, policy: policy, now: t0),
            reservedAnalyses: reserved
        )
        #expect(after.shouldDefer)
    }

    /// A failed transcription releases the slot uncharged — the counters never
    /// moved, so the retry sees the same allowance as the first attempt.
    @Test func failureReleasesUncharged() {
        let state = AllowanceState(cycleStart: t0, cycleUsed: 2)

        let decision = PracticeAllowance.decision(state: state, isEntitled: false, trial: .expired, policy: policy, now: t0)
        let result = ProcessingPolicy.reservation(for: decision, reservedAnalyses: 1)
        #expect(result.holdsReservation)

        let released = ProcessingPolicy.reservation(for: decision, reservedAnalyses: 0)
        #expect(!released.shouldDefer)
    }
}


@MainActor
struct ResumePassTests {
    private let ids = (0..<25).map { _ in UUID() }

    @Test func thePassIsCappedAtTwenty() {
        #expect(ProcessingPolicy.deferredResumeLimit == 20)
    }

    @Test func picksFirstNonActiveCandidate() {
        #expect(ProcessingPolicy.nextResumeIndex(in: Array(ids.prefix(3)), skippingActive: []) == 0)
        #expect(ProcessingPolicy.nextResumeIndex(in: Array(ids.prefix(3)), skippingActive: [ids[0]]) == 1)
        #expect(ProcessingPolicy.nextResumeIndex(in: Array(ids.prefix(3)), skippingActive: [ids[0], ids[1]]) == 2)
    }

    @Test func aHandRetryIsSteppedOverNotBlockingTheBacklog() {
        let window = Array(ids.prefix(3))
        #expect(ProcessingPolicy.nextResumeIndex(in: window, skippingActive: Set(window)) == nil)
    }

    @Test func anEmptyWindowEndsThePass() {
        #expect(ProcessingPolicy.nextResumeIndex(in: [], skippingActive: []) == nil)
    }

    @Test func stillDeferredStopsButDeletedMovesOn() {
        #expect(ProcessingPolicy.stopsResumePass(doesRecordingExist: true, stillBlockedByAllowance: true))
        #expect(!ProcessingPolicy.stopsResumePass(doesRecordingExist: false, stillBlockedByAllowance: false))
        #expect(!ProcessingPolicy.stopsResumePass(doesRecordingExist: false, stillBlockedByAllowance: true))
        #expect(!ProcessingPolicy.stopsResumePass(doesRecordingExist: true, stillBlockedByAllowance: false))
    }
}

/// A deferred user who buys Lifetime mid-queue: every gate reads `.unlimited`,
/// so nothing defers, nothing reserves, and a cleared recording lets the pass
/// continue rather than stopping on a stale flag.
@MainActor
struct MidQueuePurchaseTests {
    @Test func entitlementOpensEveryGateWithoutAccounting() {
        let result = ProcessingPolicy.reservation(for: .unlimited, reservedAnalyses: 3)

        #expect(!result.shouldDefer)
        #expect(!result.holdsReservation)

        // The half the gate read cannot show: consuming while entitled is a
        // no-op on persisted counters — the purchase must not burn the very
        // allowance it replaced.
        let state = AllowanceState(cycleStart: t0, cycleUsed: 2)
        let charged = PracticeAllowance.consume(state: state, isEntitled: true, trial: .expired, policy: .expired, now: t0)
        #expect(charged == state)
    }

    @Test func aClearedRecordingKeepsThePassRunning() {
        #expect(!ProcessingPolicy.stopsResumePass(doesRecordingExist: true, stillBlockedByAllowance: false))
    }
}
