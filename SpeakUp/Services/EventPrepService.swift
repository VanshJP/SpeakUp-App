import Foundation
import SwiftData

// MARK: - Event Prep Error

enum EventPrepError: LocalizedError {
    case eventNotFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .eventNotFound: return "Event not found."
        case .saveFailed(let detail): return "Failed to save: \(detail)"
        }
    }
}

// MARK: - Event Prep Service

@Observable
class EventPrepService {
    var errorMessage: String?

    // MARK: - Generate Tasks

    func generateTasks(for event: SpeakingEvent, context: ModelContext) {
        guard !event.isOpenEnded else { return }

        let daysUntil = event.daysRemaining
        guard daysUntil > 0 else { return }

        // Clear existing uncompleted tasks
        let eventId = event.id
        let descriptor = FetchDescriptor<EventPrepTask>(
            predicate: #Predicate { $0.eventId == eventId && !$0.isCompleted }
        )
        if let existing = try? context.fetch(descriptor) {
            for task in existing {
                context.delete(task)
            }
        }

        let hasSections = event.scriptSections?.isEmpty == false
        let sessionType = event.resolvedSessionType

        // Generate tasks for each remaining day
        for dayOffset in 0..<min(daysUntil, 14) {
            let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            let phase = phaseForDay(dayOffset: dayOffset, totalDays: daysUntil)
            let tasks = tasksForPhase(phase, sessionType: sessionType, hasSections: hasSections, day: dayOffset)

            for taskInfo in tasks {
                let task = EventPrepTask(
                    eventId: event.id,
                    scheduledDate: date,
                    taskType: taskInfo.type.rawValue,
                    title: taskInfo.title,
                    taskDescription: taskInfo.description,
                    targetSectionIndex: taskInfo.sectionIndex,
                    drillMode: taskInfo.type.associatedDrillMode,
                    priority: taskInfo.priority
                )
                context.insert(task)
            }
        }

        try? context.save()
    }

    // MARK: - Complete Task

    func completeTask(_ task: EventPrepTask, recordingId: UUID? = nil, context: ModelContext) {
        task.isCompleted = true
        task.completedDate = Date()
        task.linkedRecordingId = recordingId
        try? context.save()
    }

    // MARK: - Fetch Tasks

    func fetchTasks(for eventId: UUID, context: ModelContext) -> [EventPrepTask] {
        let descriptor = FetchDescriptor<EventPrepTask>(
            predicate: #Predicate { $0.eventId == eventId },
            sortBy: [SortDescriptor(\.scheduledDate), SortDescriptor(\.priority)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func todaysTasks(for eventId: UUID, context: ModelContext) -> [EventPrepTask] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let descriptor = FetchDescriptor<EventPrepTask>(
            predicate: #Predicate {
                $0.eventId == eventId && $0.scheduledDate >= today && $0.scheduledDate < tomorrow
            },
            sortBy: [SortDescriptor(\.priority)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Phase Determination

    private func phaseForDay(dayOffset: Int, totalDays: Int) -> EventPrepPhase {
        let remaining = totalDays - dayOffset
        let percentRemaining = Double(remaining) / Double(totalDays)
        if percentRemaining > 0.6 { return .foundation }
        if percentRemaining > 0.2 { return .building }
        return .performance
    }

    // MARK: - Task Generation

    private struct TaskInfo {
        let type: EventPrepTaskType
        let title: String
        let description: String
        var sectionIndex: Int? = nil
        var priority: Int = 2
    }

    private func tasksForPhase(_ phase: EventPrepPhase, sessionType: SessionType, hasSections: Bool, day: Int) -> [TaskInfo] {
        switch phase {
        case .foundation:
            if day == 0 {
                return [
                    TaskInfo(type: .scriptReview, title: "Review your script", description: "Read through your script to get familiar with the content.", priority: 1)
                ]
            }
            return [
                TaskInfo(type: .warmUp, title: sessionType.primaryWarmUpTitle, description: "Start with a \(sessionType.primaryWarmUpTitle.lowercased()) before practicing.", priority: 3),
                TaskInfo(type: .sectionPractice, title: "Practice a section", description: "Pick one section and rehearse it a few times.", sectionIndex: day % max(1, (hasSections ? 3 : 1)), priority: 2),
            ]

        case .building:
            let drillTypes = sessionType.primaryDrillTaskTypes
            var tasks: [TaskInfo] = [
                TaskInfo(type: .fullRehearsal, title: "Full run-through", description: "Practice your entire speech from start to finish.", priority: 1),
            ]
            let drillType = drillTypes[day % drillTypes.count]
            let drillDescription: String
            switch drillType {
            case .fillerDrill: drillDescription = "Spend 15 seconds speaking with zero fillers."
            case .paceDrill: drillDescription = "Practice speaking at your target pace."
            case .pauseDrill: drillDescription = "Practice deliberate pauses at natural break points."
            case .readAloudDrill: drillDescription = "Read a passage aloud focusing on clarity and pace."
            default: drillDescription = "Complete a focused drill to sharpen your skills."
            }
            tasks.append(TaskInfo(type: drillType, title: drillType.displayName, description: drillDescription, priority: 3))
            return tasks

        case .performance:
            var tasks: [TaskInfo] = [
                TaskInfo(type: .fullRehearsal, title: "Final rehearsal", description: "Full run-through as if it's the real event.", priority: 1),
                TaskInfo(type: .confidenceExercise, title: "Confidence exercise", description: sessionType.primaryConfidenceDescription, priority: 2),
            ]
            if day == 0 || sessionType.hasDeadline {
                tasks.append(TaskInfo(type: .dayOfPrep, title: "Day-of prep", description: "Quick breathing exercise and final script review.", priority: 1))
            }
            return tasks
        }
    }
}
