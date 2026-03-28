import Foundation
import SwiftUI
import SwiftData

@MainActor @Observable
class EventViewModel {
    let prepService = EventPrepService()
    let notificationService = NotificationService()

    var events: [SpeakingEvent] = []
    var selectedEvent: SpeakingEvent?
    var linkedRecordings: [Recording] = []
    var prepTasks: [EventPrepTask] = []
    var timelineDays: [EventTimelineDay] = []
    var revisionMilestones: [ScriptRevisionMilestone] = []
    var scriptInsightsByRecordingId: [UUID: ScriptPracticeInsight] = [:]
    var errorMessage: String?
    var showArchived = false
    var isCreating = false

    private var modelContext: ModelContext?
    private var configuredContextIdentifier: ObjectIdentifier?
    private var notificationRefreshTask: Task<Void, Never>?
    private var lastTaskNotificationSignature: Int = 0

    func configure(with context: ModelContext) {
        let contextIdentifier = ObjectIdentifier(context)
        if configuredContextIdentifier != contextIdentifier {
            self.modelContext = context
            configuredContextIdentifier = contextIdentifier
            loadEvents()
        } else if events.isEmpty {
            loadEvents()
        }
    }

    // MARK: - Load

    func loadEvents() {
        guard let context = modelContext else { return }
        let showArchived = self.showArchived
        let descriptor = FetchDescriptor<SpeakingEvent>(
            predicate: showArchived ? nil : #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.eventDate)]
        )
        events = (try? context.fetch(descriptor)) ?? []
    }

    var upcomingEvents: [SpeakingEvent] {
        events.filter { !$0.isPast && !$0.isArchived }
    }

    var pastEvents: [SpeakingEvent] {
        events.filter { $0.isPast || $0.isArchived }
    }

    // MARK: - Create

    func createEvent(
        title: String,
        sessionType: SessionType,
        eventDate: Date,
        expectedDurationMinutes: Int,
        maxDailyPracticeMinutes: Int = 45,
        audienceType: AudienceType? = nil,
        audienceSize: Int? = nil,
        venue: String? = nil,
        notes: String? = nil,
        scriptText: String? = nil,
        isOpenEnded: Bool = false
    ) async -> SpeakingEvent? {
        guard let context = modelContext else { return nil }

        isCreating = true
        defer { isCreating = false }

        var sections: [ScriptSection]? = nil
        var versions: [ScriptVersion]? = nil

        if let script = scriptText, !script.isEmpty {
            let sectionList = splitIntoSections(script)
            sections = sectionList

            let version = ScriptVersion(
                versionNumber: 1,
                scriptText: script,
                scriptSections: sectionList,
                changeNote: "Initial version"
            )
            versions = [version]
        }

        let event = SpeakingEvent(
            title: title,
            eventDate: eventDate,
            expectedDurationMinutes: expectedDurationMinutes,
            maxDailyPracticeMinutes: maxDailyPracticeMinutes,
            audienceType: audienceType?.rawValue,
            audienceSize: audienceSize,
            venue: venue,
            notes: notes,
            scriptText: scriptText,
            scriptSections: sections,
            sessionType: sessionType.rawValue,
            isOpenEnded: isOpenEnded,
            expectedDurationSeconds: expectedDurationMinutes * 60,
            scriptVersions: versions
        )

        context.insert(event)

        do {
            try context.save()
            loadEvents()
            Task { @MainActor in
                prepService.generateTasks(for: event, context: context)
            }

            return event
        } catch {
            errorMessage = "Failed to create event: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Update

    func archiveEvent(_ event: SpeakingEvent) {
        event.isArchived = true
        try? modelContext?.save()
        if selectedEvent?.id == event.id {
            scriptInsightsByRecordingId = [:]
        }
        loadEvents()
    }

    func unarchiveEvent(_ event: SpeakingEvent) {
        event.isArchived = false
        try? modelContext?.save()
        loadEvents()
    }

    func updateEventLogistics(
        _ event: SpeakingEvent,
        eventDate: Date,
        expectedDurationMinutes: Int,
        maxDailyPracticeMinutes: Int
    ) {
        guard let context = modelContext else { return }

        let sanitizedDuration = max(1, expectedDurationMinutes)
        let sanitizedDailyCapacity = max(10, maxDailyPracticeMinutes)

        let didChange =
            event.eventDate != eventDate ||
            event.expectedDurationMinutes != sanitizedDuration ||
            event.maxDailyPracticeMinutes != sanitizedDailyCapacity

        guard didChange else { return }

        event.eventDate = eventDate
        event.expectedDurationMinutes = sanitizedDuration
        event.expectedDurationSeconds = sanitizedDuration * 60
        event.maxDailyPracticeMinutes = sanitizedDailyCapacity

        try? context.save()
        prepService.generateTasks(for: event, context: context)
        loadPrepTasks(for: event)
        loadEvents()
    }

    func deleteEvent(_ event: SpeakingEvent) {
        guard let context = modelContext else { return }
        // Delete associated prep tasks
        let eventId = event.id
        let taskDescriptor = FetchDescriptor<EventPrepTask>(
            predicate: #Predicate { $0.eventId == eventId }
        )
        if let tasks = try? context.fetch(taskDescriptor) {
            for task in tasks { context.delete(task) }
        }
        context.delete(event)
        try? context.save()
        if selectedEvent?.id == event.id {
            selectedEvent = nil
            linkedRecordings = []
            prepTasks = []
            timelineDays = []
            revisionMilestones = []
            scriptInsightsByRecordingId = [:]
        }
        loadEvents()
    }

    // MARK: - Script Versions

    func saveNewScriptVersion(for event: SpeakingEvent, scriptText: String, changeNote: String?) {
        let sections = splitIntoSections(scriptText)
        let nextVersion = (event.currentVersionNumber) + 1

        let version = ScriptVersion(
            versionNumber: nextVersion,
            scriptText: scriptText,
            scriptSections: sections,
            changeNote: changeNote
        )

        if event.scriptVersions == nil {
            event.scriptVersions = [version]
        } else {
            event.scriptVersions?.append(version)
        }

        event.scriptText = scriptText
        event.scriptSections = sections

        try? modelContext?.save()
        if let context = modelContext {
            prepService.generateTasks(for: event, context: context)
            loadPrepTasks(for: event)
        }
        revisionMilestones = buildRevisionMilestones(for: event)
    }

    // MARK: - Recordings

    func loadLinkedRecordings(for event: SpeakingEvent) {
        guard let context = modelContext else { return }
        let eventId = event.id
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.eventId == eventId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        linkedRecordings = (try? context.fetch(descriptor)) ?? []

        var didMutateEvent = false
        if event.totalPracticeCount != linkedRecordings.count {
            event.totalPracticeCount = linkedRecordings.count
            didMutateEvent = true
        }
        let newestPracticeDate = linkedRecordings.first?.date
        if event.lastPracticeDate != newestPracticeDate {
            event.lastPracticeDate = newestPracticeDate
            didMutateEvent = true
        }

        // Update readiness score
        if updateReadinessScore(for: event) {
            didMutateEvent = true
        }
        if didMutateEvent {
            try? modelContext?.save()
        }

        refreshScriptInsights(for: event)
        revisionMilestones = buildRevisionMilestones(for: event)
    }

    // MARK: - Prep Tasks

    func loadPrepTasks(for event: SpeakingEvent) {
        guard let context = modelContext else { return }
        prepTasks = prepService.fetchTasks(for: event.id, context: context)
        timelineDays = buildTimelineDays(from: prepTasks)
        if updateReadinessScore(for: event) {
            try? modelContext?.save()
        }
        scheduleNotificationRefresh(tasks: prepTasks)
    }

    func completeTask(_ task: EventPrepTask, recordingId: UUID? = nil) {
        guard let context = modelContext else { return }
        prepService.completeTask(task, recordingId: recordingId, context: context)
        if let event = selectedEvent {
            loadPrepTasks(for: event)
            revisionMilestones = buildRevisionMilestones(for: event)
        }
    }

    // MARK: - Readiness Score

    @discardableResult
    private func updateReadinessScore(for event: SpeakingEvent) -> Bool {
        var score = 0.0

        // Practice count factor (up to 40 points)
        // Cap target so long-horizon events don't look permanently "behind."
        let practiceTarget = min(10, max(3, event.daysRemaining / 3))
        let practiceRatio = min(1.0, Double(event.totalPracticeCount) / Double(practiceTarget))
        score += practiceRatio * 40

        // Section mastery factor (up to 30 points)
        if let sections = event.scriptSections, !sections.isEmpty {
            let avgMastery = Double(sections.reduce(0) { $0 + $1.masteryScore }) / Double(sections.count)
            score += (avgMastery / 100.0) * 30
        } else {
            score += 15 // No sections = partial credit
        }

        // Completed tasks factor (up to 30 points)
        let completedTasks = prepTasks.filter(\.isCompleted).count
        let totalTasks = max(1, prepTasks.count)
        score += (Double(completedTasks) / Double(totalTasks)) * 30

        let nextScore = min(100, Int(score))
        guard event.readinessScore != nextScore else { return false }
        event.readinessScore = nextScore
        return true
    }

    // MARK: - Helpers

    private func splitIntoSections(_ text: String) -> [ScriptSection] {
        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if paragraphs.count <= 1 {
            let wordCount = text.split(separator: " ").count
            return [
                ScriptSection(
                    index: 0,
                    title: "Full Script",
                    text: text,
                    wordCount: wordCount,
                    targetDurationSeconds: max(10, wordCount * 60 / 150) // ~150 WPM
                )
            ]
        }

        return paragraphs.enumerated().map { index, paragraph in
            let wordCount = paragraph.split(separator: " ").count
            return ScriptSection(
                index: index,
                title: "Section \(index + 1)",
                text: paragraph.trimmingCharacters(in: .whitespacesAndNewlines),
                wordCount: wordCount,
                targetDurationSeconds: max(10, wordCount * 60 / 150)
            )
        }
    }

    // MARK: - Timeline Builders

    private func buildTimelineDays(from tasks: [EventPrepTask]) -> [EventTimelineDay] {
        let grouped = Dictionary(grouping: tasks) { task in
            Calendar.current.startOfDay(for: task.scheduledDate)
        }

        return grouped.keys
            .sorted()
            .map { date in
                let dayTasks = (grouped[date] ?? [])
                    .sorted { lhs, rhs in
                        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                        return lhs.title < rhs.title
                    }
                return EventTimelineDay(date: date, tasks: dayTasks)
            }
    }

    private func buildRevisionMilestones(for event: SpeakingEvent) -> [ScriptRevisionMilestone] {
        guard let versions = event.scriptVersions, !versions.isEmpty else { return [] }

        let sortedVersions = versions.sorted { $0.versionNumber < $1.versionNumber }
        var previousBestScore: Int?
        var milestones: [ScriptRevisionMilestone] = []

        for (index, version) in sortedVersions.enumerated() {
            let nextVersionDate = index < sortedVersions.count - 1 ? sortedVersions[index + 1].createdDate : Date.distantFuture
            let recordingsForVersion = linkedRecordings.filter { recording in
                recording.date >= version.createdDate && recording.date < nextVersionDate
            }
            let bestScore = recordingsForVersion.compactMap { $0.analysis?.speechScore.overall }.max()
            let delta: Int?
            if let bestScore, let previousBestScore {
                delta = bestScore - previousBestScore
            } else {
                delta = nil
            }
            if let bestScore {
                previousBestScore = bestScore
            }

            milestones.append(
                ScriptRevisionMilestone(
                    versionId: version.id,
                    versionNumber: version.versionNumber,
                    createdDate: version.createdDate,
                    wordCount: version.wordCount,
                    changeNote: version.changeNote ?? "Script revision checkpoint",
                    practiceCount: recordingsForVersion.count,
                    bestScore: bestScore,
                    scoreDeltaFromPrevious: delta
                )
            )
        }

        return milestones.reversed()
    }

    private func scheduleNotificationRefresh(tasks: [EventPrepTask]) {
        let signature = tasks.reduce(into: 0) { partialResult, task in
            partialResult ^= task.id.hashValue
            partialResult ^= Int(task.scheduledDate.timeIntervalSince1970)
            partialResult ^= task.isCompleted ? 1 : 0
        }
        guard signature != lastTaskNotificationSignature else { return }
        lastTaskNotificationSignature = signature

        notificationRefreshTask?.cancel()
        let tasksSnapshot = tasks
        notificationRefreshTask = Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await notificationService.checkPermission()
            await notificationService.refreshEventNotifications(tasks: tasksSnapshot)
        }
    }

    private func refreshScriptInsights(for event: SpeakingEvent) {
        guard let scriptText = event.scriptText, !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            scriptInsightsByRecordingId = [:]
            return
        }

        var insights: [UUID: ScriptPracticeInsight] = [:]
        for recording in linkedRecordings {
            guard let transcript = resolvedTranscript(for: recording) else { continue }
            if let insight = ScriptPracticeAnalyzer.analyze(script: scriptText, transcript: transcript) {
                insights[recording.id] = insight
            }
        }
        scriptInsightsByRecordingId = insights
    }

    private func resolvedTranscript(for recording: Recording) -> String? {
        let wordsTranscript = recording.transcriptionWords?
            .map(\.word)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let wordsTranscript, !wordsTranscript.isEmpty {
            return wordsTranscript
        }

        let fallbackText = recording.transcriptionText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackText, !fallbackText.isEmpty {
            return fallbackText
        }

        return nil
    }
}

struct EventTimelineDay: Identifiable {
    let date: Date
    let tasks: [EventPrepTask]

    var id: Date { date }

    var completedCount: Int {
        tasks.filter(\.isCompleted).count
    }

    var completionRatio: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedCount) / Double(tasks.count)
    }

    var estimatedMinutes: Int {
        tasks.reduce(0) { $0 + $1.estimatedMinutes }
    }

    var hasOverdueTasks: Bool {
        tasks.contains { $0.isOverdue }
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

struct ScriptRevisionMilestone: Identifiable {
    let versionId: UUID
    let versionNumber: Int
    let createdDate: Date
    let wordCount: Int
    let changeNote: String
    let practiceCount: Int
    let bestScore: Int?
    let scoreDeltaFromPrevious: Int?

    var id: UUID { versionId }
}
