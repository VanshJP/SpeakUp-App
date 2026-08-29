import Foundation
import SwiftData

@Model
final class Achievement {
    var id: String = ""
    var title: String = ""
    var descriptionText: String = ""
    var icon: String = ""
    var isUnlocked: Bool = false
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
    case wordWorkout = "word_workout"

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
        case .wordWorkout: return "Word Workout"
        }
    }

    var descriptionText: String {
        switch self {
        case .firstRecording: return "Your first recording"
        case .tenSessions: return "10 practice sessions"
        case .fiftySessions: return "50 practice sessions"
        case .hundredSessions: return "100 practice sessions"
        case .streak3: return "3 practice days in a row"
        case .streak7: return "7 practice days in a row"
        case .streak30: return "30 practice days in a row"
        case .score80: return "A score of 80 or higher"
        case .score95: return "A score of 95 or higher"
        case .zeroFillers: return "A session with zero filler words"
        case .allCategories: return "A recording in every prompt category"
        case .listenBack: return "Listening back for the first time"
        case .wordWorkout: return "Three vocabulary words in one session"
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
        case .wordWorkout: return "character.book.closed.fill"
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

    func refreshDisplay(on achievement: Achievement) {
        achievement.title = title
        achievement.descriptionText = descriptionText
        achievement.icon = icon
    }
}
