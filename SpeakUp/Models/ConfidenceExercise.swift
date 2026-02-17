import Foundation
import SwiftUI

enum ConfidenceCategory: String, CaseIterable, Identifiable {
    case calming
    case visualization
    case progressive
    case affirmation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calming: return "Calming"
        case .visualization: return "Visualization"
        case .progressive: return "Progressive"
        case .affirmation: return "Affirmation"
        }
    }

    var icon: String {
        switch self {
        case .calming: return "leaf"
        case .visualization: return "eye"
        case .progressive: return "figure.walk"
        case .affirmation: return "heart.text.clipboard"
        }
    }

    var color: Color {
        switch self {
        case .calming: return .green
        case .visualization: return .blue
        case .progressive: return .orange
        case .affirmation: return .pink
        }
    }
}

struct ConfidenceExercise: Identifiable {
    let id: String
    let category: ConfidenceCategory
    let title: String
    let description: String
    let steps: [String]
    let durationMinutes: Int
}
