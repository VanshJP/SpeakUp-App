import Foundation
import SwiftUI

struct FrameworkSection: Identifiable, Codable {
    var id: String { abbreviation }
    let title: String
    let abbreviation: String
    let hint: String
    let suggestedDurationRatio: Double
}

enum SpeechFramework: String, CaseIterable, Codable, Identifiable {
    case prep
    case star
    case problemSolution

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prep: return "PREP"
        case .star: return "STAR"
        case .problemSolution: return "Problem-Solution"
        }
    }

    var description: String {
        switch self {
        case .prep: return "Point, Reason, Example, Point"
        case .star: return "Situation, Task, Action, Result"
        case .problemSolution: return "Problem, Solution, Benefit"
        }
    }

    var icon: String {
        switch self {
        case .prep: return "list.bullet.rectangle"
        case .star: return "star.circle"
        case .problemSolution: return "lightbulb.circle"
        }
    }

    var color: Color {
        switch self {
        case .prep: return .blue
        case .star: return .orange
        case .problemSolution: return .green
        }
    }

    var sections: [FrameworkSection] {
        switch self {
        case .prep:
            return [
                FrameworkSection(title: "Point", abbreviation: "P", hint: "State your main point clearly", suggestedDurationRatio: 0.2),
                FrameworkSection(title: "Reason", abbreviation: "R", hint: "Explain why this matters", suggestedDurationRatio: 0.25),
                FrameworkSection(title: "Example", abbreviation: "E", hint: "Give a specific example", suggestedDurationRatio: 0.35),
                FrameworkSection(title: "Point", abbreviation: "P", hint: "Restate your point to close", suggestedDurationRatio: 0.2)
            ]
        case .star:
            return [
                FrameworkSection(title: "Situation", abbreviation: "S", hint: "Set the scene and context", suggestedDurationRatio: 0.2),
                FrameworkSection(title: "Task", abbreviation: "T", hint: "Describe your role or challenge", suggestedDurationRatio: 0.2),
                FrameworkSection(title: "Action", abbreviation: "A", hint: "Explain what you did", suggestedDurationRatio: 0.35),
                FrameworkSection(title: "Result", abbreviation: "R", hint: "Share the outcome", suggestedDurationRatio: 0.25)
            ]
        case .problemSolution:
            return [
                FrameworkSection(title: "Problem", abbreviation: "P", hint: "Describe the problem clearly", suggestedDurationRatio: 0.3),
                FrameworkSection(title: "Solution", abbreviation: "S", hint: "Present your solution", suggestedDurationRatio: 0.4),
                FrameworkSection(title: "Benefit", abbreviation: "B", hint: "Explain the positive impact", suggestedDurationRatio: 0.3)
            ]
        }
    }
}
