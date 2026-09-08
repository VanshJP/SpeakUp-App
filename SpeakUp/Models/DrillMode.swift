import Foundation
import SwiftUI

enum DrillMode: String, CaseIterable, Identifiable {
    case fillerElimination
    case paceControl
    case pausePractice
    case impromptuSprint
    case vocalVariety
    case emphasis
    case qaSprint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fillerElimination: return "Filler Elimination"
        case .paceControl: return "Pace Control"
        case .pausePractice: return "Pause Practice"
        case .impromptuSprint: return "Impromptu Sprint"
        case .vocalVariety: return "Vocal Variety"
        case .emphasis: return "Emphasis"
        case .qaSprint: return "Q&A Sprint"
        }
    }

    /// What this drill trains — shown on the selection card.
    var outcome: String {
        switch self {
        case .fillerElimination: return "Cut ums and likes in short bursts"
        case .paceControl: return "Match a target speaking rate"
        case .pausePractice: return "Place deliberate silence on purpose"
        case .impromptuSprint: return "Think and speak with PREP cues"
        case .vocalVariety: return "Widen pitch range on a fixed line"
        case .emphasis: return "Hit one word harder per sentence"
        case .qaSprint: return "Answer a question cleanly on the clock"
        }
    }

    /// Duration + mechanic — the cost line under the outcome.
    var description: String {
        switch self {
        case .fillerElimination: return "\(defaultDurationSeconds)s · goal: zero fillers"
        case .paceControl: return "\(defaultDurationSeconds)s · match target WPM"
        case .pausePractice: return "\(defaultDurationSeconds)s · pause at markers"
        case .impromptuSprint: return "\(defaultDurationSeconds)s · PREP beats + topic"
        case .vocalVariety: return "\(defaultDurationSeconds)s · pitch range score"
        case .emphasis: return "\(defaultDurationSeconds)s · stress the marked word"
        case .qaSprint: return "\(defaultDurationSeconds)s · question → answer"
        }
    }

    var icon: String {
        switch self {
        case .fillerElimination: return "xmark.circle"
        case .paceControl: return "speedometer"
        case .pausePractice: return "pause.circle"
        case .impromptuSprint: return "bolt.circle"
        case .vocalVariety: return "waveform.path.ecg"
        case .emphasis: return "textformat.size"
        case .qaSprint: return "questionmark.bubble"
        }
    }

    var color: Color {
        switch self {
        case .fillerElimination: return AppColors.categoryAmber
        case .paceControl: return AppColors.categoryIndigo
        case .pausePractice: return AppColors.categoryPlum
        case .impromptuSprint: return AppColors.categoryCopper
        case .vocalVariety: return AppColors.categoryTeal
        case .emphasis: return AppColors.categorySage
        case .qaSprint: return AppColors.categoryBrandBright
        }
    }

    var defaultDurationSeconds: Int {
        switch self {
        case .fillerElimination: return 15
        case .paceControl: return 60
        case .pausePractice: return 45
        case .impromptuSprint: return 30
        case .vocalVariety: return 45
        case .emphasis: return 30
        case .qaSprint: return 45
        }
    }

    /// What the session actually shows while you run it — the concrete thing
    /// a tile promises so the format is understood before committing.
    var liveFeedback: String {
        switch self {
        case .fillerElimination: return "Live filler counter"
        case .paceControl: return "Live WPM vs. target band"
        case .pausePractice: return "Guided pause markers"
        case .impromptuSprint: return "PREP beats on the clock"
        case .vocalVariety: return "Pitch range after the take"
        case .emphasis: return "Marked word + energy swing"
        case .qaSprint: return "Question with CLEAR beats"
        }
    }

    /// Prep countdown should reveal the prompt before the clock starts.
    var preparesPromptUpFront: Bool {
        switch self {
        case .impromptuSprint, .vocalVariety, .emphasis, .qaSprint: return true
        case .fillerElimination, .paceControl, .pausePractice: return false
        }
    }

    /// Scores from the recording's pitch contour after stop — not from live ASR.
    var usesPitchAnalysis: Bool {
        self == .vocalVariety
    }

    /// Mic metering alone is enough to run (no speech-recognition requirement).
    var allowsMeteringOnly: Bool {
        switch self {
        case .pausePractice, .vocalVariety: return true
        default: return false
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
