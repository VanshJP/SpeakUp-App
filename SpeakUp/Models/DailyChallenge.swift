import Foundation

struct DailyChallenge: Identifiable {
    let id = UUID()
    let type: ChallengeType
    let title: String
    let description: String
    let icon: String
    var isCompleted: Bool = false

    enum ChallengeType {
        case zeroFillers
        case targetWPM(min: Int, max: Int)
        case longSession(seconds: Int)
        case highScore(target: Int)
        case specificCategory(String)
    }
}
