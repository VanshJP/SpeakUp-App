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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .news: return "News"
        case .literature: return "Literature"
        case .technical: return "Technical"
        case .tongueTwister: return "Tongue Twister"
        }
    }

    var icon: String {
        switch self {
        case .news: return "newspaper"
        case .literature: return "book"
        case .technical: return "gearshape.2"
        case .tongueTwister: return "mouth"
        }
    }
}
