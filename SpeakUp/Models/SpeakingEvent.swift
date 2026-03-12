import Foundation
import SwiftData

@Model
final class SpeakingEvent {
    var id: UUID
    var title: String
    var eventDate: Date
    var expectedDurationMinutes: Int
    var audienceType: String?
    var venue: String?
    var notes: String?
    var scriptText: String?
    var scriptSections: [ScriptSection]?
    var createdDate: Date
    var isArchived: Bool = false
    var readinessScore: Int = 0
    var totalPracticeCount: Int = 0
    var lastPracticeDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        eventDate: Date,
        expectedDurationMinutes: Int,
        audienceType: String? = nil,
        venue: String? = nil,
        notes: String? = nil,
        scriptText: String? = nil,
        scriptSections: [ScriptSection]? = nil,
        createdDate: Date = Date(),
        isArchived: Bool = false,
        readinessScore: Int = 0,
        totalPracticeCount: Int = 0,
        lastPracticeDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.eventDate = eventDate
        self.expectedDurationMinutes = expectedDurationMinutes
        self.audienceType = audienceType
        self.venue = venue
        self.notes = notes
        self.scriptText = scriptText
        self.scriptSections = scriptSections
        self.createdDate = createdDate
        self.isArchived = isArchived
        self.readinessScore = readinessScore
        self.totalPracticeCount = totalPracticeCount
        self.lastPracticeDate = lastPracticeDate
    }

    // MARK: - Computed Properties

    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: eventDate)).day ?? 0
    }

    var totalDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: createdDate), to: Calendar.current.startOfDay(for: eventDate)).day ?? 1)
    }

    var isPast: Bool {
        eventDate < Date()
    }

    var currentPhase: EventPrepPhase {
        let remaining = Double(daysRemaining)
        let total = Double(totalDays)
        guard total > 0 else { return .performance }
        let percentRemaining = remaining / total
        if percentRemaining > 0.6 { return .foundation }
        if percentRemaining > 0.2 { return .building }
        return .performance
    }

    var daysRemainingText: String {
        let days = daysRemaining
        if days < 0 { return "Event passed" }
        if days == 0 { return "Today!" }
        if days == 1 { return "Tomorrow" }
        return "\(days) days to go"
    }
}

// MARK: - Script Section

struct ScriptSection: Codable, Identifiable, Hashable {
    var id: UUID
    var index: Int
    var title: String
    var text: String
    var wordCount: Int
    var targetDurationSeconds: Int
    var masteryScore: Int = 0
    var practiceCount: Int = 0
    var lastPracticeDate: Date?

    init(
        id: UUID = UUID(),
        index: Int,
        title: String,
        text: String,
        wordCount: Int,
        targetDurationSeconds: Int,
        masteryScore: Int = 0,
        practiceCount: Int = 0,
        lastPracticeDate: Date? = nil
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.text = text
        self.wordCount = wordCount
        self.targetDurationSeconds = targetDurationSeconds
        self.masteryScore = masteryScore
        self.practiceCount = practiceCount
        self.lastPracticeDate = lastPracticeDate
    }
}

// MARK: - Prep Phase

enum EventPrepPhase: String, Codable {
    case foundation
    case building
    case performance

    var displayName: String {
        switch self {
        case .foundation: return "Foundation"
        case .building: return "Building"
        case .performance: return "Performance"
        }
    }

    var tasksPerDay: ClosedRange<Int> {
        switch self {
        case .foundation: return 0...1
        case .building: return 1...1
        case .performance: return 1...2
        }
    }
}

// MARK: - Audience Type

enum AudienceType: String, CaseIterable, Identifiable {
    case colleagues = "Colleagues"
    case publicAudience = "Public"
    case students = "Students"
    case panel = "Panel"
    case other = "Other"

    var id: String { rawValue }
}
