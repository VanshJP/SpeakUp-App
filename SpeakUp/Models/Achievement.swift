import Foundation
import SwiftData

@Model
final class Achievement {
    @Attribute(.unique) var id: String
    var title: String
    var descriptionText: String
    var icon: String
    var isUnlocked: Bool
    var unlockedDate: Date?

    init(
        id: String,
        title: String,
        descriptionText: String,
        icon: String,
        isUnlocked: Bool = false,
        unlockedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.descriptionText = descriptionText
        self.icon = icon
        self.isUnlocked = isUnlocked
        self.unlockedDate = unlockedDate
    }
}

// MARK: - Achievement Definitions

enum AchievementDefinition: String, CaseIterable {
    case firstRecording = "first_recording"
    case tenSessions = "ten_sessions"
    case fiftySessions = "fifty_sessions"
    case hundredSessions = "hundred_sessions"
    case streak3 = "streak_3"
    case streak7 = "streak_7"
    case streak30 = "streak_30"
    case score80 = "score_80"
    case score95 = "score_95"
    case zeroFillers = "zero_fillers"
    case allCategories = "all_categories"
    case listenBack = "listen_back"

    var title: String {
        switch self {
        case .firstRecording: return "First Steps"
        case .tenSessions: return "Dedicated Speaker"
        case .fiftySessions: return "Half Century"
        case .hundredSessions: return "Centurion"
        case .streak3: return "Getting Started"
        case .streak7: return "Weekly Warrior"
        case .streak30: return "Monthly Master"
        case .score80: return "High Achiever"
        case .score95: return "Near Perfect"
        case .zeroFillers: return "Clean Speech"
        case .allCategories: return "Well Rounded"
        case .listenBack: return "Brave Listener"
        }
    }

    var descriptionText: String {
        switch self {
        case .firstRecording: return "Complete your first recording"
        case .tenSessions: return "Complete 10 practice sessions"
        case .fiftySessions: return "Complete 50 practice sessions"
        case .hundredSessions: return "Complete 100 practice sessions"
        case .streak3: return "Practice 3 days in a row"
        case .streak7: return "Practice 7 days in a row"
        case .streak30: return "Practice 30 days in a row"
        case .score80: return "Score 80 or higher"
        case .score95: return "Score 95 or higher"
        case .zeroFillers: return "Complete a session with zero filler words"
        case .allCategories: return "Record in every prompt category"
        case .listenBack: return "Listen to your own recording for the first time"
        }
    }

    var icon: String {
        switch self {
        case .firstRecording: return "star.fill"
        case .tenSessions: return "flame.fill"
        case .fiftySessions: return "medal.fill"
        case .hundredSessions: return "crown.fill"
        case .streak3: return "bolt.fill"
        case .streak7: return "bolt.shield.fill"
        case .streak30: return "trophy.fill"
        case .score80: return "chart.line.uptrend.xyaxis"
        case .score95: return "sparkles"
        case .zeroFillers: return "checkmark.seal.fill"
        case .allCategories: return "square.grid.3x3.fill"
        case .listenBack: return "headphones"
        }
    }

    func toModel() -> Achievement {
        Achievement(
            id: rawValue,
            title: title,
            descriptionText: descriptionText,
            icon: icon
        )
    }
}
