import Foundation

// MARK: - Read Aloud Passage

struct ReadAloudPassage: Identifiable, Hashable {
    let id: String
    let title: String
    let text: String
    let difficulty: ReadAloudDifficulty
    let category: ReadAloudCategory

    var wordCount: Int {
        text.split(separator: " ").count
    }

    var words: [String] {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }
}

// MARK: - Difficulty

enum ReadAloudDifficulty: String, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }

    var icon: String {
        switch self {
        case .easy: return "1.circle.fill"
        case .medium: return "2.circle.fill"
        case .hard: return "3.circle.fill"
        }
    }
}

// MARK: - Category

enum ReadAloudCategory: String, CaseIterable, Identifiable {
    case news
    case literature
    case technical
    case tongueTwister
    case minimalPairs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .news: return "News"
        case .literature: return "Literature"
        case .technical: return "Technical"
        case .tongueTwister: return "Tongue Twister"
        case .minimalPairs: return "Minimal Pairs"
        }
    }

    var icon: String {
        switch self {
        case .news: return "newspaper"
        case .literature: return "book"
        case .technical: return "gearshape.2"
        case .tongueTwister: return "mouth"
        case .minimalPairs: return "ear"
        }
    }
}

extension ReadAloudPassage {
    /// Ephemeral passage from user-typed text. Not stored in the catalog.
    static func custom(text: String) -> ReadAloudPassage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        let difficulty: ReadAloudDifficulty
        switch wordCount {
        case 0..<12: difficulty = .easy
        case 12..<40: difficulty = .medium
        default: difficulty = .hard
        }
        return ReadAloudPassage(
            id: "custom-\(UUID().uuidString)",
            title: "Practice anything",
            text: trimmed,
            difficulty: difficulty,
            category: .news
        )
    }
}
