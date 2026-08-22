import Foundation
import SwiftData

@Model
final class Recording {
    var id: UUID = UUID()
    var date: Date = Date()
    var prompt: Prompt?
    var targetDuration: Int = 60
    var actualDuration: TimeInterval = 0
    var mediaType: MediaType = MediaType.audio
    var audioURL: URL?
    var videoURL: URL?
    var thumbnailURL: URL?
    var transcriptionText: String?
    var transcriptionWords: [TranscriptionWord]?
    var analysis: SpeechAnalysis?
    /// Full-fidelity JSON mirror of `analysis`, written beside it.
    ///
    /// SwiftData's decoder drops every advanced metric on read (see
    /// `SpeechAnalysis.init(from:)` for why it has to), so `analysis` comes
    /// back carrying only the headline numbers once a recording has been read
    /// from the store rather than just written to it. Coaching reasons about
    /// exactly the fields that go missing, so it reads `fullAnalysis` instead.
    var analysisJSON: Data?
    var isProcessing: Bool = false
    var lastProcessingError: String?
    var isFavorite: Bool = false
    var customTitle: String?
    var drillMode: String?
    var frameworkUsed: String?
    var sessionFeedback: SessionFeedback?
    var goalId: UUID?
    var groupId: UUID?
    var storyId: UUID?
    var storyTitle: String?
    var waveformPeaks: [Float]?
    /// Word-workout snapshot: the day stamp and spotlight words that were live
    /// when this recording's analysis landed. Written once by
    /// `RecordingProcessingCoordinator`; the detail view scores this session
    /// against these words so an older take is judged by its own day's list,
    /// never today's. Both optional — recordings analyzed before snapshots
    /// existed simply have none.
    var vocabChallengeDayStamp: String?
    var vocabChallengeWords: [VocabChallengeWord]?
    /// Set when the recording was saved but left unanalyzed because the free
    /// allowance was spent. The audio is untouched — analysis runs the moment
    /// the allowance resets or Lifetime is purchased.
    var analysisBlockedByAllowance: Bool = false
    @Transient var audioLevelSamples: [Float]? = nil

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        prompt: Prompt? = nil,
        targetDuration: Int = 60,
        actualDuration: TimeInterval = 0,
        mediaType: MediaType = .audio,
        audioURL: URL? = nil,
        videoURL: URL? = nil,
        thumbnailURL: URL? = nil,
        transcriptionText: String? = nil,
        transcriptionWords: [TranscriptionWord]? = nil,
        analysis: SpeechAnalysis? = nil,
        isProcessing: Bool = false,
        isFavorite: Bool = false,
        customTitle: String? = nil,
        drillMode: String? = nil,
        frameworkUsed: String? = nil,
        audioLevelSamples: [Float]? = nil,
        goalId: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.prompt = prompt
        self.targetDuration = targetDuration
        self.actualDuration = actualDuration
        self.mediaType = mediaType
        self.audioURL = audioURL.map { Self.relativeURL(from: $0) }
        self.videoURL = videoURL.map { Self.relativeURL(from: $0) }
        self.thumbnailURL = thumbnailURL.map { Self.relativeURL(from: $0) }
        self.transcriptionText = transcriptionText
        self.transcriptionWords = transcriptionWords
        self.analysis = analysis
        self.analysisJSON = analysis?.encodedMirror()
        self.isProcessing = isProcessing
        self.isFavorite = isFavorite
        self.customTitle = customTitle
        self.drillMode = drillMode
        self.frameworkUsed = frameworkUsed
        self.audioLevelSamples = audioLevelSamples
        self.goalId = goalId
    }

    // MARK: - Analysis

    /// Writes the analysis and its full-fidelity mirror together.
    ///
    /// Always use this rather than assigning `analysis` directly — a write that
    /// skips the mirror leaves the advanced metrics recoverable only until the
    /// next launch.
    func setAnalysis(_ analysis: SpeechAnalysis?) {
        self.analysis = analysis
        self.analysisJSON = analysis?.encodedMirror()
    }

    /// The analysis with its advanced metrics intact.
    ///
    /// Decodes a JSON blob, so it must not be called from a view `body` — read
    /// it once into state. Falls back to the lossy SwiftData copy for
    /// recordings analyzed before the mirror existed.
    var fullAnalysis: SpeechAnalysis? {
        guard let analysisJSON else { return analysis }
        return SpeechAnalysis.decodedMirror(analysisJSON) ?? analysis
    }

    /// Display title: custom title, story title, prompt text, or fallback
    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }
        if let storyTitle, !storyTitle.isEmpty {
            return storyTitle
        }
        return prompt?.text ?? "Practice Session"
    }

    // MARK: - Resolved File URLs

    /// Resolves the stored audio path (filename or legacy absolute) to a full Documents URL.
    var resolvedAudioURL: URL? {
        Self.resolveStoredURL(audioURL)
    }

    /// Resolves the stored video path (filename or legacy absolute) to a full Documents URL.
    var resolvedVideoURL: URL? {
        Self.resolveStoredURL(videoURL)
    }

    /// Resolves the stored thumbnail path (filename or legacy absolute) to a full Documents URL.
    var resolvedThumbnailURL: URL? {
        Self.resolveStoredURL(thumbnailURL)
    }

    /// Converts a full file URL to a relative-only URL for storage.
    static func relativeURL(from url: URL) -> URL {
        let filename = url.lastPathComponent
        if let relative = URL(string: filename) {
            return relative
        }
        // Filenames with spaces/unsafe chars fail URL(string:) — percent-encode
        // rather than trap. Falls back to the original absolute URL if all else
        // fails; resolveStoredURL handles the legacy-absolute branch.
        if let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let relative = URL(string: encoded) {
            return relative
        }
        return url
    }

    /// Resolves a stored URL: if it's already absolute and the file exists, returns it as-is.
    /// If relative (just a filename), checks iCloud container first, then local Documents.
    private static func resolveStoredURL(_ stored: URL?) -> URL? {
        guard let stored else { return nil }

        let filename: String

        if stored.path.hasPrefix("/") {
            // Legacy absolute path — check if file still exists at original location
            if FileManager.default.fileExists(atPath: stored.path) {
                return stored
            }
            // File moved — extract filename and try resolving
            filename = stored.lastPathComponent
        } else {
            filename = stored.path
        }

        // Resolve via iCloud service (checks iCloud container, then local Documents)
        return ICloudStorageService.shared.resolveFile(named: filename)
    }

    // Formatted duration string
    var formattedDuration: String {
        actualDuration.minutesSeconds
    }
}

// MARK: - Supporting Types

enum MediaType: String, Codable, CaseIterable {
    case audio
    case video
    
    var displayName: String {
        switch self {
        case .audio: return "Audio"
        case .video: return "Video"
        }
    }
    
    var iconName: String {
        switch self {
        case .audio: return "mic.fill"
        case .video: return "video.fill"
        }
    }
}

enum RecordingDuration: Int, CaseIterable, Identifiable {
    case thirty = 30
    case sixty = 60
    case ninety = 90
    case onetwenty = 120
    case threeMinutes = 180
    case fiveMinutes = 300
    case tenMinutes = 600

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .thirty: return "30s"
        case .sixty: return "1m"
        case .ninety: return "1.5m"
        case .onetwenty: return "2m"
        case .threeMinutes: return "3m"
        case .fiveMinutes: return "5m"
        case .tenMinutes: return "10m"
        }
    }

    var seconds: Int { rawValue }
}
