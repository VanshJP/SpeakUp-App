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
        let audienceSize = event.audienceSize
        let planningHorizon = min(daysUntil, 60)

        // Generate timeline tasks with adaptive cadence:
        // - Far out: fewer tasks to avoid burnout
        // - Close to event: daily focus
        for dayOffset in 0..<planningHorizon {
            let daysRemaining = daysUntil - dayOffset
            guard shouldScheduleTaskDay(
                dayOffset: dayOffset,
                daysRemaining: daysRemaining,
                totalDays: daysUntil
            ) else { continue }

            let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            let phase = phaseForDay(dayOffset: dayOffset, totalDays: daysUntil)
            var tasks = tasksForPhase(
                phase,
                sessionType: sessionType,
                hasSections: hasSections,
                day: dayOffset,
                daysRemaining: daysRemaining,
                audienceSize: audienceSize
            )
            tasks.append(contentsOf: milestoneTasks(daysRemaining: daysRemaining))
            let dailyBudget = dailyBudgetMinutes(for: phase, maxDailyMinutes: event.maxDailyPracticeMinutes)

            var seen = Set<String>()
            tasks = tasks
                .sorted { lhs, rhs in
                    if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                    return lhs.type.rawValue < rhs.type.rawValue
                }
                .filter { task in
                    let key = "\(task.type.rawValue)-\(task.title)"
                    if seen.contains(key) { return false }
                    seen.insert(key)
                    return true
                }
            let dailyCap = daysRemaining <= 7 ? 4 : 3

            var selected: [TaskInfo] = []
            var consumedMinutes = 0
            for task in tasks.prefix(dailyCap) {
                if selected.isEmpty {
                    selected.append(task)
                    consumedMinutes += task.estimatedMinutes
                    continue
                }
                if consumedMinutes + task.estimatedMinutes <= dailyBudget {
                    selected.append(task)
                    consumedMinutes += task.estimatedMinutes
                }
            }

            for taskInfo in selected {
                let task = EventPrepTask(
                    eventId: event.id,
                    scheduledDate: date,
                    taskType: taskInfo.type.rawValue,
                    title: taskInfo.title,
                    taskDescription: taskInfo.description,
                    targetSectionIndex: taskInfo.sectionIndex,
                    drillMode: taskInfo.type.associatedDrillMode,
                    priority: taskInfo.priority,
                    estimatedMinutes: taskInfo.estimatedMinutes
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
        var estimatedMinutes: Int = 10
    }

    private func tasksForPhase(
        _ phase: EventPrepPhase,
        sessionType: SessionType,
        hasSections: Bool,
        day: Int,
        daysRemaining: Int,
        audienceSize: Int?
    ) -> [TaskInfo] {
        switch phase {
        case .foundation:
            var tasks: [TaskInfo] = []
            if day == 0 {
                tasks.append(
                    TaskInfo(type: .scriptReview, title: "Review your script", description: "Read through your script to get familiar with the content.", priority: 1, estimatedMinutes: 8)
                )
            }
            if day % 4 == 0 {
                tasks.append(
                    TaskInfo(type: .scriptRevision, title: "Refine your script", description: "Tighten language, simplify transitions, and cut weak phrases before your next rehearsal.", priority: 1, estimatedMinutes: 15)
                )
            }
            tasks.append(
                TaskInfo(type: .warmUp, title: sessionType.primaryWarmUpTitle, description: "Start with a \(sessionType.primaryWarmUpTitle.lowercased()) before practicing.", priority: 3, estimatedMinutes: 6)
            )
            tasks.append(
                TaskInfo(type: .sectionPractice, title: "Practice a section", description: "Pick one section and rehearse it a few times with cleaner pauses.", sectionIndex: day % max(1, (hasSections ? 3 : 1)), priority: 2, estimatedMinutes: 12)
            )
            return tasks

        case .building:
            let drillTypes = sessionType.primaryDrillTaskTypes
            var tasks: [TaskInfo] = [
                TaskInfo(type: .fullRehearsal, title: "Full run-through", description: "Practice your entire speech from start to finish.", priority: 1, estimatedMinutes: 20),
            ]
            if day % 3 == 0 {
                tasks.append(
                    TaskInfo(type: .scriptRevision, title: "Revision checkpoint", description: "Update your script based on your latest rehearsal notes and lock improvements.", priority: 1, estimatedMinutes: 18)
                )
            }
            let drillType = drillTypes[day % drillTypes.count]
            let drillDescription: String
            switch drillType {
            case .fillerDrill: drillDescription = "Spend 15 seconds speaking with zero fillers."
            case .paceDrill: drillDescription = "Practice speaking at your target pace."
            case .pauseDrill: drillDescription = "Practice deliberate pauses at natural break points."
            case .readAloudDrill: drillDescription = "Read a passage aloud focusing on clarity and pace."
            default: drillDescription = "Complete a focused drill to sharpen your skills."
            }
            tasks.append(TaskInfo(type: drillType, title: drillType.displayName, description: drillDescription, priority: 3, estimatedMinutes: 10))
            if daysRemaining <= 21 && day % 4 == 0 {
                tasks.append(
                    TaskInfo(
                        type: .audienceSimulation,
                        title: "Audience simulation",
                        description: "Do one run as if you're speaking to \(audienceDescriptor(audienceSize)) and keep your delivery intentional.",
                        priority: 2,
                        estimatedMinutes: 18
                    )
                )
            }
            return tasks

        case .performance:
            var tasks: [TaskInfo] = [
                TaskInfo(type: .fullRehearsal, title: "Final rehearsal", description: "Full run-through as if it's the real event.", priority: 1, estimatedMinutes: 25),
                TaskInfo(type: .confidenceExercise, title: "Confidence exercise", description: sessionType.primaryConfidenceDescription, priority: 2, estimatedMinutes: 10),
            ]
            if daysRemaining <= 3 {
                tasks.append(
                    TaskInfo(
                        type: .audienceSimulation,
                        title: "Pressure simulation",
                        description: "Rehearse with \(audienceDescriptor(audienceSize)) pressure, strict timing, and a confident opening.",
                        priority: 1,
                        estimatedMinutes: 20
                    )
                )
            }
            if day == 0 || sessionType.hasDeadline || daysRemaining <= 1 {
                tasks.append(TaskInfo(type: .dayOfPrep, title: "Day-of prep", description: "Quick breathing exercise and final script review.", priority: 1, estimatedMinutes: 12))
            }
            return tasks
        }
    }

    // MARK: - Timeline Helpers

    private func shouldScheduleTaskDay(dayOffset: Int, daysRemaining: Int, totalDays: Int) -> Bool {
        if dayOffset == 0 || daysRemaining <= 10 { return true }
        if totalDays <= 21 { return dayOffset % 2 == 0 }
        if daysRemaining > 35 { return dayOffset % 3 == 0 }
        return dayOffset % 2 == 0
    }

    private func milestoneTasks(daysRemaining: Int) -> [TaskInfo] {
        switch daysRemaining {
        case 21:
            return [
                TaskInfo(
                    type: .scriptRevision,
                    title: "Milestone: narrative lock",
                    description: "Lock your opening, core message, and close so future practice focuses on delivery.",
                    priority: 1,
                    estimatedMinutes: 20
                )
            ]
        case 14:
            return [
                TaskInfo(
                    type: .audienceSimulation,
                    title: "Milestone: first pressure run",
                    description: "Run your talk once at full intensity with strict timing and minimal pauses.",
                    priority: 1,
                    estimatedMinutes: 25
                )
            ]
        case 7:
            return [
                TaskInfo(
                    type: .fullRehearsal,
                    title: "Milestone: full dress rehearsal",
                    description: "Deliver your full talk in one take and note final script edits.",
                    priority: 1,
                    estimatedMinutes: 30
                )
            ]
        case 3:
            return [
                TaskInfo(
                    type: .scriptRevision,
                    title: "Milestone: freeze script",
                    description: "Freeze your final version and focus only on pace, pauses, and confidence.",
                    priority: 1,
                    estimatedMinutes: 15
                )
            ]
        case 1:
            return [
                TaskInfo(
                    type: .dayOfPrep,
                    title: "Milestone: event eve prep",
                    description: "Light warm-up, one confident run-through, then rest your voice.",
                    priority: 1,
                    estimatedMinutes: 15
                )
            ]
        default:
            return []
        }
    }

    private func audienceDescriptor(_ audienceSize: Int?) -> String {
        guard let audienceSize, audienceSize > 0 else { return "your target audience" }
        if audienceSize >= 100000 { return "a 100k+ crowd" }
        if audienceSize >= 10000 { return "a large crowd" }
        if audienceSize >= 1000 { return "a big room" }
        if audienceSize >= 100 { return "a packed room" }
        return "a small room"
    }

    private func dailyBudgetMinutes(for phase: EventPrepPhase, maxDailyMinutes: Int) -> Int {
        let capped = max(10, min(180, maxDailyMinutes))
        switch phase {
        case .foundation:
            return max(10, Int(Double(capped) * 0.30))
        case .building:
            return max(15, Int(Double(capped) * 0.65))
        case .performance:
            return capped
        }
    }
}
