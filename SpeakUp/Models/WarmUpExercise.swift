import Foundation
import SwiftUI

enum WarmUpCategory: String, CaseIterable, Identifiable {
    case breathing
    case tonguetwister
    case vocal
    case articulation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breathing: return "Breathing"
        case .tonguetwister: return "Tongue Twisters"
        case .vocal: return "Vocal"
        case .articulation: return "Articulation"
        }
    }

    var icon: String {
        switch self {
        case .breathing: return "wind"
        case .tonguetwister: return "mouth"
        case .vocal: return "music.mic"
        case .articulation: return "character.phonetic"
        }
    }

    var color: Color {
        switch self {
        case .breathing: return AppColors.categoryBrandBright
        case .tonguetwister: return AppColors.categoryCopper
        case .vocal: return AppColors.categoryPlum
        case .articulation: return AppColors.categorySage
        }
    }

    /// The shared axis. Warm-ups are a composure, clarity and presence tool;
    /// the category stays as the *kind* of exercise, shown on the row, while
    /// the focus is what the page groups by.
    var focus: PracticeFocus {
        switch self {
        case .breathing: return .steadyNerves
        case .tonguetwister, .articulation: return .clarity
        case .vocal: return .presence
        }
    }
}

enum StepAnimation: String, Codable {
    case expand
    case hold
    case contract
}

struct ExerciseStep: Identifiable, Codable {
    var id: String { label }
    let label: String
    let durationSeconds: Int
    let animation: StepAnimation
}

struct WarmUpExercise: Identifiable {
    let id: String
    let category: WarmUpCategory
    let title: String
    let instructions: String
    let steps: [ExerciseStep]
    let durationSeconds: Int
}
