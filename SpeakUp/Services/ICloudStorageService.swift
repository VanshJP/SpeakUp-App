import Foundation

/// Manages iCloud ubiquity container for audio file storage and sync.
/// Falls back to local Documents directory when iCloud is unavailable.
@Observable
final class ICloudStorageService {
    static let shared = ICloudStorageService()

    private let containerIdentifier = "iCloud.cam.vanshpatel.SpeakUp"
    private let recordingsSubdirectory = "Recordings"

    /// UserDefaults key mirroring the SwiftData iCloudSyncEnabled setting.
    /// Used because ModelContainer is created before SwiftData is available.
    static let syncEnabledKey = "iCloudSyncEnabled"

    /// The resolved iCloud container URL, or nil if iCloud is unavailable.
    private(set) var ubiquityContainerURL: URL?

    /// Whether the ubiquity container check has completed.
    private(set) var hasResolvedContainer = false

    /// Whether iCloud Drive is available AND the user has enabled sync.
    var isICloudAvailable: Bool {
        ubiquityContainerURL != nil && isSyncEnabled
    }

    /// Whether the user has opted in to iCloud sync.
    var isSyncEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.syncEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Self.syncEnabledKey) }
    }

    /// Whether iCloud is technically reachable (signed in), regardless of user preference.
    var isICloudReachable: Bool { ubiquityContainerURL != nil }

    private init() {
        // Resolve ubiquity container on a background thread (can block briefly)
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let url = FileManager.default.url(forUbiquityContainerIdentifier: self.containerIdentifier)
            await MainActor.run {
                self.ubiquityContainerURL = url
                self.hasResolvedContainer = true
            }
            // Ensure the Recordings subdirectory exists in iCloud
            if let url {
                let recordingsDir = url.appendingPathComponent("Documents/\(self.recordingsSubdirectory)")
                try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Storage Directory

    /// Returns the directory where new recordings should be stored.
    /// Uses iCloud ubiquity container when available, local Documents otherwise.
    var recordingsDirectory: URL {
        if let ubiquityURL = ubiquityContainerURL {
            return ubiquityURL
                .appendingPathComponent("Documents")
                .appendingPathComponent(recordingsSubdirectory)
        }
        return Self.localDocumentsDirectory
    }

    /// Local-only Documents directory (always available).
    static let localDocumentsDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    // MARK: - File Resolution

    /// Resolves a filename to a full URL, checking iCloud first, then local Documents.
    /// Returns nil if the file doesn't exist in either location.
    func resolveFile(named filename: String) -> URL? {
        // Check iCloud container first
        if let ubiquityURL = ubiquityContainerURL {
            let iCloudPath = ubiquityURL
                .appendingPathComponent("Documents")
                .appendingPathComponent(recordingsSubdirectory)
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: iCloudPath.path) {
                return iCloudPath
            }

            // File might exist but not be downloaded yet — check for .icloud placeholder
            let iCloudPlaceholder = iCloudPath
                .deletingLastPathComponent()
                .appendingPathComponent(".\(filename).icloud")
            if FileManager.default.fileExists(atPath: iCloudPlaceholder.path) {
                // Trigger download and return the expected final path
                try? FileManager.default.startDownloadingUbiquitousItem(at: iCloudPath)
                return iCloudPath
            }
        }

        // Fall back to local Documents
        let localPath = Self.localDocumentsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: localPath.path) {
            return localPath
        }

        return nil
    }

    // MARK: - Migration

    /// Moves existing local recordings to iCloud container.
    /// Called once when iCloud becomes available.
    func migrateLocalFilesToICloud() async {
        guard let ubiquityURL = ubiquityContainerURL else { return }
        let iCloudRecordingsDir = ubiquityURL
            .appendingPathComponent("Documents")
            .appendingPathComponent(recordingsSubdirectory)

        let localDir = Self.localDocumentsDirectory
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(atPath: localDir.path) else { return }

        for file in files where file.hasSuffix(".m4a") || file.hasSuffix(".mp4") {
            let localFile = localDir.appendingPathComponent(file)
            let iCloudFile = iCloudRecordingsDir.appendingPathComponent(file)

            guard !fm.fileExists(atPath: iCloudFile.path) else { continue }

            do {
                try fm.setUbiquitous(true, itemAt: localFile, destinationURL: iCloudFile)
            } catch {
                print("Failed to move \(file) to iCloud: \(error)")
            }
        }
    }

    // MARK: - Download Status

    /// Checks whether a file is fully downloaded from iCloud.
    func isFileDownloaded(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        do {
            let resources = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = resources.ubiquitousItemDownloadingStatus {
                return status == .current
            }
            // Not an iCloud file — it's local, so it's "downloaded"
            return true
        } catch {
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// Triggers download of an iCloud file if it's not yet local.
    func ensureDownloaded(at url: URL) {
        if !isFileDownloaded(at: url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    // MARK: - Deletion

    /// Removes a file from both local storage and iCloud (if ubiquitous).
    /// `FileManager.removeItem` on a ubiquitous file automatically propagates
    /// the deletion to iCloud, so no extra API call is needed.
    func removeFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
