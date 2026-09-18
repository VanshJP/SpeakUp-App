import Foundation
import Testing
@testable import SpeakUp

struct StoryFolderHealingTests {

    private func folder(
        _ name: String,
        id: UUID = UUID(),
        sortOrder: Int = 0,
        createdAt: Date = .distantPast
    ) -> StoryFolderHealing.FolderSnapshot {
        StoryFolderHealing.FolderSnapshot(
            id: id,
            name: name,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }

    @Test func emptyStorePlansAllDefaults() {
        let plan = StoryFolderHealing.plan(folders: [], storyFolderIDs: [])
        #expect(plan.duplicateIDs.isEmpty)
        #expect(plan.remaps.isEmpty)
        #expect(plan.missingDefaults.map(\.name) == StoryFolder.defaults.map(\.name))
        #expect(plan.needsSave)
    }

    @Test func existingDefaultsNeedNoInsert() {
        let folders = StoryFolder.defaults.enumerated().map { index, spec in
            folder(spec.name, sortOrder: index)
        }
        let plan = StoryFolderHealing.plan(folders: folders, storyFolderIDs: [])
        #expect(plan.missingDefaults.isEmpty)
        #expect(plan.duplicateIDs.isEmpty)
        #expect(!plan.needsSave)
    }

    @Test func missingDefaultNameIsReseeded() {
        let folders = [
            folder("Personal", sortOrder: 0),
            folder("Practice Ideas", sortOrder: 2)
        ]
        let plan = StoryFolderHealing.plan(folders: folders, storyFolderIDs: [])
        #expect(plan.missingDefaults.map(\.name) == ["Work"])
        #expect(plan.missingDefaults.first?.sortOrder == 1)
    }

    @Test func duplicateNamesCollapseAndRemapStories() {
        let keeperID = UUID()
        let dropA = UUID()
        let dropB = UUID()
        let early = Date(timeIntervalSince1970: 1)
        let late = Date(timeIntervalSince1970: 100)

        let folders = [
            folder("Personal", id: dropA, sortOrder: 0, createdAt: late),
            folder(" personal ", id: keeperID, sortOrder: 5, createdAt: early),
            folder("PERSONAL", id: dropB, sortOrder: 1, createdAt: late),
            folder("Work", id: UUID(), sortOrder: 1, createdAt: early)
        ]
        // Stories on the late duplicate should move onto the older keeper.
        let plan = StoryFolderHealing.plan(
            folders: folders,
            storyFolderIDs: [dropA, dropA, dropB]
        )

        #expect(plan.duplicateIDs == Set([dropA, dropB]))
        #expect(plan.remaps[dropA] == keeperID)
        #expect(plan.remaps[dropB] == keeperID)
        #expect(plan.missingDefaults.map(\.name) == ["Practice Ideas"])
    }

    @Test func keeperPrefersFolderWithMoreStories() {
        let sparse = UUID()
        let dense = UUID()
        let early = Date(timeIntervalSince1970: 1)
        let late = Date(timeIntervalSince1970: 100)

        let folders = [
            folder("Work", id: sparse, createdAt: early),
            folder("Work", id: dense, createdAt: late)
        ]
        let plan = StoryFolderHealing.plan(
            folders: folders,
            storyFolderIDs: [dense, dense, dense]
        )

        #expect(plan.duplicateIDs == Set([sparse]))
        #expect(plan.remaps[sparse] == dense)
    }

    @Test func normalizedNameTrimsAndLowercases() {
        #expect(StoryFolderHealing.normalizedName("  Personal ") == "personal")
        #expect(StoryFolderHealing.normalizedName("WORK") == "work")
    }
}
