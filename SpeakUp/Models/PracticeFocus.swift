import Foundation
import SwiftUI

/// The one axis every practice surface is organised by: the thing about your
/// speech that an exercise is trying to move.
///
/// Warm-ups, drills, read-aloud passages and Calm exercises are *formats* - 
/// how long you spend, whether a mic is open, whether you get scored. They are
/// not four unrelated subjects, but the app used to present them as if they
/// were, each carrying its own vocabulary of mechanisms: Breathing, Tongue
/// Twisters, Vocal, Articulation, Calming, Visualization, Progressive,
/// Affirmation. Eight words, none of which say what improves. Nothing
/// explained why a tongue twister was a warm-up while filler elimination was a
/// drill, or why Read Aloud was neither.
///
/// This enum is the shared answer. Pick what you want to improve and every
/// format that trains it lines up underneath. The formats stay - they are real
/// differences in commitment - but they stop being the top-level question.
nonisolated enum PracticeFocus: String, CaseIterable, Identifiable, Sendable {
    case steadyNerves
    case mindset
    case clarity
    case presence
    case pace
    case fillers
    case pauses
    case structure

    var id: String { rawValue }

    /// Outcome-first and in second person. Never the name of a mechanism - 
    /// "Be understood", not "Articulation".
    var title: String {
        switch self {
        case .steadyNerves: return "Steady your nerves"
        case .mindset: return "Walk in believing it"
        case .clarity: return "Be understood"
        case .presence: return "Sound alive"
        case .pace: return "Control your speed"
        case .fillers: return "Cut filler words"
        case .pauses: return "Use silence"
        case .structure: return "Think on your feet"
        }
    }

    /// One or two words for a filter pill, where the full title will not fit.
    var shortTitle: String {
        switch self {
        case .steadyNerves: return "Nerves"
        case .mindset: return "Mindset"
        case .clarity: return "Clarity"
        case .presence: return "Presence"
        case .pace: return "Pace"
        case .fillers: return "Fillers"
        case .pauses: return "Pauses"
        case .structure: return "Structure"
        }
    }

    /// What changes for the person listening to you. This is the line that has
    /// to earn the tap, so it describes a result, not an activity.
    var promise: String {
        switch self {
        case .steadyNerves:
            return "Slow the body down so a shaky voice settles before you start."
        case .mindset:
            return "Arrive expecting it to go well instead of braced for it to go badly."
        case .clarity:
            return "Finish your consonants so words land instead of getting swallowed."
        case .presence:
            return "Warm tone and real pitch movement, instead of a flat line."
        case .pace:
            return "Settle into a rate people can follow, and hold it there."
        case .fillers:
            return "Trade \"um\" and \"like\" for a beat of silence."
        case .pauses:
            return "Stop on purpose, so your best points have room to land."
        case .structure:
            return "Reach for a shape - point, reason, example - under pressure."
        }
    }

    var icon: String {
        switch self {
        case .steadyNerves: return "wind"
        case .mindset: return "brain.head.profile"
        case .clarity: return "character.phonetic"
        case .presence: return "waveform.path.ecg"
        case .pace: return "gauge.with.dots.needle.50percent"
        case .fillers: return "exclamationmark.bubble.fill"
        case .pauses: return "pause.circle.fill"
        case .structure: return "list.bullet.rectangle"
        }
    }

    /// Explicitly main-actor because the enum itself is `nonisolated` - it has
    /// to be, so `allCases` stays reachable from `ReadAloudCategory`, which is
    /// nonisolated too (gotcha §1). `AppColors` is default-isolated, and every
    /// caller of this is a view body, so pinning just this member keeps both
    /// sides legal without loosening the type.
    @MainActor
    var color: Color {
        switch self {
        case .steadyNerves: return AppColors.categorySage
        case .mindset: return AppColors.categoryPlum
        case .clarity: return AppColors.categoryBrandBright
        case .presence: return AppColors.categoryTeal
        case .pace: return AppColors.categoryIndigo
        case .fillers: return AppColors.categoryAmber
        case .pauses: return AppColors.categoryNeutralCool
        case .structure: return AppColors.categoryCopper
        }
    }
}
