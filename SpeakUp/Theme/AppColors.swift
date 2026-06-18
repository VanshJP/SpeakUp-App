import SwiftUI

enum AppColors {
    // MARK: - Primary Colors
    
    /// Muted Teal - Primary brand color
    static let primary = Color(red: 0.051, green: 0.518, blue: 0.533) // #0D8488
    
    /// Warm Gray - Accent color
    static let accent = Color(red: 0.392, green: 0.455, blue: 0.545) // #64748B
    
    // MARK: - Semantic Colors
    
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue
    
    // MARK: - Recording Colors
    
    static let recording = Color.red
    static let recordingPulse = Color.red.opacity(0.3)
    
    // MARK: - Score Colors

    static func scoreColor(for score: Int) -> Color {
        switch score {
        case 0..<40:
            return error
        case 40..<60:
            return warning
        case 60..<80:
            return Color.yellow
        case 80...100:
            return success
        default:
            return Color.gray
        }
    }

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

    // MARK: - Contribution Graph Colors

    static func contributionColor(intensity: Double) -> Color {
        if intensity == 0 {
            return Color.gray.opacity(0.2)
        }
        return success.opacity(0.3 + (intensity * 0.7))
    }

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
