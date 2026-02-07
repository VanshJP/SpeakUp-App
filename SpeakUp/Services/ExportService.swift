import Foundation
import Photos
import UniformTypeIdentifiers
import UIKit

@Observable
class ExportService {
    var isSaving = false
    var hasPhotoLibraryPermission = false
    
    // MARK: - Permissions
    
    func requestPhotoLibraryPermission() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        hasPhotoLibraryPermission = status == .authorized || status == .limited
        return hasPhotoLibraryPermission
    }
    
    // MARK: - Share
    
    @MainActor
    func shareRecording(_ recording: Recording, scoreCardImage: UIImage? = nil) {
        var items: [Any] = []

        // Score card image first (most visual)
        if let image = scoreCardImage {
            items.append(image)
        }

        // Add media file
        if let videoURL = recording.videoURL {
            items.append(videoURL)
        } else if let audioURL = recording.audioURL {
            items.append(audioURL)
        }

        // Add text summary
        let summary = generateShareText(for: recording)
        items.append(summary)
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            
            // Handle iPad popover
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootVC.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Save to Photos
    
    func saveToPhotoLibrary(_ recording: Recording) async throws {
        if !hasPhotoLibraryPermission {
            let granted = await requestPhotoLibraryPermission()
            guard granted else {
                throw ExportError.noPermission
            }
        }
        
        guard let mediaURL = recording.videoURL ?? recording.audioURL else {
            throw ExportError.noMediaFile
        }
        
        isSaving = true
        defer { isSaving = false }
        
        guard recording.mediaType == .video else {
            throw ExportError.audioNotSupported
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: mediaURL)
        }
    }
    
    // MARK: - Text Generation
    
    func generateShareText(for recording: Recording) -> String {
        var text = "SpeakUp Practice Session\n"
        text += "Date: \(recording.date.formatted(date: .abbreviated, time: .shortened))\n"
        
        if let prompt = recording.prompt {
            text += "Topic: \(prompt.category)\n"
        }
        
        text += "Duration: \(recording.formattedDuration)\n"
        
        if let analysis = recording.analysis {
            text += "\nResults:\n"
            text += "Overall Score: \(analysis.speechScore.overall)/100\n"
            text += "Words per minute: \(Int(analysis.wordsPerMinute))\n"
            text += "Filler words: \(analysis.totalFillerCount)\n"
        }
        
        text += "\nPractice your speaking with SpeakUp!"
        text += "\n#SpeakUp #PublicSpeaking"

        return text
    }

    func generateSocialShareText(for recording: Recording) -> String {
        var text = ""
        
        if let analysis = recording.analysis {
            let score = analysis.speechScore.overall
            
            if score >= 80 {
                text += "Crushed it! "
            } else if score >= 60 {
                text += "Getting better! "
            } else {
                text += "Practice makes progress! "
            }
            
            text += "Score: \(score)/100 "
            text += getScoreEmoji(for: score)
        }
        
        text += "\n\nPractice your speaking with SpeakUp!"
        text += "\n#SpeakUp #SpeakingPractice"

        return text
    }
    
    // MARK: - Stats Overlay Data
    
    func getStatsOverlayData(for recording: Recording) -> StatsOverlayData? {
        guard let analysis = recording.analysis else { return nil }
        
        return StatsOverlayData(
            score: analysis.speechScore.overall,
            wpm: Int(analysis.wordsPerMinute),
            fillerCount: analysis.totalFillerCount,
            duration: recording.formattedDuration,
            trend: analysis.speechScore.trend
        )
    }
    
    // MARK: - Helpers
    
    private func getScoreEmoji(for score: Int) -> String {
        switch score {
        case 90...100: return "🔥"
        case 80..<90: return "⭐️"
        case 70..<80: return "👍"
        case 60..<70: return "📈"
        default: return "💪"
        }
    }
    
    func getScoreColor(for score: Int) -> UIColor {
        switch score {
        case 0..<40: return .systemRed
        case 40..<60: return .systemOrange
        case 60..<80: return .systemYellow
        case 80...100: return .systemGreen
        default: return .systemGray
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Supporting Types

struct StatsOverlayData {
    let score: Int
    let wpm: Int
    let fillerCount: Int
    let duration: String
    let trend: ScoreTrend
}

// MARK: - Errors

enum ExportError: LocalizedError {
    case noPermission
    case noMediaFile
    case audioNotSupported
    case exportFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Photo library permission is required to save recordings."
        case .noMediaFile:
            return "No media file found for this recording."
        case .audioNotSupported:
            return "Audio files cannot be saved to the Photo Library. Use the Share button instead."
        case .exportFailed(let error):
            return "Export failed: \(error.localizedDescription)"
        }
    }
}
