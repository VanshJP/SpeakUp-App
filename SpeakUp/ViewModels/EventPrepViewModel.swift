import Foundation
import SwiftUI
import SwiftData

@MainActor @Observable
class EventPrepViewModel {
    var events: [SpeakingEvent] = []
    var selectedEvent: SpeakingEvent?
    var tasks: [EventPrepTask] = []
    var nextTask: EventPrepTask?
    var errorMessage: String?

    // Create event form state
    var newTitle = ""
    var newEventDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    var newDurationMinutes = 5
    var newAudienceType: String?
    var newVenue = ""
    var newNotes = ""
    var newScriptText = ""

    private let service = EventPrepService()
    private var modelContext: ModelContext?

    static let durationOptions = [1, 2, 3, 5, 10, 15, 20, 30]

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Loading

    func loadEvents() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<SpeakingEvent>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.eventDate)]
        )
        events = (try? context.fetch(descriptor)) ?? []
    }

    func loadTasks(for event: SpeakingEvent) {
        guard let context = modelContext else { return }
        let eventId = event.id
        let descriptor = FetchDescriptor<EventPrepTask>(
            predicate: #Predicate { $0.eventId == eventId },
            sortBy: [SortDescriptor(\.scheduledDate)]
        )
        tasks = (try? context.fetch(descriptor)) ?? []
        nextTask = service.nextTask(for: event.id, context: context)
    }

    func loadNearestEvent() {
        guard let context = modelContext else { return }
        selectedEvent = service.nearestUpcomingEvent(context: context)
        if let event = selectedEvent {
            nextTask = service.nextTask(for: event.id, context: context)
        }
    }

    // MARK: - Create Event

    var canCreate: Bool {
        !newTitle.trimmingCharacters(in: .whitespaces).isEmpty && newEventDate > Date()
    }

    func createEvent() -> SpeakingEvent? {
        guard let context = modelContext, canCreate else { return nil }

        let script = newScriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = script.isEmpty ? nil : EventPrepService.parseScriptIntoSections(script, targetDurationMinutes: newDurationMinutes)

        let event = SpeakingEvent(
            title: newTitle.trimmingCharacters(in: .whitespaces),
            eventDate: newEventDate,
            expectedDurationMinutes: newDurationMinutes,
            audienceType: newAudienceType,
            venue: newVenue.isEmpty ? nil : newVenue,
            notes: newNotes.isEmpty ? nil : newNotes,
            scriptText: script.isEmpty ? nil : script,
            scriptSections: sections
        )

        context.insert(event)
        try? context.save()

        // Generate prep plan
        service.generatePrepPlan(for: event, context: context)

        // Update widget data
        updateWidgetData(event: event)

        resetForm()
        return event
    }

    func resetForm() {
        newTitle = ""
        newEventDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        newDurationMinutes = 5
        newAudienceType = nil
        newVenue = ""
        newNotes = ""
        newScriptText = ""
    }

    // MARK: - Task Actions

    func completeTask(_ task: EventPrepTask, recording: Recording? = nil) {
        guard let context = modelContext else { return }
        service.completeTask(task, recording: recording, context: context)
        if let event = selectedEvent {
            loadTasks(for: event)
        }
    }

    // MARK: - Event Actions

    func archiveEvent(_ event: SpeakingEvent) {
        event.isArchived = true
        try? modelContext?.save()
        loadEvents()
    }

    func deleteEvent(_ event: SpeakingEvent) {
        guard let context = modelContext else { return }
        // Delete associated tasks
        let eventId = event.id
        let taskDescriptor = FetchDescriptor<EventPrepTask>(
            predicate: #Predicate { $0.eventId == eventId }
        )
        if let tasks = try? context.fetch(taskDescriptor) {
            for task in tasks {
                context.delete(task)
            }
        }
        context.delete(event)
        try? context.save()
        loadEvents()
    }

    // MARK: - Stats

    var completedTaskCount: Int {
        tasks.filter(\.isCompleted).count
    }

    var upcomingTasks: [EventPrepTask] {
        tasks.filter { !$0.isCompleted }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var todaysTasks: [EventPrepTask] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return tasks.filter { $0.scheduledDate >= today && $0.scheduledDate < tomorrow && !$0.isCompleted }
    }

    // MARK: - Widget

    private func updateWidgetData(event: SpeakingEvent) {
        WidgetDataProvider.updateEventCountdown(
            title: event.title,
            daysRemaining: event.daysRemaining,
            readinessScore: event.readinessScore
        )
    }
}
