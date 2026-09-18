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

    @Test func duplicateNamesPreferFolderWithMoreStories() {
        // dropA has 2 stories, dropB has 1, emptyOlder has 0 — story count wins
        // over age (CI failure was asserting the opposite).
        let emptyOlder = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let dropA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let dropB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let early = Date(timeIntervalSince1970: 1)
        let late = Date(timeIntervalSince1970: 100)

        let folders = [
            folder("Personal", id: dropA, sortOrder: 0, createdAt: late),
            folder(" personal ", id: emptyOlder, sortOrder: 5, createdAt: early),
            folder("PERSONAL", id: dropB, sortOrder: 1, createdAt: late),
            folder("Work", id: UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!, sortOrder: 1, createdAt: early)
        ]
        let plan = StoryFolderHealing.plan(
            folders: folders,
            storyFolderIDs: [dropA, dropA, dropB]
        )

        #expect(plan.duplicateIDs == Set([emptyOlder, dropB]))
        #expect(plan.remaps[emptyOlder] == dropA)
        #expect(plan.remaps[dropB] == dropA)
        #expect(plan.remaps[dropA] == nil)
        #expect(plan.missingDefaults.map(\.name) == ["Practice Ideas"])
    }

    @Test func keeperPrefersFolderWithMoreStories() {
        let sparse = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let dense = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
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

    @Test func tieBreakUsesSmallerUUIDNotCreatedAt() {
        let smaller = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let larger = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
        let folders = [
            folder("Work", id: larger, createdAt: Date(timeIntervalSince1970: 1)),
            folder("Work", id: smaller, createdAt: Date(timeIntervalSince1970: 100))
        ]
        let plan = StoryFolderHealing.plan(folders: folders, storyFolderIDs: [])
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

    @Test func applyRemapsTouchesFolderIdOnly() {
        let drop = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let keeper = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let attributed = Data([0x01, 0x02, 0x03])
        var stories = [
            StoryFolderHealing.StoryRef(
                id: UUID(),
                folderId: drop,
                title: "Wedding toast",
                content: "Non-empty body that must survive.",
                tags: ["friends:Alex", "topics:wedding"],
                contentAttributed: attributed
            )
        ]

        StoryFolderHealing.applyRemaps(to: &stories, remaps: [drop: keeper])

        #expect(stories[0].folderId == keeper)
        #expect(stories[0].title == "Wedding toast")
        #expect(stories[0].content == "Non-empty body that must survive.")
        #expect(stories[0].tags == ["friends:Alex", "topics:wedding"])
        #expect(stories[0].contentAttributed == attributed)
    }

    @Test func displayFolderIDsCollapseDuplicates() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let work = UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!
        let ids = StoryFolderHealing.displayFolderIDs(
            folders: [
                folder("Personal", id: a),
                folder("Personal", id: b),
                folder("Work", id: work)
            ],
            storyFolderIDs: [b, b]
        )
        #expect(ids == [b, work])
    }

    @Test func normalizedNameTrimsAndLowercases() {
        #expect(StoryFolderHealing.normalizedName("  Personal ") == "personal")
        #expect(StoryFolderHealing.normalizedName("WORK") == "work")
    }
}
