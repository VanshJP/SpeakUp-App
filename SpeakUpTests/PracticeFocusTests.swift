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

    @Test func everyCoachDimensionRoutesToAFocus() {
        // Exhaustive by construction; this pins the pairs that carry meaning.
        #expect(PracticeFocus.matching(.fillers) == .fillers)
        #expect(PracticeFocus.matching(.pace) == .pace)
        #expect(PracticeFocus.matching(.pauses) == .pauses)
        #expect(PracticeFocus.matching(.clarity) == .clarity)
        #expect(PracticeFocus.matching(.delivery) == .presence)
        #expect(PracticeFocus.matching(.vocalVariety) == .presence)
        #expect(PracticeFocus.matching(.structure) == .structure)
        #expect(PracticeFocus.matching(.vocabulary) == .structure)
        #expect(PracticeFocus.matching(.relevance) == .structure)
    }

    /// Composure has no subscore, and practice-tools invariant 1 says not to
    /// invent one. The nil is load-bearing, not an oversight.
    @Test func composureFocusesClaimNoScoredDimension() {
        #expect(PracticeFocus.steadyNerves.coachDimension == nil)
        #expect(PracticeFocus.mindset.coachDimension == nil)
        #expect(PracticeFocus.clarity.coachDimension == .clarity)
        #expect(PracticeFocus.presence.coachDimension == .vocalVariety)
    }

    /// The focus browser's core promise: a tool listed under a focus has
    /// something to show when you push into it.
    @Test func listedToolsAlwaysHaveItems() {
        for focus in PracticeFocus.allCases {
            for tool in PracticeToolKind.tools(for: focus) {
                #expect(
                    tool.itemCount(for: focus) > 0,
                    "\(tool.title) is listed under \(focus.title) with no items"
                )
            }
        }
    }

    /// And the converse: a tool with material for a focus is never hidden from
    /// that focus's page.
    @Test func toolsWithItemsAreAlwaysListed() {
        for focus in PracticeFocus.allCases {
            for tool in PracticeToolKind.practiceTools where tool.itemCount(for: focus) > 0 {
                #expect(
                    PracticeToolKind.tools(for: focus).contains(tool),
                    "\(tool.title) has items for \(focus.title) but is not listed"
                )
            }
        }
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

    /// Read Aloud's catalog filter must never offer a pill that filters to
    /// nothing, and must never hide a category behind no pill at all.
    @Test func readAloudCatalogFocusesCoverEveryCatalogCategory() {
        let covered = ReadAloudCategory.catalogFocuses
            .flatMap { ReadAloudCategory.catalogCases(for: $0) }
        #expect(Set(covered) == Set(ReadAloudCategory.catalogCases))
        #expect(!covered.contains(.custom))
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
