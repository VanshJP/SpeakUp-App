import Foundation
import SwiftData
import SwiftUI

@Model
final class Prompt {
    @Attribute(.unique) var id: String
    var text: String
    var category: String
    var difficulty: PromptDifficulty
    var isUserCreated: Bool = false
    
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
        switch self {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
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
        }
    }

    var color: Color {
        switch self {
        case .professionalDevelopment: return .blue
        case .communicationSkills: return .purple
        case .personalGrowth: return .green
        case .problemSolving: return .orange
        case .currentEvents: return .teal
        case .quickFire: return .yellow
        case .debatePersuasion: return .red
        case .interviewPrep: return .indigo
        case .storytelling: return .brown
        case .elevatorPitch: return .mint
        }
    }
}
