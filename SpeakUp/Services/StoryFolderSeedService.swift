import Foundation
import SwiftData

/// Applies `StoryFolderHealing` plans to a live `ModelContext`.
/// Fetches full `Story` rows before mutating (never `propertiesToFetch` + save).
@MainActor
enum StoryFolderSeedService {
    static let fingerprintKey = "seededStoryFoldersFingerprint_v1"

    /// Posted after a successful heal/seed that changed the store so open
    /// Stories UIs can reload without waiting for a remote-change notification.
    static let didHealNotification = Notification.Name("SpeakUp.storyFoldersDidHeal")

    /// Returns `true` when folders or story `folderId`s changed.
    @discardableResult
    static func healIfNeeded(in context: ModelContext) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<StoryFolder>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        let folderSnapshots = existing.map {
            StoryFolderHealing.FolderSnapshot(
                id: $0.id,
                name: $0.name,
                sortOrder: $0.sortOrder,
                createdAt: $0.createdAt
            )
        }

        let storedFingerprint = UserDefaults.standard.string(forKey: fingerprintKey)
        let currentFingerprint = StoryFolderHealing.contentFingerprint(folderNames: existing.map(\.name))

        // Folder-only quick plan: detects name collisions + missing defaults
        // without touching Stories. Skip the full Story fetch when clean.
        let quickPlan = StoryFolderHealing.plan(folders: folderSnapshots, storyFolderIDs: [])
        if !quickPlan.needsSave,
           storedFingerprint == currentFingerprint {
            return false
        }

        // Full Story rows — prompt-heal pattern. Never restrict propertiesToFetch
        // on objects we may mutate and save (partial faults can wipe content).
        let stories = try context.fetch(FetchDescriptor<Story>())
        let plan = StoryFolderHealing.plan(
            folders: folderSnapshots,
            storyFolderIDs: stories.compactMap(\.folderId)
        )

        guard plan.needsSave else {
            // Names already unique + defaults present; latch fingerprint.
            UserDefaults.standard.set(currentFingerprint, forKey: fingerprintKey)
            return false
        }

        for story in stories {
            guard let oldID = story.folderId, let keeperID = plan.remaps[oldID] else { continue }
            story.folderId = keeperID
        }

        for folder in existing where plan.duplicateIDs.contains(folder.id) {
            context.delete(folder)
        }

        for spec in plan.missingDefaults {
            context.insert(StoryFolder(
                name: spec.name,
                systemImage: spec.symbol,
                colorHex: spec.colorHex,
                sortOrder: spec.sortOrder
            ))
        }

        try context.save()

        let afterFolders = try context.fetch(FetchDescriptor<StoryFolder>())
        let afterStories = try context.fetch(FetchDescriptor<Story>())
        let verify = StoryFolderHealing.plan(
            folders: afterFolders.map {
                StoryFolderHealing.FolderSnapshot(
                    id: $0.id,
                    name: $0.name,
                    sortOrder: $0.sortOrder,
                    createdAt: $0.createdAt
                )
            },
            storyFolderIDs: afterStories.compactMap(\.folderId)
        )

        if verify.needsSave {
            // CloudKit may have re-imported mid-save — do not latch a dirty FP.
            UserDefaults.standard.removeObject(forKey: fingerprintKey)
        } else {
            UserDefaults.standard.set(
                StoryFolderHealing.contentFingerprint(folderNames: afterFolders.map(\.name)),
                forKey: fingerprintKey
            )
        }

        NotificationCenter.default.post(name: didHealNotification, object: nil)
        return true
    }

    static func invalidateFingerprint() {
        UserDefaults.standard.removeObject(forKey: fingerprintKey)
    }
}
