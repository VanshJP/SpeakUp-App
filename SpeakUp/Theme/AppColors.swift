import SwiftUI

enum AppColors {
    // MARK: - Primary Colors
    
    /// Muted Teal - Primary brand color
    static let primary = Color("Primary", bundle: nil)
    static let primaryFallback = Color(red: 0.051, green: 0.518, blue: 0.533) // #0D8488
    
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
            return .red
        case 40..<60:
            return .orange
        case 60..<80:
            return .yellow
        case 80...100:
            return .green
        default:
            return .gray
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
            return .green
        case .medium:
            return .orange
        case .hard:
            return .red
        }
    }
    
    // MARK: - Category Colors
    
    static func categoryColor(_ category: String) -> Color {
        switch category {
        case "Professional Development":
            return .blue
        case "Communication Skills":
            return .purple
        case "Personal Growth":
            return .green
        case "Problem Solving":
            return .orange
        case "Current Events & Opinions":
            return .teal
        case "Quick Fire":
            return .yellow
        case "Debate & Persuasion":
            return .red
        default:
            return .gray
        }
    }
    
    // MARK: - Wheel Segment Colors
    
    static let wheelSegmentColors: [Color] = [
        .blue,      // Professional Development
        .purple,    // Communication Skills
        .green,     // Personal Growth
        .orange,    // Problem Solving
        .teal,      // Current Events
        .yellow,    // Quick Fire
        .red,       // Debate & Persuasion
        .pink       // Extra
    ]
    
    // MARK: - Contribution Graph Colors
    
    static func contributionColor(intensity: Double) -> Color {
        if intensity == 0 {
            return Color.gray.opacity(0.2)
        }
        return Color.green.opacity(0.3 + (intensity * 0.7))
    }
    
    // MARK: - Glass Tints
    
    static let glassTintPrimary = Color.teal.opacity(0.1)
    static let glassTintAccent = Color.white.opacity(0.05)
    static let glassTintWarning = Color.orange.opacity(0.1)
    static let glassTintError = Color.red.opacity(0.1)
    static let glassTintSuccess = Color.green.opacity(0.1)
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
