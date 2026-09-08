import SwiftUI

enum AppColors {
    // MARK: - Primary Colors
    
    /// Muted Teal - Primary brand color
    static let primary = Color(red: 0.051, green: 0.518, blue: 0.533) // #0D8488
    
    static let accent = Color(red: 0.392, green: 0.455, blue: 0.545) // #64748B
    
    // MARK: - Semantic Colors

    static let success = Color(red: 0.220, green: 0.800, blue: 0.502) // #38CC80

    static let warning = Color(red: 0.961, green: 0.663, blue: 0.235) // #F5A93C

    static let error = Color(red: 0.961, green: 0.329, blue: 0.290) // #F5544A

    /// Muted steel blue. Informational badges only — never a score band.
    static let info = Color(red: 0.357, green: 0.529, blue: 0.761) // #5B87C2

    // MARK: - Recording Colors

    /// Recording red is its own tone rather than an alias of `error` — it sits
    /// slightly deeper so it stays legible under the pulsing glow instead of
    /// blooming out, and so "live" never reads as "something went wrong".
    static let recording = Color(red: 0.851, green: 0.294, blue: 0.271) // #D94B45

    // MARK: - Score Colors

    static let scoreLow = Color(red: 0.961, green: 0.329, blue: 0.290) // #F5544A

    static let scoreMid = Color(red: 1.000, green: 0.565, blue: 0.212) // #FF9036

    static let scoreGood = Color(red: 0.961, green: 0.773, blue: 0.259) // #F5C542

    static let scoreHigh = Color(red: 0.220, green: 0.800, blue: 0.502) // #38CC80

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

    static func scoreVerdict(for score: Int) -> String {
        switch score {
        case 0..<40: return "Building"
        case 40..<60: return "Developing"
        case 60..<80: return "Solid"
        case 80...100: return "Strong"
        default: return "Unscored"
        }
    }

    static let meterTrack = Color.white.opacity(0.07)

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

    static func difficultyColor(_ difficulty: ReadAloudDifficulty) -> Color {
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
    // 1. Brand tonal tokens (`categoryBrandBright`, `categoryNeutral`,
    //    `categoryNeutralCool`) — used widely as gradient companions and
    //    utility accents on glass surfaces.
    //
    // 2. Muted-jewel identity tones (`categoryTeal`, `categoryIndigo`,
    //    `categoryPlum`, `categoryAmber`, `categorySage`, `categoryCopper`)
    //    — used by `PromptCategory.color`, `SpeakerLevel.color`,
    //    `OnboardingGoal.color`, and the Today quick-action toolbar. All sit
    //    at ~40–55% saturation and ~55–65% brightness so adjacent cards read
    //    as distinct identities without screaming on the dark glass.
    //    Functional `success` / `warning` / `error` stay reserved for state.

    static let categoryBrandBright = Color(red: 0.169, green: 0.659, blue: 0.659)

    static let categoryNeutral = accent

    static let categoryNeutralCool = Color(red: 0.298, green: 0.388, blue: 0.494)

    static let categoryTeal = primary

    static let categoryIndigo = Color(red: 0.349, green: 0.400, blue: 0.651) // #5966A6

    static let categoryPlum = Color(red: 0.549, green: 0.361, blue: 0.518) // #8C5C84

    /// Muted gold. Energy / spark categories. Distinct from semantic warning orange.
    static let categoryAmber = Color(red: 0.749, green: 0.576, blue: 0.318) // #BF9351

    static let categorySage = Color(red: 0.451, green: 0.624, blue: 0.502) // #739F80

    static let categoryCopper = Color(red: 0.749, green: 0.471, blue: 0.400) // #BF7866

    // MARK: - Practice Tool Tones

    static let toolWarmUp = categorySage
    static let toolDrill = categoryAmber
    static let toolReadAloud = categoryBrandBright
    static let toolCalm = categoryPlum

    // MARK: - Subscore Identity Tones
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

    static func subscoreTone(_ index: Int) -> Color {
        subscoreTones[index % subscoreTones.count]
    }

    // MARK: - Contribution Graph Colors

    static func contributionColor(intensity: Double) -> Color {
        if intensity == 0 {
            return Color.white.opacity(0.06)
        }
        return success.opacity(0.28 + (intensity * 0.62))
    }

    // MARK: - Surfaces

    static let surfaceLift = Color.white.opacity(0.03)

    static let cardStroke = Color.white.opacity(0.07)

    // MARK: - Glass Tints

    static let glassTintPrimary = primary.opacity(0.10)
    static let glassTintAccent = GlassAppearance.light.glassTint
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
