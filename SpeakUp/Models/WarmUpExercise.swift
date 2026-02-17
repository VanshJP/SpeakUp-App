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
        case .breathing: return .cyan
        case .tonguetwister: return .orange
        case .vocal: return .purple
        case .articulation: return .green
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
