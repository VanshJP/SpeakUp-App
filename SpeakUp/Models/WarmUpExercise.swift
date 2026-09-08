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

    /// What this category is *for* — the one line a section header shows so
    /// someone browsing understands why the grouping exists.
    var purpose: String {
        switch self {
        case .breathing: return "Steady your nerves and breath support."
        case .tonguetwister: return "Loosen up articulation, then add speed."
        case .vocal: return "Wake up resonance and pitch range."
        case .articulation: return "Crisper consonants, looser jaw."
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
