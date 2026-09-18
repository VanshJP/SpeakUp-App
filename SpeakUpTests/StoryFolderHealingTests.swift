import Foundation
import Testing
@testable import SpeakUp

struct StoryFolderHealingTests {

    private func folder(_ name: String, id: UUID = UUID()) -> StoryFolderHealing.FolderSnapshot {
        StoryFolderHealing.FolderSnapshot(id: id, name: name)
    }

    @Test func emptyStorePlansAllDefaults() {
        let plan = StoryFolderHealing.plan(folders: [], storyFolderIDs: [])
        #expect(plan.missingDefaults.map(\.name) == StoryFolder.defaults.map(\.name))
        #expect(plan.needsSave)
    }

    @Test func existingDefaultsNeedNoInsert() {
        let folders = StoryFolder.defaults.map { folder($0.name) }
        let plan = StoryFolderHealing.plan(folders: folders, storyFolderIDs: [])
        #expect(!plan.needsSave)
    }

    @Test func missingDefaultNameIsReseeded() {
        let plan = StoryFolderHealing.plan(
            folders: [folder("Personal"), folder("Practice Ideas")],
            storyFolderIDs: []
        )
        #expect(plan.missingDefaults.map(\.name) == ["Work"])
        #expect(plan.missingDefaults.first?.sortOrder == 1)
    }

    @Test func duplicateNamesPreferFolderWithMoreStories() {
        let empty = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let dense = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let sparse = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let plan = StoryFolderHealing.plan(
            folders: [
                folder("Personal", id: dense),
                folder(" personal ", id: empty),
                folder("PERSONAL", id: sparse),
                folder("Work", id: UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!)
            ],
            storyFolderIDs: [dense, dense, sparse]
        )
        #expect(plan.duplicateIDs == Set([empty, sparse]))
        #expect(plan.remaps[empty] == dense)
        #expect(plan.remaps[sparse] == dense)
        #expect(plan.remaps[dense] == nil)
        #expect(plan.missingDefaults.map(\.name) == ["Practice Ideas"])
    }

    @Test func tieBreakUsesSmallerUUID() {
        let smaller = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let larger = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
        let plan = StoryFolderHealing.plan(
            folders: [folder("Work", id: larger), folder("Work", id: smaller)],
            storyFolderIDs: []
        )
        #expect(plan.duplicateIDs == Set([larger]))
        #expect(plan.remaps[larger] == smaller)
    }

    @Test func contentFingerprintDetectsSameCountRenameCollision() {
        let healthy = StoryFolderHealing.contentFingerprint(folderNames: [
            "Personal", "Work", "Practice Ideas"
        ])
        let collided = StoryFolderHealing.contentFingerprint(folderNames: [
            "Personal", "Personal", "Practice Ideas"
        ])
        #expect(healthy != collided)
        #expect(healthy == StoryFolderHealing.contentFingerprint(folderNames: [
            " practice ideas ", "PERSONAL", "work"
        ]))
    }

    /// Remap mutates `folderId` only — stands in for full-Story fetch+save wipe guard.
    @Test func applyRemapsTouchesFolderIdOnly() {
        let drop = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let keeper = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let remaps = [drop: keeper]
        var folderId: UUID? = drop
        var title = "Wedding toast"
        var content = "Non-empty body that must survive."
        var tags = ["friends:Alex", "topics:wedding"]
        var attributed: Data? = Data([0x01, 0x02, 0x03])

        if let old = folderId, let keep = remaps[old] { folderId = keep }

        #expect(folderId == keeper)
        #expect(title == "Wedding toast")
        #expect(content == "Non-empty body that must survive.")
        #expect(tags == ["friends:Alex", "topics:wedding"])
        #expect(attributed == Data([0x01, 0x02, 0x03]))
    }

    @Test func displayFolderIDsCollapseDuplicates() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let work = UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!
        #expect(
            StoryFolderHealing.displayFolderIDs(
                folders: [folder("Personal", id: a), folder("Personal", id: b), folder("Work", id: work)],
                storyFolderIDs: [b, b]
            ) == [b, work]
        )
    }

    @Test func siblingIDsIncludeAllSameNormalizedNameFolders() {
        let display = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let ghost = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let work = UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!
        let folders = [
            folder("Personal", id: display),
            folder(" personal ", id: ghost),
            folder("Work", id: work)
        ]
        let siblings = StoryFolderHealing.siblingIDs(of: display, folders: folders)
        #expect(siblings == Set([display, ghost]))
        let remaining = folders.filter { !siblings.contains($0.id) }
        #expect(StoryFolderHealing.displayFolderIDs(folders: remaining, storyFolderIDs: []) == [work])
    }

    @Test func normalizedNameTrimsAndLowercases() {
        #expect(StoryFolderHealing.normalizedName("  Personal ") == "personal")
        #expect(StoryFolderHealing.normalizedName("WORK") == "work")
    }
}
