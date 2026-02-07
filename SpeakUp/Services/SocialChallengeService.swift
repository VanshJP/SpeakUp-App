import Foundation
import UIKit

@Observable
class SocialChallengeService {
    var incomingChallenge: SocialChallenge?

    func handleIncomingURL(_ url: URL) -> Bool {
        guard let challenge = SocialChallenge.from(url: url) else { return false }
        incomingChallenge = challenge
        return true
    }

    @MainActor
    func shareChallenge(_ challenge: SocialChallenge) {
        guard let deepLink = challenge.deepLink else { return }

        let text = "\(challenge.challengerName) challenges you! Can you beat their score of \(challenge.challengerScore)/100 on this prompt? \(deepLink.absoluteString)"

        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)

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

    func clearIncoming() {
        incomingChallenge = nil
    }
}
