import SwiftUI

/// Motif drawn by `LessonGlyphView`. Map: `LessonIdentity.forLesson(id:)`.
enum LessonMotif: String, CaseIterable {
    case baseline, fillers, pace, score
    case breath, cleanSpeech, warmUp
    case prep, star, pause, sentences
    case nerves, impromptu, stamina, celebrate
    case vocal, volume, articulation, emphasis
    case ruleOfThree, problemSolution, whatSoWhat, bridge
    case storyArc, hook, emotion, closing
    case qa, elevator, talk, graduate
    case opener, keepGoing, room, conversation
}

/// Per-lesson glyph + accent. Keep `catalog` in sync with `DefaultCurriculum`.
struct LessonIdentity {
    let motif: LessonMotif
    let accent: Color

    static func forLesson(id: String) -> LessonIdentity {
        catalog[id] ?? LessonIdentity(motif: .baseline, accent: AppColors.primary)
    }

    static func forPhase(week: Int) -> Color {
        switch week {
        case 1: return AppColors.categoryTeal
        case 2: return AppColors.categorySage
        case 3: return AppColors.categoryIndigo
        case 4: return AppColors.categoryPlum
        case 5: return AppColors.categoryAmber
        case 6: return AppColors.categoryCopper
        case 7: return AppColors.categoryBrandBright
        case 8: return AppColors.categoryNeutralCool
        default: return AppColors.categoryPlum
        }
    }

    /// Seeded lesson ids → identity. `@testable` tests assert coverage vs `DefaultCurriculum`.
    static let catalog: [String: LessonIdentity] = [
        "w1_l1": .init(motif: .baseline, accent: AppColors.categoryTeal),
        "w1_l2": .init(motif: .fillers, accent: AppColors.categoryAmber),
        "w1_l3": .init(motif: .pace, accent: AppColors.categoryIndigo),
        "w1_l4": .init(motif: .score, accent: AppColors.categoryBrandBright),

        "w2_l1": .init(motif: .breath, accent: AppColors.categorySage),
        "w2_l2": .init(motif: .cleanSpeech, accent: AppColors.categoryAmber),
        "w2_l3": .init(motif: .pace, accent: AppColors.categoryTeal),
        "w2_l4": .init(motif: .warmUp, accent: AppColors.categoryCopper),

        "w3_l1": .init(motif: .prep, accent: AppColors.categoryIndigo),
        "w3_l2": .init(motif: .star, accent: AppColors.categoryAmber),
        "w3_l3": .init(motif: .pause, accent: AppColors.categoryNeutralCool),
        "w3_l4": .init(motif: .sentences, accent: AppColors.categoryTeal),

        "w4_l1": .init(motif: .nerves, accent: AppColors.categoryPlum),
        "w4_l2": .init(motif: .impromptu, accent: AppColors.categoryCopper),
        "w4_l3": .init(motif: .stamina, accent: AppColors.categorySage),
        "w4_l4": .init(motif: .celebrate, accent: AppColors.scoreGood),

        "w5_l1": .init(motif: .vocal, accent: AppColors.categoryBrandBright),
        "w5_l2": .init(motif: .volume, accent: AppColors.categoryAmber),
        "w5_l3": .init(motif: .articulation, accent: AppColors.categoryTeal),
        "w5_l4": .init(motif: .emphasis, accent: AppColors.categoryIndigo),

        "w6_l1": .init(motif: .ruleOfThree, accent: AppColors.categoryCopper),
        "w6_l2": .init(motif: .problemSolution, accent: AppColors.categoryIndigo),
        "w6_l3": .init(motif: .whatSoWhat, accent: AppColors.categorySage),
        "w6_l4": .init(motif: .bridge, accent: AppColors.categoryBrandBright),

        "w7_l1": .init(motif: .storyArc, accent: AppColors.categoryPlum),
        "w7_l2": .init(motif: .hook, accent: AppColors.categoryAmber),
        "w7_l3": .init(motif: .emotion, accent: AppColors.categoryPlum),
        "w7_l4": .init(motif: .closing, accent: AppColors.categoryTeal),

        "w8_l1": .init(motif: .qa, accent: AppColors.categoryIndigo),
        "w8_l2": .init(motif: .elevator, accent: AppColors.categoryCopper),
        "w8_l3": .init(motif: .talk, accent: AppColors.categoryBrandBright),
        "w8_l4": .init(motif: .graduate, accent: AppColors.scoreGood),

        "w9_l1": .init(motif: .opener, accent: AppColors.categorySage),
        "w9_l2": .init(motif: .keepGoing, accent: AppColors.categoryTeal),
        "w9_l3": .init(motif: .room, accent: AppColors.categoryIndigo),
        "w9_l4": .init(motif: .conversation, accent: AppColors.categoryPlum),
    ]
}
