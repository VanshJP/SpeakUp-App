import Testing
import Foundation
@testable import SpeakUp

// The coordinator's allowance decisions run minutes apart from its IO, so the
// rules get pinned here as pure values: nothing fetches, saves, or clocks.
// These are the monetization invariants, not implementation details.

private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

@MainActor
struct ProcessingReservationTests {
    private func reservation(
        _ decision: AllowanceDecision,
        reservedAnalyses: Int = 0
    ) -> ProcessingPolicy.Reservation {
        ProcessingPolicy.reservation(for: decision, reservedAnalyses: reservedAnalyses)
    }

    /// A free user past the trial with analyses left analyzes now and holds a
    /// reservation while doing it — the charge lands later, on success only.
    @Test func aCountableFreeAnalysisReservesBeforeProcessing() {
        let decision = AllowanceDecision.cycle(remaining: 3, resetsOn: t0)
        let result = reservation(decision)

        #expect(!result.shouldDefer)
        #expect(result.holdsReservation)
    }

    /// Two recordings started back-to-back both read the persisted counters
    /// before either is charged — nothing serialises the reads, so each can
    /// see the same `remaining` and one slot gets spent twice. One analysis
    /// left with one already in flight is exactly that race: the second
    /// recording must park.
    @Test func aRecordingBeyondTheReservedSlotsDefers() {
        let decision = AllowanceDecision.cycle(remaining: 1, resetsOn: t0)

        #expect(!reservation(decision, reservedAnalyses: 0).shouldDefer)
        #expect(reservation(decision, reservedAnalyses: 1).shouldDefer)
    }

    @Test func anExhaustedAllowanceDefers() {
        let result = reservation(.exhausted(resetsOn: t0))

        #expect(result.shouldDefer)
        // A parked recording holds no slot — remaining == 0 is non-nil, so
        // reserving off it would leak capacity to future callers' budgets.
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

// The charge is the reservation released through `PracticeAllowance.consume`
// after the analysis persisted. These walk that path with pure state only.

@MainActor
struct ProcessingChargePathTests {
    private let policy = FreeTierPolicy.expired

    /// Success charges exactly once and frees the slot: a second recording
    /// queued behind a spent allowance defers instead of sneaking through.
    @Test func successChargesOnceAndTheNextRecordingDefers() {
        // One analysis left in the cycle.
        var state = AllowanceState(cycleStart: t0, cycleUsed: policy.monthlyAnalyses - 1)
        var reserved = 0

        let first = ProcessingPolicy.reservation(
            for: PracticeAllowance.decision(state: state, isEntitled: false, trial: .expired, policy: policy, now: t0),
            reservedAnalyses: reserved
        )
        #expect(first.holdsReservation)
        reserved += 1

        // A concurrent recording during the ~90s transcription window sees
        // every countable slot taken and parks instead of double-spending.
        let second = ProcessingPolicy.reservation(
            for: PracticeAllowance.decision(state: state, isEntitled: false, trial: .expired, policy: policy, now: t0),
            reservedAnalyses: reserved
        )
        #expect(second.shouldDefer)

        // The success path: consume persists the charge, processing returns,
        // and the reservation releases with the cycle now exhausted.
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

        // Failure path releases without calling consume: the same decision,
        // replayed with nothing reserved, analyzes again at the same counter.
        let released = ProcessingPolicy.reservation(for: decision, reservedAnalyses: 0)
        #expect(!released.shouldDefer)
    }
}

// One resume pass: oldest first, bounded, stopped by a recording that is still
// deferred after its turn but not by one the user deleted meanwhile.

@MainActor
struct ResumePassTests {
    private let ids = (0..<25).map { _ in UUID() }

    @Test func thePassIsCappedAtTwenty() {
        #expect(ProcessingPolicy.deferredResumeLimit == 20)
    }

    @Test func picksFirstNonActiveCandidate() {
        // Linear scan over the caller-supplied window — oldest-first ordering
        // lives in the fetch sort, not here.
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
        // Full truth table: only a recording that still exists AND is still
        // flagged stops the pass. Deleted-but-still-flagged cannot happen,
        // and if it ever did, the pass must keep clearing the backlog.
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
