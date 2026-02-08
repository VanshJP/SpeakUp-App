import Foundation
import SwiftData

@Model
final class Recording {
    var id: UUID
    var date: Date
    var prompt: Prompt?
    var targetDuration: Int // 30, 60, 90, 120 seconds
    var actualDuration: TimeInterval
    var mediaType: MediaType
    var audioURL: URL?
    var videoURL: URL?
    var thumbnailURL: URL?
    var transcriptionText: String?
    var transcriptionWords: [TranscriptionWord]?
    var analysis: SpeechAnalysis?
    var isProcessing: Bool
    var isFavorite: Bool
    var customTitle: String?

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
        customTitle: String? = nil
    ) {
        self.id = id
        self.date = date
        self.prompt = prompt
        self.targetDuration = targetDuration
        self.actualDuration = actualDuration
        self.mediaType = mediaType
        self.audioURL = audioURL
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.transcriptionText = transcriptionText
        self.transcriptionWords = transcriptionWords
        self.analysis = analysis
        self.isProcessing = isProcessing
        self.isFavorite = isFavorite
        self.customTitle = customTitle
    }

    /// Display title: custom title, prompt text, or fallback
    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }
        return prompt?.text ?? "Practice Session"
    }
    
    // Computed property to check if media file is downloaded from iCloud
    var isDownloaded: Bool {
        guard let url = videoURL ?? audioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    // Formatted date string
    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
    
    // Formatted duration string
    var formattedDuration: String {
        let minutes = Int(actualDuration) / 60
        let seconds = Int(actualDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .thirty: return "30s"
        case .sixty: return "1m"
        case .ninety: return "1.5m"
        case .onetwenty: return "2m"
        }
    }
    
    var seconds: Int { rawValue }
}
