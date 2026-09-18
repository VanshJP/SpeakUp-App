import Foundation
import SwiftData

/// Pure plan + store apply for StoryFolder CloudKit duplicate heal.
/// Folders use random UUIDs (unlike prompts' stable string ids), so heal keys
/// on **normalized name**. Same-name user folders intentionally collapse.
nonisolated enum StoryFolderHealing {

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Sorted normalized-name multiset + defaults count (not raw row count).
    static func contentFingerprint(folderNames: [String]) -> String {
        let keys = folderNames.map(normalizedName).filter { !$0.isEmpty }.sorted()
        return keys.joined(separator: "\u{1f}") + "|\(StoryFolder.defaults.count)"
    }

    struct FolderSnapshot: Sendable, Equatable {
        let id: UUID
        let name: String
    }

    struct Plan: Sendable {
        let remaps: [UUID: UUID]
        let duplicateIDs: Set<UUID>
        let missingDefaults: [(name: String, symbol: String, colorHex: String, sortOrder: Int)]

        var needsSave: Bool {
            !remaps.isEmpty || !duplicateIDs.isEmpty || !missingDefaults.isEmpty
        }
    }

    /// Prefer more stories; ties → lexicographically smaller UUID.
    static func plan(
        folders: [FolderSnapshot],
        storyFolderIDs: [UUID],
        defaults: [(name: String, symbol: String, colorHex: String)] = StoryFolder.defaults
    ) -> Plan {
        var storyCounts: [UUID: Int] = [:]
        for id in storyFolderIDs { storyCounts[id, default: 0] += 1 }

        var byName: [String: FolderSnapshot] = [:]
        var remaps: [UUID: UUID] = [:]
        var duplicateIDs: Set<UUID> = []

        for folder in folders {
            let key = normalizedName(folder.name)
            guard !key.isEmpty else { continue }
            guard let keeper = byName[key] else {
                byName[key] = folder
                continue
            }

            let kept = preferredKeeper(keeper, folder, storyCounts: storyCounts)
            let dropped = kept.id == keeper.id ? folder : keeper
            byName[key] = kept
            remaps[dropped.id] = kept.id
            duplicateIDs.insert(dropped.id)
            for (from, to) in remaps where to == dropped.id {
                remaps[from] = kept.id
            }
        }

        let present = Set(byName.keys)
        var missing: [(name: String, symbol: String, colorHex: String, sortOrder: Int)] = []
        for (index, spec) in defaults.enumerated() {
            guard !present.contains(normalizedName(spec.name)) else { continue }
            missing.append((spec.name, spec.symbol, spec.colorHex, index))
        }
        return Plan(remaps: remaps, duplicateIDs: duplicateIDs, missingDefaults: missing)
    }

    /// Ids sharing a display chip's normalized name (including `folderID`).
    static func siblingIDs(of folderID: UUID, folders: [FolderSnapshot]) -> Set<UUID> {
        guard let target = folders.first(where: { $0.id == folderID }) else { return [folderID] }
        let key = normalizedName(target.name)
        guard !key.isEmpty else { return [folderID] }
        return Set(folders.filter { normalizedName($0.name) == key }.map(\.id))
    }

    /// One id per normalized name (same keepers as `plan`).
    static func displayFolderIDs(folders: [FolderSnapshot], storyFolderIDs: [UUID]) -> [UUID] {
        let heal = plan(folders: folders, storyFolderIDs: storyFolderIDs)
        var seen = Set<String>()
        var result: [UUID] = []
        for folder in folders {
            let key = normalizedName(folder.name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(heal.remaps[folder.id] ?? folder.id)
        }
        return result
    }

    private static func preferredKeeper(
        _ a: FolderSnapshot,
        _ b: FolderSnapshot,
        storyCounts: [UUID: Int]
    ) -> FolderSnapshot {
        let aCount = storyCounts[a.id, default: 0]
        let bCount = storyCounts[b.id, default: 0]
        if aCount != bCount { return aCount > bCount ? a : b }
        return a.id.uuidString < b.id.uuidString ? a : b
    }
}

// MARK: - Store apply

/// Fetches full `Story` rows before mutating (never `propertiesToFetch` + save).
@MainActor
enum StoryFolderSeedService {
    static let fingerprintKey = "seededStoryFoldersFingerprint_v1"
    static let didHealNotification = Notification.Name("SpeakUp.storyFoldersDidHeal")

    @discardableResult
    static func healIfNeeded(in context: ModelContext) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<StoryFolder>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        let snaps = existing.map { StoryFolderHealing.FolderSnapshot(id: $0.id, name: $0.name) }
        let fingerprint = StoryFolderHealing.contentFingerprint(folderNames: existing.map(\.name))

        if !StoryFolderHealing.plan(folders: snaps, storyFolderIDs: []).needsSave,
           UserDefaults.standard.string(forKey: fingerprintKey) == fingerprint {
            return false
        }

        let stories = try context.fetch(FetchDescriptor<Story>())
        let heal = StoryFolderHealing.plan(
            folders: snaps,
            storyFolderIDs: stories.compactMap(\.folderId)
        )
        guard heal.needsSave else {
            UserDefaults.standard.set(fingerprint, forKey: fingerprintKey)
            return false
        }

        for story in stories {
            guard let old = story.folderId, let keep = heal.remaps[old] else { continue }
            story.folderId = keep
        }
        for folder in existing where heal.duplicateIDs.contains(folder.id) {
            context.delete(folder)
        }
        for spec in heal.missingDefaults {
            context.insert(StoryFolder(
                name: spec.name,
                systemImage: spec.symbol,
                colorHex: spec.colorHex,
                sortOrder: spec.sortOrder
            ))
        }
        try context.save()

        // Name uniqueness / missing defaults don't need story counts.
        let after = try context.fetch(FetchDescriptor<StoryFolder>())
        let afterSnaps = after.map { StoryFolderHealing.FolderSnapshot(id: $0.id, name: $0.name) }
        if StoryFolderHealing.plan(folders: afterSnaps, storyFolderIDs: []).needsSave {
            UserDefaults.standard.removeObject(forKey: fingerprintKey)
        } else {
            UserDefaults.standard.set(
                StoryFolderHealing.contentFingerprint(folderNames: after.map(\.name)),
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
