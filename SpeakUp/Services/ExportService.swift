import Foundation
import UIKit

@Observable
class ExportService {

    // MARK: - Share

    @MainActor
    func shareRecording(_ recording: Recording, scoreCardImage: UIImage? = nil) {
        var items: [Any] = []

        if let image = scoreCardImage {
            items.append(image)
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {

            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            rootVC.present(activityVC, animated: true)
        }
    }
}
