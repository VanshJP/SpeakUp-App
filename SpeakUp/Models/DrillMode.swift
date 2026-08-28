import Foundation
import SwiftUI

enum DrillMode: String, CaseIterable, Identifiable {
    case fillerElimination
    case paceControl
    case pausePractice
    case impromptuSprint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fillerElimination: return "Filler Elimination"
        case .paceControl: return "Pace Control"
        case .pausePractice: return "Pause Practice"
        case .impromptuSprint: return "Impromptu Sprint"
        }
    }

    /// What this drill trains — shown on the selection card.
    var outcome: String {
        switch self {
        case .fillerElimination: return "Cut ums and likes in short bursts"
        case .paceControl: return "Match a target speaking rate"
        case .pausePractice: return "Place deliberate silence on purpose"
        case .impromptuSprint: return "Think and speak with zero prep"
        }
    }

    /// Duration + mechanic — the cost line under the outcome.
    var description: String {
        switch self {
        case .fillerElimination: return "\(defaultDurationSeconds)s · goal: zero fillers"
        case .paceControl: return "\(defaultDurationSeconds)s · match target WPM"
        case .pausePractice: return "\(defaultDurationSeconds)s · pause at markers"
        case .impromptuSprint: return "\(defaultDurationSeconds)s · random prompt"
        }
    }

    var icon: String {
        switch self {
        case .fillerElimination: return "xmark.circle"
        case .paceControl: return "speedometer"
        case .pausePractice: return "pause.circle"
        case .impromptuSprint: return "bolt.circle"
        }
    }

    var color: Color {
        switch self {
        case .fillerElimination: return AppColors.categoryAmber
        case .paceControl: return AppColors.categoryIndigo
        case .pausePractice: return AppColors.categoryPlum
        case .impromptuSprint: return AppColors.categoryCopper
        }
    }

    var defaultDurationSeconds: Int {
        switch self {
        case .fillerElimination: return 15
        case .paceControl: return 60
        case .pausePractice: return 45
        case .impromptuSprint: return 30
        }
    }

    /// What the session actually shows while you run it — the concrete thing
    /// a tile promises so the format is understood before committing.
    var liveFeedback: String {
        switch self {
        case .fillerElimination: return "Live filler counter"
        case .paceControl: return "Live WPM vs. target band"
        case .pausePractice: return "Guided pause markers"
        case .impromptuSprint: return "Surprise topic on the clock"
        }
    }
}

struct DrillResult: Identifiable {
    let id = UUID()
    let mode: DrillMode
    let score: Int // 0-100
    let date: Date
    let details: String
    let passed: Bool
}
