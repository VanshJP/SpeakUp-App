import Foundation
import SwiftUI

/// Canonical catalog for every practice tool the user can open from Today,
/// Library, or a coach route. One place owns title, outcome, and "when to use"
/// so the toolbar tiles and the Library rows never drift into different stories.
enum PracticeToolKind: String, CaseIterable, Identifiable {
    case warmUp
    case drills
    case readAloud
    case calm
    case learn

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .warmUp: return "Warm-Up"
        case .drills: return "Drills"
        case .readAloud: return "Read Aloud"
        case .calm: return "Calm"
        case .learn: return "Learn"
        }
    }

    var title: String {
        switch self {
        case .warmUp: return "Warm-Ups"
        case .drills: return "Drills"
        case .readAloud: return "Read Aloud"
        case .calm: return "Calm"
        case .learn: return "Learning Path"
        }
    }

    var outcome: String {
        switch self {
        case .warmUp: return "Open the voice before a scored take"
        case .drills: return "Fix one weakness in under a minute"
        case .readAloud: return "Train clarity on a passage — or your own word"
        case .calm: return "Settle nerves so the take starts clean"
        case .learn: return "Follow a week-by-week speaking curriculum"
        }
    }

    var bestFor: String {
        switch self {
        case .warmUp: return "Best before interviews, presentations, or a cold start"
        case .drills: return "Best when a score highlights fillers, pace, or pauses"
        case .readAloud: return "Best when clarity or articulation needs reps"
        case .calm: return "Best right before a high-stakes session"
        case .learn: return "Best when you want structure instead of free practice"
        }
    }

    var icon: String {
        switch self {
        case .warmUp: return "wind"
        case .drills: return "bolt.fill"
        case .readAloud: return "text.book.closed"
        case .calm: return "heart.fill"
        case .learn: return "map.fill"
        }
    }

    var color: Color {
        switch self {
        case .warmUp: return AppColors.toolWarmUp
        case .drills: return AppColors.toolDrill
        case .readAloud: return AppColors.toolReadAloud
        case .calm: return AppColors.toolCalm
        case .learn: return AppColors.primary
        }
    }

    static let todayStripDefaults: [PracticeToolKind] = [.warmUp, .drills, .calm, .readAloud]

    static func recommended(for route: CoachPracticeRoute?) -> PracticeToolKind? {
        guard let route else { return nil }
        switch route {
        case .warmUp: return .warmUp
        case .readAloud: return .readAloud
        case .drill: return .drills
        }
    }
}
