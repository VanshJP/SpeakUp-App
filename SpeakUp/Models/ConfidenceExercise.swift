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
        case .calming: return AppColors.categorySage
        case .visualization: return AppColors.categoryIndigo
        case .progressive: return AppColors.categoryCopper
        case .affirmation: return AppColors.categoryAmber
        }
    }

    /// What this category is *for* — the one line a section header shows so
    /// someone browsing understands why the grouping exists.
    var purpose: String {
        switch self {
        case .calming: return "Settle nerves in the moment."
        case .visualization: return "Rehearse success before it's real."
        case .progressive: return "Small steps past the fear."
        case .affirmation: return "Reset the inner monologue."
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

    /// Bounds-checked step access. Every seed ships steps, but an empty or
    /// shorter list must degrade to a placeholder instead of trapping.
    func step(safelyAt index: Int) -> String {
        guard steps.indices.contains(index) else { return "" }
        return steps[index]
    }
}
