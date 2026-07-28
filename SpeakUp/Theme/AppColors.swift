import SwiftUI

enum AppColors {
    // MARK: - Primary Colors
    
    /// Muted Teal - Primary brand color
    static let primary = Color(red: 0.051, green: 0.518, blue: 0.533) // #0D8488
    
    /// Warm Gray - Accent color
    static let accent = Color(red: 0.392, green: 0.455, blue: 0.545) // #64748B
    
    // MARK: - Semantic Colors
    //
    // Hand-picked tones, still not system colors, but pitched bright. The deep
    // navy canvas swallows anything under ~70% saturation, so state has to
    // carry real chroma to register at pill and arrow size. These sit one
    // register above the category identity tones below on purpose: state
    // should out-read identity, never blend into it.

    /// Vivid emerald. Positive state, completion, on-target metrics.
    /// Matches `scoreHigh` so a passing score and a success pill agree.
    static let success = Color(red: 0.220, green: 0.800, blue: 0.502) // #38CC80

    /// Bright amber. Caution, fillers, mid-range state. Warmer and far hotter
    /// than `categoryAmber` so state reads as state, not category identity.
    static let warning = Color(red: 0.961, green: 0.663, blue: 0.235) // #F5A93C

    /// Vivid coral red. Failure, destructive actions, low scores.
    /// Matches `scoreLow` for the same reason `success` matches `scoreHigh`.
    static let error = Color(red: 0.961, green: 0.329, blue: 0.290) // #F5544A

    /// Muted steel blue. Informational badges only — never a score band.
    static let info = Color(red: 0.357, green: 0.529, blue: 0.761) // #5B87C2

    // MARK: - Recording Colors

    /// Recording red is its own tone rather than an alias of `error` — it sits
    /// slightly deeper so it stays legible under the pulsing glow instead of
    /// blooming out, and so "live" never reads as "something went wrong".
    static let recording = Color(red: 0.851, green: 0.294, blue: 0.271) // #D94B45
    static let recordingPulse = recording.opacity(0.30)

    // MARK: - Score Colors
    //
    // The ramp is the loudest thing in the app and should be. A score is a
    // verdict, and a verdict the eye has to squint at is a failed verdict —
    // muted bands made every band look the same at ring and chip size. Four
    // vivid steps that read as a traffic light on first glance: coral →
    // orange → gold → emerald.
    //
    // Still hand-picked, not `Color.red` / `.orange` / `.yellow` / `.green`.
    // The system hues are tuned for light UI and drift muddy over the navy
    // canvas. In particular `scoreGood` is a warm gold, not pure yellow —
    // pure yellow is the one hue that cannot hold contrast under white text
    // on a dark surface, and 60–79 is the band most often labelled.

    /// 0–39. Vivid coral red.
    static let scoreLow = Color(red: 0.961, green: 0.329, blue: 0.290) // #F5544A

    /// 40–59. Bright orange.
    static let scoreMid = Color(red: 1.000, green: 0.565, blue: 0.212) // #FF9036

    /// 60–79. Bright gold — reads as yellow without being `Color.yellow`.
    static let scoreGood = Color(red: 0.961, green: 0.773, blue: 0.259) // #F5C542

    /// 80–100. Vivid emerald.
    static let scoreHigh = Color(red: 0.220, green: 0.800, blue: 0.502) // #38CC80

    /// Neutral fill for an absent or not-yet-computed score.
    static let scoreEmpty = Color(red: 0.416, green: 0.435, blue: 0.463) // #6A6F76

    static func scoreColor(for score: Int) -> Color {
        switch score {
        case 0..<40:
            return scoreLow
        case 40..<60:
            return scoreMid
        case 60..<80:
            return scoreGood
        case 80...100:
            return scoreHigh
        default:
            return scoreEmpty
        }
    }

    /// One-word verdict paired with `scoreColor`. Keeps the wording for a
    /// given band identical everywhere a score is presented.
    static func scoreVerdict(for score: Int) -> String {
        switch score {
        case 0..<40: return "Needs work"
        case 40..<60: return "Developing"
        case 60..<80: return "Solid"
        case 80...100: return "Strong"
        default: return "Unscored"
        }
    }

    /// Recessed track behind any ring, meter, or progress capsule. Previously
    /// hardcoded as `Color.white.opacity(0.07)` in a dozen places.
    static let meterTrack = Color.white.opacity(0.07)

    static func scoreGradient(for score: Int) -> LinearGradient {
        let color = scoreColor(for: score)
        return LinearGradient(
            colors: [color.opacity(0.8), color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Difficulty Colors

    static func difficultyColor(_ difficulty: PromptDifficulty) -> Color {
        switch difficulty {
        case .easy:
            return success
        case .medium:
            return warning
        case .hard:
            return error
        }
    }

    // MARK: - Category Tones
    //
    // Two layers:
    //
    // 1. Brand tonal tokens (`categoryBrand`, `categoryBrandBright`,
    //    `categoryNeutral`, `categoryNeutralCool`) — used widely as gradient
    //    companions and utility accents on glass surfaces.
    //
    // 2. Muted-jewel identity tones (`categoryTeal`, `categoryIndigo`,
    //    `categoryPlum`, `categoryAmber`, `categorySage`, `categoryCopper`)
    //    — used by `PromptCategory.color`, `SpeakerLevel.color`,
    //    `OnboardingGoal.color`, and the Today quick-action toolbar. All sit
    //    at ~40–55% saturation and ~55–65% brightness so adjacent cards read
    //    as distinct identities without screaming on the dark glass.
    //    Functional `success` / `warning` / `error` stay reserved for state.

    /// Brand teal at full saturation. Identity / primary category bucket.
    static let categoryBrand = primary

    /// Brighter teal-leaning tone — used widely as a gradient companion to `primary`.
    static let categoryBrandBright = Color(red: 0.169, green: 0.659, blue: 0.659)

    /// Muted accent gray for reflective utility surfaces (callouts, takeaways).
    static let categoryNeutral = accent

    /// Cooler accent for analytical utility surfaces.
    static let categoryNeutralCool = Color(red: 0.298, green: 0.388, blue: 0.494)

    /// Brand teal as an identity tone (alias of `categoryBrand`).
    static let categoryTeal = primary

    /// Muted blue-violet. Interpersonal / decision categories.
    static let categoryIndigo = Color(red: 0.349, green: 0.400, blue: 0.651) // #5966A6

    /// Muted wine-purple. Narrative / introspective categories.
    static let categoryPlum = Color(red: 0.549, green: 0.361, blue: 0.518) // #8C5C84

    /// Muted gold. Energy / spark categories. Distinct from semantic warning orange.
    static let categoryAmber = Color(red: 0.749, green: 0.576, blue: 0.318) // #BF9351

    /// Muted green-gray. Growth / calm categories. Distinct from semantic success green.
    static let categorySage = Color(red: 0.451, green: 0.624, blue: 0.502) // #739F80

    /// Muted terracotta. Heat / analytical-warmth categories. Distinct from semantic error red.
    static let categoryCopper = Color(red: 0.749, green: 0.471, blue: 0.400) // #BF7866

    // MARK: - Practice Tool Tones
    //
    // Identity tone per practice tool, defined once because the Today
    // quick-action strip and the Library tools list render the same concepts
    // and had drifted to different hues. All drawn from the muted jewel set
    // above — a row of four saturated system colors read as a toy.

    static let toolWarmUp = categorySage
    static let toolDrill = categoryAmber
    static let toolReadAloud = categoryBrandBright
    static let toolCalm = categoryPlum
    static let toolWheel = categoryIndigo

    // MARK: - Subscore Identity Tones
    //
    // Used where subscores need to be told apart as *categories* (weight
    // editor, legends) rather than judged as values. Judgement is
    // `scoreColor(for:)`; these never encode good or bad.
    static let subscoreTones: [Color] = [
        categoryTeal,
        categoryIndigo,
        categoryAmber,
        categoryPlum,
        categorySage,
        categoryCopper,
        categoryBrandBright,
        categoryNeutralCool,
        accent
    ]

    /// Stable tone for the subscore at `index`, wrapping if the list grows.
    static func subscoreTone(_ index: Int) -> Color {
        subscoreTones[index % subscoreTones.count]
    }

    // MARK: - Contribution Graph Colors

    static func contributionColor(intensity: Double) -> Color {
        if intensity == 0 {
            // Matches the meter track rather than a gray wash, so empty days
            // recede into the canvas instead of reading as their own tone.
            return Color.white.opacity(0.06)
        }
        return success.opacity(0.28 + (intensity * 0.62))
    }

    // MARK: - Surfaces

    /// Faint lift applied over the material fill of every card so surfaces
    /// read a step lighter than the navy canvas.
    static let surfaceLift = Color.white.opacity(0.03)

    /// Uniform hairline stroke around cards and controls.
    static let cardStroke = Color.white.opacity(0.07)

    // MARK: - Glass Tints

    static let glassTintPrimary = primary.opacity(0.10)
    static let glassTintAccent = Color.white.opacity(0.05)
    static let glassTintWarning = warning.opacity(0.10)
    static let glassTintError = error.opacity(0.10)
    static let glassTintSuccess = success.opacity(0.10)
}

// MARK: - Color Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
