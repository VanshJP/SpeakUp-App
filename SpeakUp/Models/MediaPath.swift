import Foundation

nonisolated enum MediaPath {
    static func sanitizedFilename(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Collapse any directory prefix — only the last component may resolve.
        let base = (trimmed as NSString).lastPathComponent
        guard !base.isEmpty, base != ".", base != ".." else { return nil }
        guard !base.contains("\0") else { return nil }
        guard !base.contains("/"), !base.contains("\\") else { return nil }
        return base
    }

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
