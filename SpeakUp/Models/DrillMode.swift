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

    /// What this drill trains - shown on the selection card.
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

    /// What this drill is filed under app-wide. Drills already spoke in
    /// outcomes; this is the same idea promoted to a vocabulary that warm-ups,
    /// Read Aloud and Calm share, so one question - what do you want to
    /// improve - reaches every format.
    var focus: PracticeFocus {
        switch self {
        case .fillerElimination: return .fillers
        case .paceControl: return .pace
        case .pausePractice: return .pauses
        case .impromptuSprint: return .structure
        case .vocalVariety: return .presence
        case .emphasis: return .presence
        case .qaSprint: return .structure
        }
    }

    /// Duration + mechanic - the cost line under the outcome.
    var description: String {
        let seconds = currentDurationSeconds
        switch self {
        case .fillerElimination: return "\(seconds)s · goal: zero fillers"
        case .paceControl: return "\(seconds)s · hold your target pace"
        case .pausePractice: return "\(seconds)s · pause at markers"
        case .impromptuSprint: return "\(seconds)s · PREP beats + topic"
        case .vocalVariety: return "\(seconds)s · pitch range score"
        case .emphasis: return "\(seconds)s · stress the marked word"
        case .qaSprint: return "\(seconds)s · question → answer"
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

    /// Longer rounds, unlocked one clean run at a time.
    ///
    /// Filler Elimination starts at 15 seconds, which is enough to learn the
    /// drill and too short to prove anything once you have: the habit-reversal
    /// studies that cut filled pauses did it over minutes of speech, not one
    /// breath. A drill with a single rung never changes length.
    var durationLadder: [Int] {
        switch self {
        case .fillerElimination: return [15, 30, 45, 60]
        default: return [defaultDurationSeconds]
        }
    }

    func durationSeconds(atLevel level: Int) -> Int {
        let ladder = durationLadder
        return ladder[min(max(0, level), ladder.count - 1)]
    }

    /// The round this drill runs at right now: its default, or the rung of
    /// `durationLadder` the user has earned.
    var currentDurationSeconds: Int {
        durationSeconds(atLevel: DrillProgressStore.record(for: self)?.level ?? 0)
    }

    /// The technique to use while the clock runs, shown under the topic. Nil
    /// where the drill's own display already says what to do.
    ///
    /// Filler Elimination's line is the competing response from habit-reversal
    /// training - notice the filler coming and do something incompatible with
    /// it instead - which is the part of that method that did the work.
    var coachingCue: String? {
        switch self {
        case .fillerElimination: return "Feel an “um” coming? Close your lips and pause instead."
        case .paceControl: return "Running fast? Finish the sentence, then take a full breath."
        case .pausePractice: return "When the marker lights, stop completely and let the silence land."
        case .impromptuSprint, .vocalVariety, .emphasis, .qaSprint: return nil
        }
    }

    /// What the session actually shows while you run it - the concrete thing
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

    /// Scores from the recording's pitch contour after stop - not from live ASR.
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
    /// Progress worth calling out: a new personal best, a longer round
    /// unlocked. Nil on an ordinary run.
    var milestone: String?
}
