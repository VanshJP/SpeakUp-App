import Foundation
import SwiftUI

/// Catalog for review / reflection tools — Compare, Listen back, Goals,
/// Journal. Lives beside `PracticeToolKind` so Library → Tools and History →
/// Progress never invent different names or tints for the same door.
enum ReviewToolKind: String, CaseIterable, Identifiable {
    case compare
    case listenBack
    case goals
    case journal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compare: return "Compare"
        case .listenBack: return "Listen back"
        case .goals: return "Goals"
        case .journal: return "Journal"
        }
    }

    var outcome: String {
        switch self {
        case .compare: return "Stack two takes and see what changed"
        case .listenBack: return "Hear an earlier take next to a recent one"
        case .goals: return "Set a target and track the streak toward it"
        case .journal: return "Export reflections from your sessions"
        }
    }

    var bestFor: String {
        switch self {
        case .compare: return "Best after a few scored takes on the same prompt"
        case .listenBack: return "Best when you want to hear progress, not just read it"
        case .goals: return "Best when practice needs a finish line"
        case .journal: return "Best when you want a written trail of practice"
        }
    }

    var meta: String {
        switch self {
        case .compare: return "Two takes · side by side"
        case .listenBack: return "Audio · before & after"
        case .goals: return "Targets · weekly progress"
        case .journal: return "Export · reflections"
        }
    }

    var icon: String {
        switch self {
        case .compare: return "arrow.left.arrow.right"
        case .listenBack: return "headphones"
        case .goals: return "target"
        case .journal: return "square.and.arrow.up"
        }
    }

    var color: Color {
        switch self {
        case .compare: return AppColors.categoryIndigo
        case .listenBack: return AppColors.categoryPlum
        case .goals: return AppColors.categorySage
        case .journal: return AppColors.categoryAmber
        }
    }
}
