import Foundation
import SwiftUI

enum ConfidenceCategory: String, CaseIterable, Identifiable {
    case calming
    case visualization
    case progressive
    case affirmation

    var id: String { rawValue }

    /// Named for the outcome, not the technique. "Calming", "Visualization",
    /// "Progressive" and "Affirmation" described what the exercise *is*; a
    /// browsing user wants to know what it gets them.
    var displayName: String {
        switch self {
        case .calming: return "Settle the body"
        case .visualization: return "Rehearse it going well"
        case .progressive: return "Face it in steps"
        case .affirmation: return "Quiet the inner critic"
        }
    }

    /// The shared axis. Calm covers the two composure outcomes: getting the
    /// body quiet, and getting the story you tell yourself straight.
    var focus: PracticeFocus {
        switch self {
        case .calming, .progressive: return .steadyNerves
        case .visualization, .affirmation: return .mindset
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
