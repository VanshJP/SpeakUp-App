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

    /// Short label for dense chrome (toolbar tiles, tour copy).
    var shortTitle: String {
        switch self {
        case .warmUp: return "Warm-Up"
        case .drills: return "Drills"
        case .readAloud: return "Read Aloud"
        case .calm: return "Calm"
        case .learn: return "Learn"
        }
    }

    /// Full title for list rows and sheet chrome.
    var title: String {
        switch self {
        case .warmUp: return "Warm-Ups"
        case .drills: return "Drills"
        case .readAloud: return "Read Aloud"
        case .calm: return "Calm"
        case .learn: return "Learning Path"
        }
    }

    /// What the user gets — the line that makes the tool worth tapping.
    var outcome: String {
        switch self {
        case .warmUp: return "Loosen the voice so your first sentence isn't the warm-up"
        case .drills: return "Fix one habit in under a minute"
        case .readAloud: return "Train clarity against a script — ours or your own"
        case .calm: return "Settle nerves so the take starts clean"
        case .learn: return "Follow a week-by-week speaking curriculum"
        }
    }

    /// *How* this tool works, in the terms that actually separate the four.
    ///
    /// Without this line they read as four arbitrary buckets — the obvious
    /// question being why a tongue twister is a warm-up while filler
    /// elimination is a drill, and whether Read Aloud is a drill too. It is
    /// the format that differs, not the subject: two of these time you through
    /// guided steps with the mic off, two open the mic and score you. What
    /// each one *improves* is the shared `PracticeFocus` axis, and several of
    /// them improve the same things on purpose.
    var format: String {
        switch self {
        case .warmUp: return "Guided steps · mic off · 20–60s"
        case .drills: return "Mic on · scored · 15–60s"
        case .readAloud: return "Mic on · scored word by word"
        case .calm: return "Guided steps · mic off · 2–5 min"
        case .learn: return "Lessons, then activities"
        }
    }

    /// Which focuses this tool has material for.
    ///
    /// Derived from `itemCount(for:)` rather than from the category enums, so
    /// it cannot disagree with the counts the listings print. The earlier
    /// version asked each catalog's *category* enum which focuses existed,
    /// which would have listed a focus whose only category shipped no
    /// exercises.
    var focuses: [PracticeFocus] {
        PracticeFocus.allCases.filter { itemCount(for: $0) > 0 }
    }

    /// What one item of this tool is called, for "3 drills" / "5 passages".
    var itemNoun: String {
        switch self {
        case .warmUp, .calm: return "exercise"
        case .drills: return "drill"
        case .readAloud: return "passage"
        case .learn: return "lesson"
        }
    }

    /// How much material this tool has for a focus. Counted from the seeds so
    /// a cross-tool listing cannot promise rows that are not there.
    func itemCount(for focus: PracticeFocus) -> Int {
        switch self {
        case .warmUp:
            return DefaultWarmUps.all.filter { $0.category.focus == focus }.count
        case .drills:
            return DrillMode.allCases.filter { $0.focus == focus }.count
        case .readAloud:
            return DefaultReadAloudPassages.all.filter { $0.category.focus == focus }.count
        case .calm:
            return DefaultConfidenceExercises.all.filter { $0.category.focus == focus }.count
        case .learn:
            return 0
        }
    }

    /// The practice tools, in the order the app presents them. `learn` is a
    /// whole tab, not a tool page, so it is excluded.
    static let practiceTools: [PracticeToolKind] = [.warmUp, .drills, .readAloud, .calm]

    /// Every practice tool with material for a focus, in presentation order.
    static func tools(for focus: PracticeFocus) -> [PracticeToolKind] {
        practiceTools.filter { $0.itemCount(for: focus) > 0 }
    }

    /// The focuses the app can actually offer today. The Improve list is built
    /// from this, not from `PracticeFocus.allCases`, so a focus with nothing
    /// behind it cannot render a row that leads to an empty page.
    static var coveredFocuses: [PracticeFocus] {
        PracticeFocus.allCases.filter { !tools(for: $0).isEmpty }
    }

    /// When this tool is the right pick — shown on Library cards and sheet headers.
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

    /// Tools that appear on Today's prep strip by default. The Prompt Wheel
    /// is deliberately absent — it lives in Library → Prompts, where you pick
    /// what to say, not in the strip that gets your voice ready.
    static let todayStripDefaults: [PracticeToolKind] = [.warmUp, .drills, .calm, .readAloud]

    /// Map a coach practice route onto the tool that owns that work.
    static func recommended(for route: CoachPracticeRoute?) -> PracticeToolKind? {
        guard let route else { return nil }
        switch route {
        case .warmUp: return .warmUp
        case .readAloud: return .readAloud
        case .drill: return .drills
        }
    }
}
