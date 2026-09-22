import Testing
import Foundation
@testable import SpeakUp

// MARK: - Order

struct PracticeRoutineOrderTests {
    @Test func emptyStorageIsTheFactoryChain() {
        #expect(PracticeRoutine.resolve([]) == RoutineStep.defaultSteps)
    }

    @Test func unknownAndDuplicateRawValuesAreDropped() {
        let resolved = PracticeRoutine.resolve(["warmUp", "warmUp", "nonsense", "session"])
        #expect(resolved == [.warmUp, .session])
    }

    /// The scored take is the point of the routine. A payload that lost it - 
    /// a hand edit, an older build - gets it back rather than leaving the user
    /// with a chain of preparation for nothing.
    @Test func theTakeIsPutBackWhenAPayloadDroppedIt() {
        #expect(PracticeRoutine.resolve(["warmUp", "review"]) == [.warmUp, .session, .review])
    }

    @Test func theTakeCannotBeRemoved() {
        let steps = RoutineStep.defaultSteps
        #expect(PracticeRoutine.removing(.session, from: steps) == steps)
        #expect(PracticeRoutine.removing(.warmUp, from: steps) == [.session, .review])
    }

    /// Adding lands in canonical order - prep before the take, review after - 
    /// so a new link never appends itself behind the review.
    @Test func addedStepsLandInCanonicalOrder() {
        let withCalm = PracticeRoutine.adding(.calm, to: RoutineStep.defaultSteps)
        #expect(withCalm == [.calm, .warmUp, .session, .review])

        let withDrill = PracticeRoutine.adding(.drill, to: withCalm)
        #expect(withDrill == [.calm, .warmUp, .drill, .session, .review])
    }

    @Test func addingAStepAlreadyInTheChainChangesNothing() {
        let steps = RoutineStep.defaultSteps
        #expect(PracticeRoutine.adding(.session, to: steps) == steps)
    }

    @Test func movingSwapsNeighboursAndStopsAtTheEnds() {
        let steps = RoutineStep.defaultSteps  // warmUp, session, review
        #expect(PracticeRoutine.moving(.session, by: -1, in: steps) == [.session, .warmUp, .review])
        #expect(PracticeRoutine.moving(.warmUp, by: -1, in: steps) == steps)
        #expect(PracticeRoutine.moving(.review, by: 1, in: steps) == steps)
    }

    /// The card's time line: the take counts at the user's chosen length plus
    /// its countdown and scoring, rounded up, so "about 5 min" is a promise
    /// the chain keeps.
    @Test func estimatesCountTheTakeAtItsChosenLength() {
        let minutes = { (seconds: Int) in
            RoutineStep.defaultSteps.reduce(0) { $0 + $1.estimatedMinutes(takeSeconds: seconds) }
        }
        #expect(minutes(30) == 5)
        #expect(minutes(60) == 5)
        #expect(minutes(90) == 6)
        #expect(minutes(300) == 9)
        #expect(RoutineStep.session.estimatedMinutes(takeSeconds: 0) == 1)
    }

    @Test func encodeRoundTrips() {
        let steps: [RoutineStep] = [.calm, .warmUp, .session, .review]
        #expect(PracticeRoutine.resolve(PracticeRoutine.encode(steps)) == steps)
    }
}

// MARK: - Progress

struct RoutineProgressTests {
    private let steps = RoutineStep.defaultSteps  // warmUp, session, review
    private let now = Date()

    private var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    }

    @Test func nothingDoneMeansTheFirstLinkIsNext() {
        #expect(RoutineProgress.empty.next(in: steps, now: now) == .warmUp)
    }

    @Test func nextSkipsWhatIsAlreadyDone() {
        let progress = RoutineProgress.empty.marking(.warmUp, now: now)
        #expect(progress.next(in: steps, now: now) == .session)
    }

    @Test func aFinishedChainHasNoNextStep() {
        var progress = RoutineProgress.empty
        for step in steps { progress = progress.marking(step, now: now) }
        #expect(progress.next(in: steps, now: now) == nil)
        #expect(progress.isDone(in: steps, now: now))
    }

    /// The app is not running at midnight, so the rollover has to be derived on
    /// read. Yesterday's ticks must not make today look half done.
    @Test func yesterdaysProgressClearsOnRead() {
        let stale = RoutineProgress(completed: [.warmUp, .session], day: yesterday)
        #expect(stale.rolling(now: now) == .empty)
        #expect(stale.next(in: steps, now: now) == .warmUp)
    }

    /// Marking after a rollover starts a fresh day rather than adding to a
    /// stale set - otherwise the first tick of a new day would resurrect all of
    /// yesterday's.
    @Test func markingAfterARolloverStartsFresh() {
        let stale = RoutineProgress(completed: [.warmUp, .session], day: yesterday)
        let marked = stale.marking(.review, now: now)
        #expect(marked.completed == [.review])
        #expect(marked.day == now.startOfDay)
    }

    @Test func storageRoundTrips() {
        let progress = RoutineProgress.empty.marking(.warmUp, now: now).marking(.review, now: now)
        let restored = RoutineProgress(raw: progress.encoded, day: progress.day)
        #expect(restored.rolling(now: now).completed == [.warmUp, .review])
    }

    /// The handoff looks forward, not at whatever is outstanding: finishing the
    /// take when the warm-up was skipped points at the review, not back at a
    /// warm-up the take has already made pointless.
    @Test func theHandoffLooksForwardFromTheFinishedStep() {
        let progress = RoutineProgress.empty.marking(.session, now: now)
        #expect(progress.nextAfter(.session, in: steps, now: now) == .review)
        // `next` still counts the skipped link as outstanding.
        #expect(progress.next(in: steps, now: now) == .warmUp)
    }

    /// The Today card deals one step at a time and never deals backwards:
    /// after the take, the review is on top, not the skipped warm-up, and
    /// once the review is done the routine is done.
    @Test func theCardDealsForwardPastASkippedLink() {
        #expect(RoutineProgress.upNext(in: steps, completed: []) == .warmUp)
        #expect(RoutineProgress.upNext(in: steps, completed: [.warmUp]) == .session)
        #expect(RoutineProgress.upNext(in: steps, completed: [.session]) == .review)
        #expect(RoutineProgress.upNext(in: steps, completed: [.session, .review]) == nil)
    }

    /// Opening an old breakdown ticks the review without a take today. The
    /// take is what the routine is for, so it is never passed.
    @Test func theCardNeverPassesTheTake() {
        #expect(RoutineProgress.upNext(in: steps, completed: [.warmUp, .review]) == .session)
        let long: [RoutineStep] = [.calm, .warmUp, .drill, .session, .review]
        #expect(RoutineProgress.upNext(in: long, completed: [.drill]) == .session)
    }

    @Test func theLastLinkHandsOffToNothing() {
        var progress = RoutineProgress.empty
        for step in steps { progress = progress.marking(step, now: now) }
        #expect(progress.nextAfter(.review, in: steps, now: now) == nil)
    }

    /// A step the user's chain does not contain has no position in it, so it
    /// cannot hand off to anything.
    @Test func aStepOutsideTheChainHandsOffToNothing() {
        #expect(RoutineProgress.empty.nextAfter(.drill, in: steps, now: now) == nil)
    }

    /// Steps outside the user's chain never block it. Someone whose routine is
    /// warm-up → take → review should not be held up by a drill they took on a
    /// whim, and should not have it counted either.
    @Test func stepsOutsideTheChainDoNotAffectIt() {
        let progress = RoutineProgress.empty.marking(.drill, now: now)
        #expect(progress.next(in: steps, now: now) == .warmUp)
        #expect(!progress.isDone(in: steps, now: now))
    }
}
