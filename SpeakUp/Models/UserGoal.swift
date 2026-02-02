import Foundation
import SwiftData

@Model
final class UserGoal {
    var id: UUID
    var type: GoalType
    var title: String
    var goalDescription: String
    var target: Int
    var current: Int
    var startDate: Date
    var deadline: Date
    var isCompleted: Bool
    var isActive: Bool
    
    init(
        id: UUID = UUID(),
        type: GoalType,
        title: String,
        goalDescription: String,
        target: Int,
        current: Int = 0,
        startDate: Date = Date(),
        deadline: Date,
        isCompleted: Bool = false,
        isActive: Bool = true
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.goalDescription = goalDescription
        self.target = target
        self.current = current
        self.startDate = startDate
        self.deadline = deadline
        self.isCompleted = isCompleted
        self.isActive = isActive
    }
    
    var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1.0)
    }
    
    var progressPercentage: Int {
        Int(progress * 100)
    }
    
    var isExpired: Bool {
        Date() > deadline && !isCompleted
    }
    
    var daysRemaining: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: deadline)
        return max(components.day ?? 0, 0)
    }
}

// MARK: - Goal Type

enum GoalType: String, Codable, CaseIterable {
    case sessionsPerWeek = "sessions_per_week"
    case reduceFiller = "reduce_filler"
    case improveScore = "improve_score"
    case practiceStreak = "practice_streak"
    case totalMinutes = "total_minutes"
    
    var displayName: String {
        switch self {
        case .sessionsPerWeek: return "Weekly Sessions"
        case .reduceFiller: return "Reduce Fillers"
        case .improveScore: return "Improve Score"
        case .practiceStreak: return "Practice Streak"
        case .totalMinutes: return "Total Practice Time"
        }
    }
    
    var iconName: String {
        switch self {
        case .sessionsPerWeek: return "calendar"
        case .reduceFiller: return "text.badge.minus"
        case .improveScore: return "chart.line.uptrend.xyaxis"
        case .practiceStreak: return "flame.fill"
        case .totalMinutes: return "clock.fill"
        }
    }
    
    var unit: String {
        switch self {
        case .sessionsPerWeek: return "sessions"
        case .reduceFiller: return "% reduction"
        case .improveScore: return "points"
        case .practiceStreak: return "days"
        case .totalMinutes: return "minutes"
        }
    }
}

// MARK: - Goal Templates

struct GoalTemplate {
    let type: GoalType
    let title: String
    let description: String
    let target: Int
    let durationDays: Int
    
    static let templates: [GoalTemplate] = [
        GoalTemplate(
            type: .sessionsPerWeek,
            title: "Weekly Practice",
            description: "Complete 5 practice sessions this week",
            target: 5,
            durationDays: 7
        ),
        GoalTemplate(
            type: .practiceStreak,
            title: "7-Day Streak",
            description: "Practice every day for a week",
            target: 7,
            durationDays: 7
        ),
        GoalTemplate(
            type: .improveScore,
            title: "Score Improvement",
            description: "Increase your average score by 10 points",
            target: 10,
            durationDays: 14
        ),
        GoalTemplate(
            type: .reduceFiller,
            title: "Reduce Fillers",
            description: "Reduce filler word usage by 20%",
            target: 20,
            durationDays: 14
        ),
        GoalTemplate(
            type: .totalMinutes,
            title: "Practice Time",
            description: "Accumulate 30 minutes of practice",
            target: 30,
            durationDays: 7
        )
    ]
}
