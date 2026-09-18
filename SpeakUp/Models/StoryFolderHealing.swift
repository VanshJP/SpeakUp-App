import Foundation

/// Pure plan for StoryFolder seed + CloudKit duplicate heal.
/// Unique constraints are unavailable with CloudKit, so reinstall / second-device
/// sync can leave many same-named folders. Collapse by normalized name, remap
/// story `folderId`s onto the keeper, then insert any missing default names.
///
/// Unlike prompts (stable string `id`), folder identity is a random UUID, so
/// heal keys on **normalized name**. Intentional: two user folders named
/// "Personal" collapse into one on the next heal pass.
nonisolated enum StoryFolderHealing {

    /// Trim + case-fold so "Personal" / " personal " collide.
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Multiset of normalized names (sorted) plus shipped-default count.
    /// Detects same-count rename collisions and 1:1 CloudKit re-imports that
    /// a raw `fetchCount` fingerprint would miss.
    static func contentFingerprint(
        folderNames: [String],
        defaultsCount: Int = StoryFolder.defaults.count
    ) -> String {
        let keys = folderNames
            .map(normalizedName)
            .filter { !$0.isEmpty }
            .sorted()
        return keys.joined(separator: "\u{1f}") + "|\(defaultsCount)"
    }

    /// Snapshot of one store row used only for planning (no SwiftData types).
    struct FolderSnapshot: Sendable, Equatable {
        let id: UUID
        let name: String
        let sortOrder: Int
        let createdAt: Date
    }

    /// POD story row for remap unit tests (mirrors `Story.folderId` mutation).
    struct StoryRef: Sendable, Equatable {
        var id: UUID
        var folderId: UUID?
        var title: String
        var content: String
        var tags: [String]
        var contentAttributed: Data?
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
    /// ties break toward the lexicographically smaller UUID (stable across devices).
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

    /// Remap `folderId` only — title/content/tags/rtf stay untouched (apply-path contract).
    static func applyRemaps(to stories: inout [StoryRef], remaps: [UUID: UUID]) {
        for index in stories.indices {
            guard let oldID = stories[index].folderId, let keeperID = remaps[oldID] else { continue }
            stories[index].folderId = keeperID
        }
    }

    /// All folder ids that share the display chip's normalized name (including `folderID`).
    /// Used so deleting a `foldersForDisplay` chip removes CloudKit siblings, not one UUID.
    static func siblingIDs(
        of folderID: UUID,
        folders: [FolderSnapshot]
    ) -> Set<UUID> {
        guard let target = folders.first(where: { $0.id == folderID }) else {
            return [folderID]
        }
        let key = normalizedName(target.name)
        guard !key.isEmpty else { return [folderID] }
        return Set(
            folders
                .filter { normalizedName($0.name) == key }
                .map(\.id)
        )
    }

    /// One folder per normalized name for UI (chips / Move sheet) so ghosts
    /// cannot flood surfaces before heal finishes. Prefer higher story count,
    /// then smaller UUID — same rule as heal keepers.
    static func displayFolderIDs(
        folders: [FolderSnapshot],
        storyFolderIDs: [UUID]
    ) -> [UUID] {
        var storyCounts: [UUID: Int] = [:]
        for id in storyFolderIDs {
            storyCounts[id, default: 0] += 1
        }

        var byName: [String: FolderSnapshot] = [:]
        var order: [String] = []
        for folder in folders {
            let key = normalizedName(folder.name)
            guard !key.isEmpty else { continue }
            guard let existing = byName[key] else {
                byName[key] = folder
                order.append(key)
                continue
            }
            byName[key] = preferredKeeper(existing, folder, storyCounts: storyCounts)
        }
        return order.compactMap { byName[$0]?.id }
    }

    private static func preferredKeeper(
        _ a: FolderSnapshot,
        _ b: FolderSnapshot,
        storyCounts: [UUID: Int]
    ) -> FolderSnapshot {
        let aCount = storyCounts[a.id, default: 0]
        let bCount = storyCounts[b.id, default: 0]
        if aCount != bCount { return aCount > bCount ? a : b }
        // Deterministic across devices (ignore createdAt — CloudKit can skew it).
        return a.id.uuidString < b.id.uuidString ? a : b
    }
}
