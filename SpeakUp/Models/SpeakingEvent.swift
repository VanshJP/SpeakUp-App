import Foundation
import SwiftData

// MARK: - Session Type

enum SessionType: String, CaseIterable, Identifiable {
    case presentation = "Presentation"
    case shortVideo = "Short Video"
    case longVideo = "Long Video"
    case podcast = "Podcast"
    case voiceOver = "Voice-Over"
    case speech = "Speech"
    case practice = "Just Practice"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .presentation: return "person.and.background.dotted"
        case .shortVideo: return "video.badge.waveform"
        case .longVideo: return "play.rectangle"
        case .podcast: return "mic.and.signal.meter"
        case .voiceOver: return "waveform.and.mic"
        case .speech: return "podium"
        case .practice: return "figure.mind.and.body"
        }
    }

    var defaultDurationMinutes: Int {
        switch self {
        case .shortVideo: return 1
        case .longVideo: return 10
        case .podcast: return 30
        case .voiceOver: return 2
        case .presentation: return 10
        case .speech: return 5
        case .practice: return 2
        }
    }

    var hasDeadline: Bool {
        switch self {
        case .practice, .podcast: return false
        default: return true
        }
    }

    var suggestedAudienceTypes: [AudienceType] {
        switch self {
        case .presentation: return AudienceType.allCases
        case .shortVideo: return [.viewers, .camera, .publicAudience]
        case .longVideo: return [.viewers, .camera, .publicAudience]
        case .podcast: return [.listeners]
        case .voiceOver: return [.camera]
        case .speech: return AudienceType.allCases
        case .practice: return []
        }
    }

    var durationOptions: [Int] {
        switch self {
        case .shortVideo: return [1, 2, 3, 5]
        case .longVideo: return [5, 10, 15, 20, 30]
        case .podcast: return [10, 15, 20, 30]
        case .voiceOver: return [1, 2, 3, 5]
        case .presentation: return [5, 10, 15, 20, 30]
        case .speech: return [1, 2, 3, 5, 10, 15, 20, 30]
        case .practice: return [1, 2, 3, 5, 10]
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .presentation: return "e.g., Q1 All-Hands"
        case .shortVideo: return "e.g., Product Launch Reel"
        case .longVideo: return "e.g., Tutorial: Getting Started"
        case .podcast: return "e.g., Episode 12: Deep Dive"
        case .voiceOver: return "e.g., App Walkthrough"
        case .speech: return "e.g., Wedding Toast"
        case .practice: return "e.g., Impromptu Practice"
        }
    }

    var venueLabel: String {
        switch self {
        case .shortVideo, .longVideo: return "Platform"
        case .podcast: return "Platform"
        case .voiceOver: return "Project"
        case .presentation: return "Venue"
        case .speech: return "Venue"
        case .practice: return "Location"
        }
    }

    var showsVenue: Bool {
        self != .practice
    }

    var showsAudience: Bool {
        self != .practice && self != .voiceOver
    }
}

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
    var sessionType: String?
    var isOpenEnded: Bool = false
    var teleprompterSpeed: Double = 1.0
    var teleprompterFontSize: Double = 24.0
    var expectedDurationSeconds: Int = 0
    var scriptVersions: [ScriptVersion]?

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
        lastPracticeDate: Date? = nil,
        sessionType: String? = nil,
        isOpenEnded: Bool = false,
        teleprompterSpeed: Double = 1.0,
        teleprompterFontSize: Double = 24.0,
        expectedDurationSeconds: Int = 0,
        scriptVersions: [ScriptVersion]? = nil
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
        self.sessionType = sessionType
        self.isOpenEnded = isOpenEnded
        self.teleprompterSpeed = teleprompterSpeed
        self.teleprompterFontSize = teleprompterFontSize
        self.expectedDurationSeconds = expectedDurationSeconds
        self.scriptVersions = scriptVersions
    }

    // MARK: - Computed Properties

    var resolvedSessionType: SessionType {
        guard let sessionType else { return .speech }
        return SessionType(rawValue: sessionType) ?? .speech
    }

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

    var currentScriptVersion: ScriptVersion? {
        scriptVersions?.max(by: { $0.versionNumber < $1.versionNumber })
    }

    var currentVersionNumber: Int {
        currentScriptVersion?.versionNumber ?? 0
    }

    var daysRemainingText: String {
        if isOpenEnded { return "Open-ended" }
        let days = daysRemaining
        if days < 0 { return "Event passed" }
        if days == 0 { return "Today!" }
        if days == 1 { return "Tomorrow" }
        return "\(days) days to go"
    }
}

// MARK: - Script Version

struct ScriptVersion: Codable, Identifiable, Hashable {
    var id: UUID
    var versionNumber: Int
    var scriptText: String
    var scriptSections: [ScriptSection]
    var createdDate: Date
    var changeNote: String?
    var wordCount: Int

    init(
        id: UUID = UUID(),
        versionNumber: Int,
        scriptText: String,
        scriptSections: [ScriptSection],
        createdDate: Date = Date(),
        changeNote: String? = nil
    ) {
        self.id = id
        self.versionNumber = versionNumber
        self.scriptText = scriptText
        self.scriptSections = scriptSections
        self.createdDate = createdDate
        self.changeNote = changeNote
        self.wordCount = scriptText.split(separator: " ").count
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
    case viewers = "Viewers"
    case listeners = "Listeners"
    case camera = "Camera"
    case other = "Other"

    var id: String { rawValue }
}
