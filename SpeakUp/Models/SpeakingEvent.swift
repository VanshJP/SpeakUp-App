import Foundation
import SwiftUI
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

    var color: Color {
        switch self {
        case .presentation: return AppColors.info
        case .shortVideo: return .pink
        case .longVideo: return .purple
        case .podcast: return AppColors.warning
        case .voiceOver: return .cyan
        case .speech: return AppColors.primary
        case .practice: return AppColors.accent
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

    // MARK: - Type-Specific Configuration

    var recommendedTools: [RecommendedTool] {
        switch self {
        case .presentation:
            return [
                RecommendedTool(name: "Pause Practice", icon: "pause.circle", color: .purple, tip: "Let key points land with deliberate pauses", action: .drill(.pausePractice)),
                RecommendedTool(name: "Read Aloud", icon: "text.book.closed", color: .indigo, tip: "Practice PREP/STAR frameworks out loud", action: .readAloud),
                RecommendedTool(name: "Confidence", icon: "heart.fill", color: .pink, tip: "Visualize commanding the room", action: .confidence),
                RecommendedTool(name: "Filler Drill", icon: "xmark.circle", color: .orange, tip: "Eliminate filler words under pressure", action: .drill(.fillerElimination)),
                RecommendedTool(name: "Breathing", icon: "wind", color: .cyan, tip: "Calm your nerves before presenting", action: .warmUp),
            ]
        case .shortVideo:
            return [
                RecommendedTool(name: "Pace Control", icon: "speedometer", color: .blue, tip: "Hit your timing for short-form content", action: .drill(.paceControl)),
                RecommendedTool(name: "Filler Drill", icon: "xmark.circle", color: .orange, tip: "Every filler costs precious seconds", action: .drill(.fillerElimination)),
                RecommendedTool(name: "Read Aloud", icon: "text.book.closed", color: .indigo, tip: "Nail your script delivery", action: .readAloud),
                RecommendedTool(name: "Articulation", icon: "mouth", color: .cyan, tip: "Crisp articulation for the mic", action: .warmUp),
            ]
        case .longVideo:
            return [
                RecommendedTool(name: "Pace Control", icon: "speedometer", color: .blue, tip: "Vary your pace to keep viewers engaged", action: .drill(.paceControl)),
                RecommendedTool(name: "Filler Drill", icon: "xmark.circle", color: .orange, tip: "Stay clean across a longer runtime", action: .drill(.fillerElimination)),
                RecommendedTool(name: "Pause Practice", icon: "pause.circle", color: .purple, tip: "Use pauses to structure long content", action: .drill(.pausePractice)),
                RecommendedTool(name: "Vocal Warm-Up", icon: "waveform", color: .cyan, tip: "Protect your voice for extended sessions", action: .warmUp),
            ]
        case .podcast:
            return [
                RecommendedTool(name: "Pace Control", icon: "speedometer", color: .blue, tip: "Find a conversational rhythm", action: .drill(.paceControl)),
                RecommendedTool(name: "Vocal Warm-Up", icon: "waveform", color: .cyan, tip: "Your voice IS the product", action: .warmUp),
                RecommendedTool(name: "Read Aloud", icon: "text.book.closed", color: .indigo, tip: "Practice reading show notes smoothly", action: .readAloud),
            ]
        case .voiceOver:
            return [
                RecommendedTool(name: "Read Aloud", icon: "text.book.closed", color: .indigo, tip: "Match your delivery to the visuals", action: .readAloud),
                RecommendedTool(name: "Pace Control", icon: "speedometer", color: .blue, tip: "Keep a steady, measured pace", action: .drill(.paceControl)),
                RecommendedTool(name: "Articulation", icon: "mouth", color: .cyan, tip: "Every syllable matters for VO", action: .warmUp),
            ]
        case .speech:
            return [
                RecommendedTool(name: "Pause Practice", icon: "pause.circle", color: .purple, tip: "Connect with your audience through pauses", action: .drill(.pausePractice)),
                RecommendedTool(name: "Confidence", icon: "heart.fill", color: .pink, tip: "Own the stage with confidence", action: .confidence),
                RecommendedTool(name: "Filler Drill", icon: "xmark.circle", color: .orange, tip: "Speak with purpose, not fillers", action: .drill(.fillerElimination)),
                RecommendedTool(name: "Breathing", icon: "wind", color: .cyan, tip: "Ground yourself before you speak", action: .warmUp),
            ]
        case .practice:
            return [
                RecommendedTool(name: "Filler Drill", icon: "xmark.circle", color: .orange, tip: "Quick reps to sharpen your speech", action: .drill(.fillerElimination)),
                RecommendedTool(name: "Pace Control", icon: "speedometer", color: .blue, tip: "Experiment with different paces", action: .drill(.paceControl)),
                RecommendedTool(name: "Impromptu", icon: "bolt.circle", color: .red, tip: "Think on your feet", action: .drill(.impromptuSprint)),
            ]
        }
    }

    var coachingTip: String {
        switch self {
        case .presentation: return "Focus on deliberate pauses to let key points land with your audience"
        case .shortVideo: return "Every second counts — nail your timing and cut the fillers"
        case .longVideo: return "Vary your pace to keep viewers engaged over a longer runtime"
        case .podcast: return "Your voice IS the product — warm up your vocals and nail your pacing"
        case .voiceOver: return "Clarity is king — articulate every syllable to match your visuals"
        case .speech: return "Connect with your audience through pauses and purposeful structure"
        case .practice: return "Experiment freely — try different drills and find your edge"
        }
    }

    var primaryDrillTaskTypes: [EventPrepTaskType] {
        switch self {
        case .presentation: return [.pauseDrill, .fillerDrill]
        case .shortVideo: return [.paceDrill, .fillerDrill]
        case .longVideo: return [.paceDrill, .fillerDrill]
        case .podcast: return [.paceDrill, .readAloudDrill]
        case .voiceOver: return [.readAloudDrill, .paceDrill]
        case .speech: return [.pauseDrill, .fillerDrill]
        case .practice: return [.fillerDrill, .paceDrill]
        }
    }

    var primaryWarmUpTitle: String {
        switch self {
        case .presentation, .speech: return "Breathing warm-up"
        case .shortVideo, .voiceOver: return "Articulation warm-up"
        case .longVideo, .podcast: return "Vocal warm-up"
        case .practice: return "Quick warm-up"
        }
    }

    var primaryConfidenceDescription: String {
        switch self {
        case .presentation, .speech: return "Visualize delivering your talk with confidence"
        case .shortVideo, .longVideo, .podcast, .voiceOver: return "A calming exercise to settle your nerves"
        case .practice: return "Build confidence through positive affirmations"
        }
    }
}

// MARK: - Tool Action

enum ToolAction {
    case drill(DrillMode)
    case readAloud
    case warmUp
    case confidence
    case teleprompter
    case script
}

// MARK: - Recommended Tool

struct RecommendedTool: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let tip: String
    let action: ToolAction
}

@Model
final class SpeakingEvent {
    var id: UUID
    var title: String
    var eventDate: Date
    var expectedDurationMinutes: Int
    var maxDailyPracticeMinutes: Int = 45
    var audienceType: String?
    var audienceSize: Int?
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
        maxDailyPracticeMinutes: Int = 45,
        audienceType: String? = nil,
        audienceSize: Int? = nil,
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
        self.maxDailyPracticeMinutes = max(10, maxDailyPracticeMinutes)
        self.audienceType = audienceType
        self.audienceSize = audienceSize
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

    var audienceScaleLabel: String {
        guard let audienceSize, audienceSize > 0 else { return "Not set" }
        if audienceSize < 20 { return "Small group" }
        if audienceSize < 200 { return "Room / workshop" }
        if audienceSize < 5000 { return "Large venue" }
        return "Mass audience"
    }

    var phasePracticeTargets: (foundation: Int, building: Int, performance: Int) {
        let maxDaily = max(10, maxDailyPracticeMinutes)
        let foundation = max(10, Int(Double(maxDaily) * 0.25))
        let building = max(15, Int(Double(maxDaily) * 0.6))
        let performance = max(20, maxDaily)
        return (foundation, building, performance)
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
