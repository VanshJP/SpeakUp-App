import Foundation
import Photos
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

        // Score card image
        if let image = scoreCardImage {
            items.append(image)
        }
        
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
