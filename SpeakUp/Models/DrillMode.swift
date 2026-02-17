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

    var description: String {
        switch self {
        case .fillerElimination: return "15-second bursts — goal: zero fillers"
        case .paceControl: return "60 seconds — match the target WPM"
        case .pausePractice: return "45 seconds — pause deliberately at markers"
        case .impromptuSprint: return "30 seconds — random prompt, no prep"
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
        case .fillerElimination: return .orange
        case .paceControl: return .blue
        case .pausePractice: return .purple
        case .impromptuSprint: return .red
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
}

struct DrillResult: Identifiable {
    let id = UUID()
    let mode: DrillMode
    let score: Int // 0-100
    let date: Date
    let details: String
    let passed: Bool
}
