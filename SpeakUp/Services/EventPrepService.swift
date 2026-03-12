import Foundation
import SwiftData

@Observable
class EventPrepService {

    // MARK: - Script Parsing

    static func parseScriptIntoSections(_ script: String, targetDurationMinutes: Int) -> [ScriptSection] {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let totalWords = trimmed.split(separator: " ").count
        guard totalWords >= 10 else {
            return [ScriptSection(
                index: 0,
                title: "Full Script",
                text: trimmed,
                wordCount: totalWords,
                targetDurationSeconds: targetDurationMinutes * 60
            )]
        }

        let targetWPM = max(1, Double(totalWords) / Double(max(1, targetDurationMinutes)))

        // Split on double newlines for paragraph boundaries
        var paragraphs = trimmed.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // If fewer than 3 paragraphs, split by sentence groups
        if paragraphs.count < 3 && totalWords >= 200 {
            paragraphs = splitBySentenceGroups(trimmed, targetCount: min(7, max(3, totalWords / 80)))
        }

        // If script is very short, single section
        if totalWords < 200 && paragraphs.count < 3 {
            return [ScriptSection(
                index: 0,
                title: "Full Script",
                text: trimmed,
                wordCount: totalWords,
                targetDurationSeconds: targetDurationMinutes * 60
            )]
        }

        // Cap at 7 sections
        if paragraphs.count > 7 {
            paragraphs = mergeParagraphs(paragraphs, targetCount: 7)
        }

        return paragraphs.enumerated().map { index, text in
            let wordCount = text.split(separator: " ").count
            let targetSeconds = Int(Double(wordCount) / targetWPM * 60)
            let title: String
            if index == 0 {
                title = "Opening"
            } else if index == paragraphs.count - 1 {
                title = "Closing"
            } else {
                title = "Section \(index + 1)"
            }
            return ScriptSection(
                index: index,
                title: title,
                text: text,
                wordCount: wordCount,
                targetDurationSeconds: max(10, targetSeconds)
            )
        }
    }

    private static func splitBySentenceGroups(_ text: String, targetCount: Int) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard sentences.count >= targetCount else { return sentences.isEmpty ? [text] : sentences }

        let groupSize = max(1, sentences.count / targetCount)
        var groups: [String] = []
        var current: [String] = []

        for sentence in sentences {
            current.append(sentence)
            if current.count >= groupSize && groups.count < targetCount - 1 {
                groups.append(current.joined(separator: ". ") + ".")
                current = []
            }
        }
        if !current.isEmpty {
            groups.append(current.joined(separator: ". ") + ".")
        }
        return groups
    }

    private static func mergeParagraphs(_ paragraphs: [String], targetCount: Int) -> [String] {
        guard paragraphs.count > targetCount else { return paragraphs }
        var result = paragraphs
        while result.count > targetCount {
            // Find shortest adjacent pair and merge
            var minLen = Int.max
            var minIdx = 0
            for i in 0..<(result.count - 1) {
                let combined = result[i].count + result[i + 1].count
                if combined < minLen {
                    minLen = combined
                    minIdx = i
                }
            }
            result[minIdx] = result[minIdx] + "\n\n" + result[minIdx + 1]
            result.remove(at: minIdx + 1)
        }
        return result
    }

    // MARK: - Plan Generation

    @MainActor
    func generatePrepPlan(for event: SpeakingEvent, context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let eventDay = calendar.startOfDay(for: event.eventDate)
        let totalDays = max(1, calendar.dateComponents([.day], from: today, to: eventDay).day ?? 1)

        // Clear existing tasks for this event
        let eventId = event.id
        let descriptor = FetchDescriptor<EventPrepTask>(
            predicate: #Predicate { $0.eventId == eventId }
        )
        if let existing = try? context.fetch(descriptor) {
            for task in existing {
                context.delete(task)
            }
        }

        var tasks: [EventPrepTask] = []
        let hasSections = event.scriptSections != nil && !(event.scriptSections?.isEmpty ?? true)
        let sectionCount = event.scriptSections?.count ?? 0

        for dayOffset in 0..<totalDays {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }

            let daysRemaining = totalDays - dayOffset
            let percentRemaining = Double(daysRemaining) / Double(totalDays)
            let phase: EventPrepPhase
            if percentRemaining > 0.6 { phase = .foundation }
            else if percentRemaining > 0.2 { phase = .building }
            else { phase = .performance }

            let tasksForDay = determineTaskCount(phase: phase, daysRemaining: daysRemaining)

            for taskIndex in 0..<tasksForDay {
                let taskType = pickTaskType(
                    phase: phase,
                    dayOffset: dayOffset,
                    taskIndex: taskIndex,
                    totalDays: totalDays,
                    daysRemaining: daysRemaining,
                    hasSections: hasSections,
                    sectionCount: sectionCount
                )

                let sectionIdx = pickSectionIndex(
                    taskType: taskType,
                    dayOffset: dayOffset,
                    sectionCount: sectionCount
                )

                let priority = phase == .performance ? 3 : (phase == .building ? 2 : 1)

                let task = EventPrepTask(
                    eventId: event.id,
                    scheduledDate: date,
                    taskType: taskType.rawValue,
                    title: taskType.displayName,
                    taskDescription: taskDescription(for: taskType, sectionIndex: sectionIdx, sections: event.scriptSections),
                    targetSectionIndex: sectionIdx,
                    drillMode: taskType.associatedDrillMode,
                    priority: priority
                )
                tasks.append(task)
            }
        }

        // Final day: ensure dayOfPrep
        if let lastTask = tasks.last, lastTask.taskType != EventPrepTaskType.dayOfPrep.rawValue {
            let dayOfTask = EventPrepTask(
                eventId: event.id,
                scheduledDate: eventDay,
                taskType: EventPrepTaskType.dayOfPrep.rawValue,
                title: "Day-of Prep",
                taskDescription: "Breathing exercise + affirmation. You're ready!",
                priority: 3
            )
            tasks.append(dayOfTask)
        }

        for task in tasks {
            context.insert(task)
        }
        try? context.save()
    }

    private func determineTaskCount(phase: EventPrepPhase, daysRemaining: Int) -> Int {
        switch phase {
        case .foundation:
            // 2-3 tasks per week = roughly every 2-3 days
            return daysRemaining % 3 == 0 ? 1 : 0
        case .building:
            return 1
        case .performance:
            return daysRemaining <= 3 ? 2 : 1
        }
    }

    private func pickTaskType(
        phase: EventPrepPhase,
        dayOffset: Int,
        taskIndex: Int,
        totalDays: Int,
        daysRemaining: Int,
        hasSections: Bool,
        sectionCount: Int
    ) -> EventPrepTaskType {
        // Day of event
        if daysRemaining <= 1 {
            return taskIndex == 0 ? .dayOfPrep : .confidenceExercise
        }

        switch phase {
        case .foundation:
            let options: [EventPrepTaskType] = hasSections
                ? [.scriptReview, .warmUp, .confidenceExercise, .scriptReview]
                : [.warmUp, .confidenceExercise, .warmUp, .impromptuVariation]
            return options[dayOffset % options.count]

        case .building:
            if taskIndex > 0 { return .confidenceExercise }
            // Cycle: section practice, drill, full rehearsal, section practice, drill...
            let cycle = dayOffset % 5
            switch cycle {
            case 0: return hasSections ? .sectionPractice : .fullRehearsal
            case 1: return .fillerDrill
            case 2: return .fullRehearsal
            case 3: return hasSections ? .sectionPractice : .paceDrill
            case 4: return .pauseDrill
            default: return .fullRehearsal
            }

        case .performance:
            if taskIndex > 0 { return .confidenceExercise }
            // Alternate full rehearsals and section work
            return dayOffset % 2 == 0 ? .fullRehearsal : (hasSections ? .sectionPractice : .impromptuVariation)
        }
    }

    private func pickSectionIndex(taskType: EventPrepTaskType, dayOffset: Int, sectionCount: Int) -> Int? {
        guard taskType == .sectionPractice || taskType == .scriptReview else { return nil }
        guard sectionCount > 0 else { return nil }
        return dayOffset % sectionCount
    }

    private func taskDescription(for type: EventPrepTaskType, sectionIndex: Int?, sections: [ScriptSection]?) -> String {
        switch type {
        case .fullRehearsal:
            return "Practice your entire speech from start to finish."
        case .sectionPractice:
            if let idx = sectionIndex, let sections, idx < sections.count {
                return "Practice \"\(sections[idx].title)\" — focus on smooth delivery."
            }
            return "Practice a specific section of your speech."
        case .fillerDrill:
            return "15-second burst — speak with zero filler words."
        case .paceDrill:
            return "60 seconds — match a steady, natural pace."
        case .pauseDrill:
            return "45 seconds — practice deliberate pauses."
        case .warmUp:
            return "Breathing and vocal exercises to prepare your voice."
        case .confidenceExercise:
            return "Visualization or calming exercise to build confidence."
        case .scriptReview:
            if let idx = sectionIndex, let sections, idx < sections.count {
                return "Re-read and internalize \"\(sections[idx].title)\"."
            }
            return "Re-read your script to strengthen memorization."
        case .impromptuVariation:
            return "Speak on your topic without looking at the script."
        case .dayOfPrep:
            return "Breathing exercise + affirmation. You're ready!"
        }
    }

    // MARK: - Readiness Score

    @MainActor
    func computeReadinessScore(for event: SpeakingEvent, context: ModelContext) -> Int {
        let eventId = event.id
        let taskDescriptor = FetchDescriptor<EventPrepTask>(
            predicate: #Predicate { $0.eventId == eventId }
        )
        let tasks = (try? context.fetch(taskDescriptor)) ?? []

        let recordingDescriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.eventId == eventId }
        )
        let recordings = (try? context.fetch(recordingDescriptor)) ?? []

        // 1. Script mastery (40% if script exists)
        var scriptMastery: Double = 0
        var scriptWeight: Double = 0
        if let sections = event.scriptSections, !sections.isEmpty {
            scriptWeight = 0.4
            let totalMastery = sections.reduce(0) { $0 + $1.masteryScore }
            scriptMastery = Double(totalMastery) / Double(sections.count)
        }

        // 2. Task completion (30%)
        let totalTasks = tasks.count
        let completedTasks = tasks.filter(\.isCompleted).count
        let taskCompletion = totalTasks > 0 ? Double(completedTasks) / Double(totalTasks) * 100.0 : 0

        // 3. Recent recording scores (20%)
        let recentScores = recordings
            .sorted { $0.date > $1.date }
            .prefix(5)
            .compactMap { $0.analysis.map { Double($0.speechScore.overall) } }
        let avgScore = recentScores.isEmpty ? 0.0 : recentScores.reduce(0.0, +) / Double(recentScores.count)

        // 4. Confidence exercises (10%)
        let confidenceTasks = tasks.filter { $0.taskType == EventPrepTaskType.confidenceExercise.rawValue }
        let completedConfidence = confidenceTasks.filter(\.isCompleted).count
        let confidenceScore = confidenceTasks.isEmpty ? 0.0 : Double(completedConfidence) / Double(confidenceTasks.count) * 100.0

        // Redistribute weights if no script
        let remainingWeight = 1.0 - scriptWeight
        let taskWeight = scriptWeight > 0 ? 0.3 : 0.3 / remainingWeight * 1.0
        let recordingWeight = scriptWeight > 0 ? 0.2 : 0.2 / remainingWeight * 1.0
        let confidenceWeight = scriptWeight > 0 ? 0.1 : 0.1 / remainingWeight * 1.0

        let normalizedWeights: (Double, Double, Double, Double)
        if scriptWeight > 0 {
            normalizedWeights = (scriptWeight, 0.3, 0.2, 0.1)
        } else {
            // Redistribute: 50% tasks, 33% recordings, 17% confidence
            normalizedWeights = (0, 0.5, 0.33, 0.17)
        }

        let score = scriptMastery * normalizedWeights.0
            + taskCompletion * normalizedWeights.1
            + avgScore * normalizedWeights.2
            + confidenceScore * normalizedWeights.3

        return min(100, max(0, Int(score)))
    }

    // MARK: - Task Completion

    @MainActor
    func completeTask(_ task: EventPrepTask, recording: Recording? = nil, context: ModelContext) {
        task.isCompleted = true
        task.completedDate = Date()
        task.linkedRecordingId = recording?.id

        // Update event stats
        let eventId = task.eventId
        let eventDescriptor = FetchDescriptor<SpeakingEvent>(
            predicate: #Predicate { $0.id == eventId }
        )
        if let event = try? context.fetch(eventDescriptor).first {
            event.totalPracticeCount += 1
            event.lastPracticeDate = Date()

            // Update section mastery if applicable
            if let sectionIdx = task.targetSectionIndex,
               let recording,
               let analysis = recording.analysis,
               var sections = event.scriptSections,
               sectionIdx < sections.count {
                let score = Double(analysis.speechScore.overall)
                sections[sectionIdx].practiceCount += 1
                sections[sectionIdx].lastPracticeDate = Date()
                // Weighted update: 60% previous, 40% new
                let prev = Double(sections[sectionIdx].masteryScore)
                sections[sectionIdx].masteryScore = Int(prev * 0.6 + score * 0.4)
                event.scriptSections = sections
            }

            // Recompute readiness
            event.readinessScore = computeReadinessScore(for: event, context: context)
        }

        try? context.save()
    }

    // MARK: - Next Task

    @MainActor
    func nextTask(for eventId: UUID, context: ModelContext) -> EventPrepTask? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<EventPrepTask>(
            predicate: #Predicate { $0.eventId == eventId && !$0.isCompleted },
            sortBy: [SortDescriptor(\.scheduledDate)]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        // Return first task that's today or in the past (overdue), or next upcoming
        return tasks.first
    }

    // MARK: - Upcoming Events

    @MainActor
    func nearestUpcomingEvent(context: ModelContext) -> SpeakingEvent? {
        let now = Date()
        let descriptor = FetchDescriptor<SpeakingEvent>(
            predicate: #Predicate { !$0.isArchived && $0.eventDate >= now },
            sortBy: [SortDescriptor(\.eventDate)]
        )
        return try? context.fetch(descriptor).first
    }
}
