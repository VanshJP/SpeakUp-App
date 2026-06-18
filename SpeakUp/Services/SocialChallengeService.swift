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

    func clearIncoming() {
        incomingChallenge = nil
    }
}
