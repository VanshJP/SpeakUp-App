import Testing
import Foundation
@testable import SpeakUp

/// `PracticeFocus` is the axis Warm-Ups, Drills, Read Aloud and Calm all group
/// by, and every listing that uses it is derived from the seed catalogs rather
/// than written down. These pin the derivation, because the failure mode is
/// quiet: a focus row that promises exercises, pushes a tool page, and lands on
/// an empty list.
@MainActor
struct PracticeFocusTests {

    @Test func everyFocusCarriesCopy() {
        for focus in PracticeFocus.allCases {
            #expect(!focus.title.isEmpty)
            #expect(!focus.shortTitle.isEmpty)
            #expect(!focus.promise.isEmpty)
            #expect(!focus.icon.isEmpty)
        }
    }

    /// Every focus the app offers has something behind it.
    ///
    /// `tools(for:)` and `focuses` both derive from `itemCount(for:)`, so a
    /// listed-but-empty tool is no longer expressible — what is still worth
    /// asserting is the content side: adding a `PracticeFocus` case without
    /// giving it any exercises would leave a row in Library's Improve list
    /// that leads nowhere.
    @Test func everyFocusShipsMaterial() {
        for focus in PracticeFocus.allCases {
            #expect(
                !PracticeToolKind.tools(for: focus).isEmpty,
                "\(focus.title) has no exercises in any tool"
            )
        }
        #expect(PracticeToolKind.coveredFocuses.count == PracticeFocus.allCases.count)
    }

    @Test func everyShippedExerciseCountsTowardItsTool() {
        let warmUps = PracticeFocus.allCases
            .reduce(0) { $0 + PracticeToolKind.warmUp.itemCount(for: $1) }
        #expect(warmUps == DefaultWarmUps.all.count)

        let calm = PracticeFocus.allCases
            .reduce(0) { $0 + PracticeToolKind.calm.itemCount(for: $1) }
        #expect(calm == DefaultConfidenceExercises.all.count)

        let drills = PracticeFocus.allCases
            .reduce(0) { $0 + PracticeToolKind.drills.itemCount(for: $1) }
        #expect(drills == DrillMode.allCases.count)

        let passages = PracticeFocus.allCases
            .reduce(0) { $0 + PracticeToolKind.readAloud.itemCount(for: $1) }
        #expect(passages == DefaultReadAloudPassages.all.count)
    }

    /// Warm-ups are a composure, clarity and presence tool. If that ever stops
    /// being true the page's headings change, so it is worth stating.
    @Test func warmUpCategoriesMapOntoTheExpectedFocuses() {
        #expect(WarmUpCategory.breathing.focus == .steadyNerves)
        #expect(WarmUpCategory.tonguetwister.focus == .clarity)
        #expect(WarmUpCategory.articulation.focus == .clarity)
        #expect(WarmUpCategory.vocal.focus == .presence)
    }
}
