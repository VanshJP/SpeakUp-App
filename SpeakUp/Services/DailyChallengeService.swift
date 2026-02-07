import Foundation

enum DailyChallengeService {
    private static let challengeTemplates: [(String, String, String, DailyChallenge.ChallengeType)] = [
        ("Clean Slate", "Complete a session with zero filler words", "checkmark.seal.fill", .zeroFillers),
        ("Steady Pace", "Speak between 130-170 WPM", "speedometer", .targetWPM(min: 130, max: 170)),
        ("Marathon Session", "Record a 2-minute session", "clock.fill", .longSession(seconds: 120)),
        ("High Scorer", "Score 80 or higher", "star.fill", .highScore(target: 80)),
        ("Perfect Score", "Score 90 or higher", "sparkles", .highScore(target: 90)),
        ("Problem Solver", "Record in Problem Solving category", "lightbulb.fill", .specificCategory("Problem Solving")),
        ("Debater", "Record in Debate & Persuasion category", "scale.3d", .specificCategory("Debate & Persuasion")),
        ("Communicator", "Record in Communication Skills", "bubble.left.and.bubble.right.fill", .specificCategory("Communication Skills")),
        ("Quick Fire", "Complete a Quick Fire prompt", "bolt.fill", .specificCategory("Quick Fire")),
        ("Personal Growth", "Record a Personal Growth prompt", "leaf.fill", .specificCategory("Personal Growth")),
    ]

    /// Generate today's challenge using date-seeded rotation.
    static func todaysChallenge() -> DailyChallenge {
        let today = Calendar.current.startOfDay(for: Date())
        let components = Calendar.current.dateComponents([.year, .month, .day], from: today)
        let seed = (components.year ?? 0) * 366 + (components.month ?? 0) * 31 + (components.day ?? 0)
        let index = seed % challengeTemplates.count

        let template = challengeTemplates[index]
        return DailyChallenge(
            type: template.3,
            title: template.0,
            description: template.1,
            icon: template.2
        )
    }

    /// Check if a recording satisfies a challenge.
    static func evaluate(challenge: DailyChallenge, recording: Recording) -> Bool {
        guard let analysis = recording.analysis else { return false }

        switch challenge.type {
        case .zeroFillers:
            return analysis.totalFillerCount == 0 && analysis.totalWords > 0
        case .targetWPM(let min, let max):
            let wpm = Int(analysis.wordsPerMinute)
            return wpm >= min && wpm <= max
        case .longSession(let seconds):
            return recording.actualDuration >= TimeInterval(seconds)
        case .highScore(let target):
            return analysis.speechScore.overall >= target
        case .specificCategory(let category):
            return recording.prompt?.category == category
        }
    }
}
