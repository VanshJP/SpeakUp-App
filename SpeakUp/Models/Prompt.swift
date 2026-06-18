import Foundation
import SwiftData
import SwiftUI

@Model
final class Prompt {
    var id: String = ""
    var text: String = ""
    var category: String = ""
    var difficulty: PromptDifficulty = PromptDifficulty.medium
    var isUserCreated: Bool = false
    @Relationship(inverse: \Recording.prompt)
    var recordings: [Recording]? = []

    init(
        id: String,
        text: String,
        category: String,
        difficulty: PromptDifficulty,
        isUserCreated: Bool = false
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.difficulty = difficulty
        self.isUserCreated = isUserCreated
    }
}

// MARK: - Difficulty Enum

enum PromptDifficulty: String, Codable, CaseIterable {
    case easy
    case medium
    case hard
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var color: Color {
        AppColors.difficultyColor(self)
    }
}

// MARK: - Category Enum

enum PromptCategory: String, CaseIterable {
    case professionalDevelopment = "Professional Development"
    case communicationSkills = "Communication Skills"
    case personalGrowth = "Personal Growth"
    case problemSolving = "Problem Solving"
    case currentEvents = "Current Events & Opinions"
    case quickFire = "Quick Fire"
    case debatePersuasion = "Debate & Persuasion"
    case interviewPrep = "Interview Prep"
    case storytelling = "Storytelling"
    case elevatorPitch = "Elevator Pitch"
    case conversationStarters = "Conversation Starters"
    case describeExplain = "Describe & Explain"

    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .professionalDevelopment: return "briefcase.fill"
        case .communicationSkills: return "bubble.left.and.bubble.right.fill"
        case .personalGrowth: return "leaf.fill"
        case .problemSolving: return "lightbulb.fill"
        case .currentEvents: return "newspaper.fill"
        case .quickFire: return "bolt.fill"
        case .debatePersuasion: return "scale.3d"
        case .interviewPrep: return "person.crop.rectangle.fill"
        case .storytelling: return "book.fill"
        case .elevatorPitch: return "arrow.up.right.circle.fill"
        case .conversationStarters: return "person.2.wave.2.fill"
        case .describeExplain: return "text.justify.left"
        }
    }

    /// Six muted-jewel identity tones. Each category gets a hue distinct
    /// enough that two adjacent cards always read as different, while every
    /// tone stays in the same desaturated band so the grid never feels like
    /// a rainbow.
    var color: Color {
        switch self {
        case .professionalDevelopment, .interviewPrep:
            return AppColors.categoryTeal
        case .communicationSkills, .elevatorPitch:
            return AppColors.categoryIndigo
        case .storytelling, .currentEvents, .describeExplain:
            return AppColors.categoryPlum
        case .quickFire:
            return AppColors.categoryAmber
        case .personalGrowth, .conversationStarters:
            return AppColors.categorySage
        case .problemSolving, .debatePersuasion:
            return AppColors.categoryCopper
        }
    }
}
