import Foundation
import Testing
@testable import SpeakUp

/// Pins the practice tools' memory and progression: drill records and the
/// Filler Elimination ladder, the milestones the result screen calls out,
/// Read Aloud's "drill what you missed" passage, and the catalog arithmetic
/// the runners rely on.
struct PracticeToolProgressTests {

    // MARK: - Drill records and ladder

    @Test func fillerEliminationClimbsOneCleanRoundAtATime() {
        let mode = DrillMode.fillerElimination
        #expect(mode.durationSeconds(atLevel: 0) == 15)

        var record = DrillRecord.folding(nil, score: 100, passed: true, rungs: mode.durationLadder.count)
        #expect(record.level == 1)
        #expect(mode.durationSeconds(atLevel: record.level) == 30)

        record = DrillRecord.folding(record, score: 50, passed: false, rungs: mode.durationLadder.count)
        #expect(record.level == 1)
        #expect(record.best == 100)
        #expect(record.last == 50)
        #expect(record.runs == 2)
    }

    @Test func theTopRungHolds() {
        let record = DrillRecord.folding(DrillRecord(level: 3), score: 100, passed: true, rungs: 4)
        #expect(record.level == 3)
        #expect(DrillMode.fillerElimination.durationSeconds(atLevel: 9) == 60)
    }

    @Test func singleRungDrillsNeverChangeLength() {
        let mode = DrillMode.paceControl
        let record = DrillRecord.folding(nil, score: 90, passed: true, rungs: mode.durationLadder.count)
        #expect(record.level == 0)
        #expect(mode.durationSeconds(atLevel: record.level) == mode.defaultDurationSeconds)
    }

    @Test func milestonesCallOutLevelUpsAndBestsButNotFirstRuns() {
        let first = DrillRecord.folding(nil, score: 80, passed: false, rungs: 1)
        #expect(DrillViewModel.milestone(for: .paceControl, score: 80, previous: nil, updated: first) == nil)

        let better = DrillRecord.folding(first, score: 90, passed: true, rungs: 1)
        #expect(
            DrillViewModel.milestone(for: .paceControl, score: 90, previous: first, updated: better)
                == "New personal best, up from 80."
        )

        let cleared = DrillRecord.folding(nil, score: 100, passed: true, rungs: 4)
        #expect(
            DrillViewModel.milestone(for: .fillerElimination, score: 100, previous: nil, updated: cleared)
                == "Round cleared. The next one runs 30 seconds."
        )
    }

    // MARK: - Read Aloud misses

    @Test func missedPhrasesKeepContextOnEitherSide() {
        let words = "one two three four five six seven eight nine ten eleven twelve"
            .components(separatedBy: " ")
        var states = Array(repeating: WordMatchState.matched, count: words.count)
        states[1] = .mismatched(spoken: "too")
        states[9] = .skipped

        #expect(
            ReadAloudResult.missedPhrases(in: words, states: states)
                == "one two three four. eight nine ten eleven twelve"
        )
    }

    @Test func nearbyMissesMergeIntoOneStretch() {
        let words = "The quick brown fox jumps over the lazy dog.".components(separatedBy: " ")
        var states = Array(repeating: WordMatchState.matched, count: words.count)
        states[2] = .skipped
        states[5] = .mismatched(spoken: "under")

        #expect(
            ReadAloudResult.missedPhrases(in: words, states: states)
                == "The quick brown fox jumps over the lazy"
        )
    }

    @Test func edgePunctuationIsDroppedFromAStretch() {
        let words = "The quick brown fox jumps over the lazy dog.".components(separatedBy: " ")
        var states = Array(repeating: WordMatchState.matched, count: words.count)
        states[8] = .mismatched(spoken: "log")

        #expect(ReadAloudResult.missedPhrases(in: words, states: states) == "the lazy dog")
    }

    @Test func aCleanReadHasNothingToDrill() {
        let words = ["Hello", "world"]
        #expect(ReadAloudResult.missedPhrases(in: words, states: [.matched, .matched]) == nil)
        // Words never reached are not misses.
        #expect(ReadAloudResult.missedPhrases(in: words, states: [.matched, .current]) == nil)
        #expect(ReadAloudResult.missedPhrases(in: words, states: []) == nil)
    }

    // MARK: - Catalog arithmetic

    /// The row dial and the runner both trust `durationSeconds`; a seed whose
    /// steps add up to something else would promise one length and run
    /// another.
    @Test func everyWarmUpRunsForTheLengthItAdvertises() {
        for exercise in DefaultWarmUps.all {
            let stepTotal = exercise.steps.reduce(0) { $0 + $1.durationSeconds }
            #expect(stepTotal == exercise.durationSeconds, "\(exercise.id) steps add to \(stepTotal)")
        }
    }

    /// The rounds picker rebuilds a breathing exercise from its first third,
    /// so every breathing seed has to encode exactly three rounds.
    @Test func everyBreathingWarmUpEncodesThreeRounds() {
        for exercise in DefaultWarmUps.all where exercise.category == .breathing {
            #expect(exercise.steps.count % 3 == 0, "\(exercise.id) has \(exercise.steps.count) steps")
        }
    }

    @Test func guidedCalmHoldsStayBetweenABreathAndHalfAMinute() {
        for exercise in DefaultConfidenceExercises.all {
            #expect((6...30).contains(exercise.guidedHoldSeconds), "\(exercise.id)")
        }
    }

    /// Lessons launch exercises by id, so a renamed or removed seed would turn
    /// a lesson activity into a dead end.
    @Test func everyLessonExerciseStillExists() {
        let known = Set(DefaultWarmUps.all.map(\.id) + DefaultConfidenceExercises.all.map(\.id))
        for phase in DefaultCurriculum.phases {
            for lesson in phase.lessons {
                for activity in lesson.activities {
                    guard let id = activity.exerciseId else { continue }
                    #expect(known.contains(id), "\(activity.id) points at missing exercise \(id)")
                }
            }
        }
    }
}
