import Foundation
import os.log

@Observable
final class ICloudStorageService {
    private let logger = Logger.app("iCloudStorage")
    static let shared = ICloudStorageService()

    private let containerIdentifier = "iCloud.cam.vanshpatel.SpeakUp"
    private let recordingsSubdirectory = "Recordings"

    /// UserDefaults key mirroring the SwiftData iCloudSyncEnabled setting.
    /// Used because ModelContainer is created before SwiftData is available.
    static let syncEnabledKey = "iCloudSyncEnabled"

    /// Effective startup sync preference.
    /// If the user has never explicitly chosen a value (fresh install), default
    /// to enabled when iCloud account credentials are available so reinstall can
    /// restore cloud data automatically.
    static var resolvedSyncEnabledPreference: Bool {
        if let storedPreference = UserDefaults.standard.object(forKey: syncEnabledKey) as? Bool {
            return storedPreference
        }
        return FileManager.default.ubiquityIdentityToken != nil
    }

    private(set) var ubiquityContainerURL: URL?

    private(set) var hasResolvedContainer = false

    var isICloudAvailable: Bool {
        ubiquityContainerURL != nil && isSyncEnabled
    }

    var isSyncEnabled: Bool {
        get { Self.resolvedSyncEnabledPreference }
        set { UserDefaults.standard.set(newValue, forKey: Self.syncEnabledKey) }
    }

    var isICloudReachable: Bool { ubiquityContainerURL != nil }

    private init() {
        if UserDefaults.standard.object(forKey: Self.syncEnabledKey) == nil {
            UserDefaults.standard.set(Self.resolvedSyncEnabledPreference, forKey: Self.syncEnabledKey)
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let url = FileManager.default.url(forUbiquityContainerIdentifier: self.containerIdentifier)
            await MainActor.run {
                self.ubiquityContainerURL = url
                self.hasResolvedContainer = true
            }
            if let url {
                let recordingsDir = url.appendingPathComponent("Documents/\(self.recordingsSubdirectory)")
                try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Storage Directory

    /// Directory for active AVAudioRecorder captures.
    /// Always local Documents — never the ubiquity container. Writing an open
    var recordingsDirectory: URL {
        Self.localDocumentsDirectory
    }

    var iCloudRecordingsDirectory: URL? {
        guard let ubiquityURL = ubiquityContainerURL else { return nil }
        return ubiquityURL
            .appendingPathComponent("Documents")
            .appendingPathComponent(recordingsSubdirectory)
    }

    static let localDocumentsDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    // MARK: - File Resolution

    func resolveFile(named filename: String) -> URL? {
        guard let filename = MediaPath.sanitizedFilename(filename) else { return nil }

        if let ubiquityURL = ubiquityContainerURL {
            let iCloudPath = ubiquityURL
                .appendingPathComponent("Documents")
                .appendingPathComponent(recordingsSubdirectory)
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: iCloudPath.path),
               MediaPath.isUnderAllowedMediaRoot(iCloudPath, ubiquityContainer: ubiquityURL) {
                return iCloudPath
            }

            // File might exist but not be downloaded yet — check for .icloud placeholder
            let iCloudPlaceholder = iCloudPath
                .deletingLastPathComponent()
                .appendingPathComponent(".\(filename).icloud")
            if FileManager.default.fileExists(atPath: iCloudPlaceholder.path),
               MediaPath.isUnderAllowedMediaRoot(iCloudPath, ubiquityContainer: ubiquityURL) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: iCloudPath)
                return iCloudPath
            }
        }

        let localPath = Self.localDocumentsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: localPath.path),
           MediaPath.isUnderAllowedMediaRoot(localPath) {
            return localPath
        }

        return nil
    }

    // MARK: - Migration

    @discardableResult
    func promoteToICloudIfNeeded(localURL: URL) -> URL {
        guard isICloudAvailable, let iCloudDir = iCloudRecordingsDirectory else {
            return localURL
        }

        let fm = FileManager.default
        try? fm.createDirectory(at: iCloudDir, withIntermediateDirectories: true)

        let destination = iCloudDir.appendingPathComponent(localURL.lastPathComponent)
        guard !fm.fileExists(atPath: destination.path) else { return destination }

        do {
            try fm.setUbiquitous(true, itemAt: localURL, destinationURL: destination)
            return destination
        } catch {
            logger.error("Failed to promote \(localURL.lastPathComponent) to iCloud: \(error.localizedDescription, privacy: .private(mask: .hash))")
            return localURL
        }
    }

    func migrateLocalFilesToICloud() async {
        guard isICloudAvailable, let iCloudRecordingsDir = iCloudRecordingsDirectory else { return }

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
                logger.error("Failed to move \(file) to iCloud: \(error.localizedDescription, privacy: .private(mask: .hash))")
            }
        }
    }

    // MARK: - Download Status

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

    func ensureDownloaded(at url: URL) {
        if !isFileDownloaded(at: url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    // MARK: - Deletion

    func removeFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
