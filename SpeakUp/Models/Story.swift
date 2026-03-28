import Foundation
import SwiftData

@Model
final class Story {
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var tags: [StoryTag] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isFavorite: Bool = false
    var practiceCount: Int = 0
    var colorHex: String?
    var iconName: String?
    var inputMethod: String = "typed"

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        tags: [StoryTag] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        practiceCount: Int = 0,
        colorHex: String? = nil,
        iconName: String? = nil,
        inputMethod: String = "typed"
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.practiceCount = practiceCount
        self.colorHex = colorHex
        self.iconName = iconName
        self.inputMethod = inputMethod
    }

    /// Number of words in the story content
    var wordCount: Int {
        content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Short preview of story content for list display
    var contentPreview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 100 { return trimmed }
        return String(trimmed.prefix(100)) + "…"
    }

    /// Tags of a specific type
    func tags(ofType type: StoryTagType) -> [StoryTag] {
        tags.filter { $0.type == type }
    }

    /// All unique tag types present on this story
    var tagTypes: Set<StoryTagType> {
        Set(tags.map(\.type))
    }
}

// MARK: - Supporting Types

enum StoryTagType: String, Codable, CaseIterable, Identifiable {
    case friend
    case date
    case location
    case topic
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .friend: return "Friends"
        case .date: return "Dates"
        case .location: return "Locations"
        case .topic: return "Topics"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .friend: return "person.2"
        case .date: return "calendar"
        case .location: return "mappin"
        case .topic: return "tag"
        case .custom: return "pencil"
        }
    }
}

struct StoryTag: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var type: StoryTagType
    var value: String
    var parsedDate: Date?
}
