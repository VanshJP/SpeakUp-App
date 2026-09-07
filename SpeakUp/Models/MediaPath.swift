import Foundation

/// Basename-only media path helpers for Documents / iCloud resolution.
///
/// `Recording` stores relative filenames, but a corrupted or tampered row can
/// carry `../` segments or absolute paths. Resolving those with
/// `appendingPathComponent` would walk outside the recordings directory.
nonisolated enum MediaPath {
    /// Returns a single path component safe to append under Documents / iCloud,
    /// or nil when the input is empty, `.` / `..`, or still contains separators.
    static func sanitizedFilename(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Collapse any directory prefix — only the last component may resolve.
        let base = (trimmed as NSString).lastPathComponent
        guard !base.isEmpty, base != ".", base != ".." else { return nil }
        guard !base.contains("\0") else { return nil }
        // `lastPathComponent` already strips `/`; still reject raw separators
        // that some Foundation paths leave intact (e.g. Windows-style).
        guard !base.contains("/"), !base.contains("\\") else { return nil }
        return base
    }

    /// True when `url` (after symlink resolution) sits under local Documents or
    /// the app's iCloud container. Used to keep legacy absolute media URLs —
    /// and in-root symlinks — from pointing at arbitrary sandbox files.
    static func isUnderAllowedMediaRoot(_ url: URL, ubiquityContainer: URL? = nil) -> Bool {
        let standardized = url.resolvingSymlinksInPath().standardizedFileURL.path
        // Resolved here rather than via `ICloudStorageService.localDocumentsDirectory`
        // so this pure helper stays `nonisolated` under MainActor default isolation.
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        if standardized == documents || standardized.hasPrefix(documents + "/") {
            return true
        }
        if let ubiquity = ubiquityContainer?
            .resolvingSymlinksInPath()
            .standardizedFileURL.path,
           standardized == ubiquity || standardized.hasPrefix(ubiquity + "/") {
            return true
        }
        return false
    }
}
