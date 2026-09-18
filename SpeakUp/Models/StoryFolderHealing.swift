import Foundation

/// Pure plan for StoryFolder seed + CloudKit duplicate heal.
/// Unique constraints are unavailable with CloudKit, so reinstall / second-device
/// sync can leave many same-named folders. Collapse by normalized name, remap
/// story `folderId`s onto the keeper, then insert any missing default names.
nonisolated enum StoryFolderHealing {

    /// Trim + case-fold so "Personal" / " personal " collide.
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Snapshot of one store row used only for planning (no SwiftData types).
    struct FolderSnapshot: Sendable, Equatable {
        let id: UUID
        let name: String
        let sortOrder: Int
        let createdAt: Date
    }

    struct Plan: Sendable, Equatable {
        /// Dropped folder id → keeper folder id.
        let remaps: [UUID: UUID]
        let duplicateIDs: Set<UUID>
        /// Default specs still missing after heal (name, symbol, colorHex, sortOrder).
        let missingDefaults: [(name: String, symbol: String, colorHex: String, sortOrder: Int)]

        static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.remaps == rhs.remaps
                && lhs.duplicateIDs == rhs.duplicateIDs
                && lhs.missingDefaults.map { "\($0.name)|\($0.symbol)|\($0.colorHex)|\($0.sortOrder)" }
                    == rhs.missingDefaults.map { "\($0.name)|\($0.symbol)|\($0.colorHex)|\($0.sortOrder)" }
        }

        var needsSave: Bool {
            !remaps.isEmpty || !duplicateIDs.isEmpty || !missingDefaults.isEmpty
        }
    }

    /// Build a heal + seed plan. Prefer the folder that already owns more stories;
    /// ties break toward older `createdAt`, then lower `sortOrder`, then stable UUID.
    static func plan(
        folders: [FolderSnapshot],
        storyFolderIDs: [UUID],
        defaults: [(name: String, symbol: String, colorHex: String)] = StoryFolder.defaults
    ) -> Plan {
        var storyCounts: [UUID: Int] = [:]
        storyCounts.reserveCapacity(storyFolderIDs.count)
        for id in storyFolderIDs {
            storyCounts[id, default: 0] += 1
        }

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
            // If an earlier remap pointed at the dropped folder, retarget it.
            for (from, to) in remaps where to == dropped.id {
                remaps[from] = kept.id
            }
        }

        let presentNames = Set(byName.keys)
        var missingDefaults: [(name: String, symbol: String, colorHex: String, sortOrder: Int)] = []
        for (index, spec) in defaults.enumerated() {
            let key = normalizedName(spec.name)
            guard !presentNames.contains(key) else { continue }
            missingDefaults.append((spec.name, spec.symbol, spec.colorHex, index))
        }

        return Plan(remaps: remaps, duplicateIDs: duplicateIDs, missingDefaults: missingDefaults)
    }

    private static func preferredKeeper(
        _ a: FolderSnapshot,
        _ b: FolderSnapshot,
        storyCounts: [UUID: Int]
    ) -> FolderSnapshot {
        let aCount = storyCounts[a.id, default: 0]
        let bCount = storyCounts[b.id, default: 0]
        if aCount != bCount { return aCount > bCount ? a : b }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt ? a : b }
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder ? a : b }
        return a.id.uuidString < b.id.uuidString ? a : b
    }
}
