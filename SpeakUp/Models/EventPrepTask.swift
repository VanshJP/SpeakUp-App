import Foundation
import SwiftData

@Model
final class EventPrepTask {
    var id: UUID
    var eventId: UUID
    var scheduledDate: Date
    var taskType: String
    var title: String
    var taskDescription: String
    var targetSectionIndex: Int?
    var drillMode: String?
    var isCompleted: Bool = false
    var completedDate: Date?
    var linkedRecordingId: UUID?
    var priority: Int
    var estimatedMinutes: Int = 10

    init(
        id: UUID = UUID(),
        eventId: UUID,
        scheduledDate: Date,
        taskType: String,
        title: String,
        taskDescription: String,
        targetSectionIndex: Int? = nil,
        drillMode: String? = nil,
        isCompleted: Bool = false,
        completedDate: Date? = nil,
        linkedRecordingId: UUID? = nil,
        priority: Int = 2,
        estimatedMinutes: Int = 10
    ) {
        self.id = id
        self.eventId = eventId
        self.scheduledDate = scheduledDate
        self.taskType = taskType
        self.title = title
        self.taskDescription = taskDescription
        self.targetSectionIndex = targetSectionIndex
        self.drillMode = drillMode
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.linkedRecordingId = linkedRecordingId
        self.priority = priority
        self.estimatedMinutes = max(3, estimatedMinutes)
    }

    var type: EventPrepTaskType {
        EventPrepTaskType(rawValue: taskType) ?? .scriptReview
    }

    var isOverdue: Bool {
        !isCompleted && scheduledDate < Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - Task Type

enum EventPrepTaskType: String, CaseIterable, Identifiable {
    case fullRehearsal
    case sectionPractice
    case scriptRevision
    case audienceSimulation
    case fillerDrill
    case paceDrill
    case pauseDrill
    case warmUp
    case confidenceExercise
    case scriptReview
    case impromptuVariation
    case dayOfPrep
    case readAloudDrill

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullRehearsal: return "Full Rehearsal"
        case .sectionPractice: return "Section Practice"
        case .scriptRevision: return "Script Revision"
        case .audienceSimulation: return "Audience Simulation"
        case .fillerDrill: return "Filler Drill"
        case .paceDrill: return "Pace Drill"
        case .pauseDrill: return "Pause Drill"
        case .warmUp: return "Warm Up"
        case .confidenceExercise: return "Confidence Exercise"
        case .scriptReview: return "Script Review"
        case .impromptuVariation: return "Impromptu Variation"
        case .dayOfPrep: return "Day-of Prep"
        case .readAloudDrill: return "Read Aloud Drill"
        }
    }

    var icon: String {
        switch self {
        case .fullRehearsal: return "play.circle.fill"
        case .sectionPractice: return "doc.text.fill"
        case .scriptRevision: return "pencil.and.list.clipboard"
        case .audienceSimulation: return "person.3.sequence.fill"
        case .fillerDrill: return "xmark.circle.fill"
        case .paceDrill: return "speedometer"
        case .pauseDrill: return "pause.circle.fill"
        case .warmUp: return "wind"
        case .confidenceExercise: return "heart.fill"
        case .scriptReview: return "eye.fill"
        case .impromptuVariation: return "bolt.circle.fill"
        case .dayOfPrep: return "star.fill"
        case .readAloudDrill: return "text.book.closed"
        }
    }

    var color: String {
        switch self {
        case .fullRehearsal: return "teal"
        case .sectionPractice: return "blue"
        case .scriptRevision: return "indigo"
        case .audienceSimulation: return "purple"
        case .fillerDrill: return "orange"
        case .paceDrill: return "blue"
        case .pauseDrill: return "purple"
        case .warmUp: return "cyan"
        case .confidenceExercise: return "pink"
        case .scriptReview: return "indigo"
        case .impromptuVariation: return "red"
        case .dayOfPrep: return "yellow"
        case .readAloudDrill: return "indigo"
        }
    }

    var opensRecording: Bool {
        switch self {
        case .fullRehearsal, .sectionPractice, .audienceSimulation: return true
        default: return false
        }
    }

    var opensDrill: Bool {
        switch self {
        case .fillerDrill, .paceDrill, .pauseDrill, .readAloudDrill: return true
        default: return false
        }
    }

    var associatedDrillMode: String? {
        switch self {
        case .fillerDrill: return "fillerElimination"
        case .paceDrill: return "paceControl"
        case .pauseDrill: return "pausePractice"
        default: return nil
        }
    }
}
