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
    var storyStage: String = "spark"
    var occasion: String?
    var estimatedDurationSeconds: Int = 0
    var lastPracticeDate: Date?
    var bestScore: Int = 0
    var entryType: String = "story"

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
        inputMethod: String = "typed",
        storyStage: String = "spark",
        occasion: String? = nil,
        estimatedDurationSeconds: Int = 0,
        lastPracticeDate: Date? = nil,
        bestScore: Int = 0,
        entryType: String = "story"
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
        self.storyStage = storyStage
        self.occasion = occasion
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.lastPracticeDate = lastPracticeDate
        self.bestScore = bestScore
        self.entryType = entryType
    }

    // MARK: - Computed Properties

    var wordCount: Int {
        content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var contentPreview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 120 { return trimmed }
        return String(trimmed.prefix(120)) + "…"
    }

    var resolvedStage: StoryStage {
        StoryStage(rawValue: storyStage) ?? .spark
    }

    var resolvedOccasion: StoryOccasion? {
        guard let occasion else { return nil }
        return StoryOccasion(rawValue: occasion)
    }

    var estimatedReadingTime: String {
        let words = wordCount
        guard words > 0 else { return "0s" }
        let seconds = max(1, words * 60 / 150)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        if remaining == 0 { return "\(minutes)m" }
        return "\(minutes)m \(remaining)s"
    }

    func tags(ofType type: StoryTagType) -> [StoryTag] {
        tags.filter { $0.type == type }
    }

    var tagTypes: Set<StoryTagType> {
        Set(tags.map(\.type))
    }

    var resolvedEntryType: StoryEntryType {
        StoryEntryType(rawValue: entryType) ?? .story
    }
}

// MARK: - Entry Type

enum StoryEntryType: String, Codable, CaseIterable, Identifiable {
    case story
    case reflection
    case note

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .story: return "Story"
        case .reflection: return "Reflection"
        case .note: return "Note"
        }
    }

    var icon: String {
        switch self {
        case .story: return "book.pages"
        case .reflection: return "thought.bubble"
        case .note: return "note.text"
        }
    }
}

// MARK: - Story Stage

enum StoryStage: String, Codable, CaseIterable, Identifiable {
    case spark
    case draft
    case polished

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spark: return "Idea"
        case .draft: return "In Progress"
        case .polished: return "Ready"
        }
    }

    var icon: String {
        switch self {
        case .spark: return "lightbulb"
        case .draft: return "pencil.line"
        case .polished: return "checkmark.circle"
        }
    }

    var description: String {
        switch self {
        case .spark: return "Quick idea or memory"
        case .draft: return "Working on it"
        case .polished: return "Ready to tell"
        }
    }
}

// MARK: - Story Occasion

enum StoryOccasion: String, Codable, CaseIterable, Identifiable {
    case casual = "Casual"
    case interview = "Job Interview"
    case toast = "Toast / Speech"
    case pitch = "Pitch"
    case icebreaker = "Icebreaker"
    case networking = "Networking"
    case teaching = "Teaching"
    case personal = "Personal"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .casual: return "bubble.left"
        case .interview: return "briefcase"
        case .toast: return "wineglass"
        case .pitch: return "chart.line.uptrend.xyaxis"
        case .icebreaker: return "person.2"
        case .networking: return "link"
        case .teaching: return "book"
        case .personal: return "heart"
        }
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
        case .friend: return "People"
        case .date: return "Dates"
        case .location: return "Places"
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
