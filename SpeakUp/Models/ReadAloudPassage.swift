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

    /// User-typed word, sentence, or short paragraph for pronunciation practice.
    static let customMinCharacters = 2
    static let customMaxCharacters = 800

    /// Builds an ephemeral passage from freeform text. Returns `nil` when the
    /// input is empty or only punctuation/whitespace.
    static func custom(from raw: String) -> ReadAloudPassage? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= customMinCharacters else { return nil }

        let capped = String(cleaned.prefix(customMaxCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !capped.isEmpty else { return nil }

        let count = capped.split(whereSeparator: { $0.isWhitespace }).count
        let title: String
        switch count {
        case 1: title = "Word practice"
        case 2...20: title = "Sentence practice"
        default: title = "Paragraph practice"
        }

        let difficulty: ReadAloudDifficulty
        switch count {
        case 1...8: difficulty = .easy
        case 9...40: difficulty = .medium
        default: difficulty = .hard
        }

        return ReadAloudPassage(
            id: "custom-\(UUID().uuidString)",
            title: title,
            text: capped,
            difficulty: difficulty,
            category: .custom
        )
    }

    /// True when this passage came from the freeform practice field.
    var isCustom: Bool { category == .custom }
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
    /// Ephemeral user-typed practice — not shown in catalog filters.
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .news: return "News"
        case .literature: return "Literature"
        case .technical: return "Technical"
        case .tongueTwister: return "Tongue Twister"
        case .custom: return "Yours"
        }
    }

    var icon: String {
        switch self {
        case .news: return "newspaper"
        case .literature: return "book"
        case .technical: return "gearshape.2"
        case .tongueTwister: return "mouth"
        case .custom: return "text.cursor"
        }
    }

    /// Catalog filters — excludes freeform custom passages.
    static var catalogCases: [ReadAloudCategory] {
        allCases.filter { $0 != .custom }
    }
}
