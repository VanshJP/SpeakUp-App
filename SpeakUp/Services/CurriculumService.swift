import Foundation
import SwiftData

@Observable
class CurriculumService {
    var progress: CurriculumProgress?
    var phases: [CurriculumPhase] = DefaultCurriculum.phases
    private var modelContext: ModelContext?
    private var autoCompletedActivityIds: Set<String> = []
    /// The history scan in flight. A newer refresh (Learn reappearing right
    /// after a lesson take) cancels it, so only the newest result applies.
    @ObservationIgnored private var autoCompletionScan: Task<Void, Never>?

    @MainActor
    func loadProgress(context: ModelContext) {
        modelContext = context
        let descriptor = FetchDescriptor<CurriculumProgress>()
        if let existing = try? context.fetch(descriptor).first {
            progress = existing
        } else {
            let fresh = CurriculumProgress()
            context.insert(fresh)
            try? context.save()
            progress = fresh
        }
        refreshAutoCompletions(context: context)
    }

    var currentPhase: CurriculumPhase? {
        guard let progress else { return phases.first }
        return phases.first { $0.id == progress.currentPhaseId }
    }

    var currentLesson: CurriculumLesson? {
        guard let progress, let phase = currentPhase else {
            return phases.first?.lessons.first
        }
        return phase.lessons.first { $0.id == progress.currentLessonId }
    }

    var overallProgress: Double {
        guard let progress else { return 0 }
        let totalLessons = phases.reduce(0) { $0 + $1.lessons.count }
        guard totalLessons > 0 else { return 0 }
        return Double(progress.completedLessonIds.count) / Double(totalLessons)
    }

    var completedLessonsCount: Int {
        progress?.completedLessonIds.count ?? 0
    }

    var totalLessonsCount: Int {
        phases.reduce(0) { $0 + $1.lessons.count }
    }

    func isActivityCompleted(_ activityId: String) -> Bool {
        (progress?.completedActivityIds.contains(activityId) ?? false) || autoCompletedActivityIds.contains(activityId)
    }

    func isLessonCompleted(_ lessonId: String) -> Bool {
        if progress?.completedLessonIds.contains(lessonId) == true {
            return true
        }
        guard let lesson = lesson(for: lessonId) else { return false }
        return lesson.activities.allSatisfy { isActivityCompleted($0.id) }
    }

    @MainActor
    func completeActivity(_ activityId: String, context: ModelContext) {
        guard progress != nil else { return }
        recordActivityCompletion(activityId)
        try? context.save()
        refreshAutoCompletions(context: context)
    }

    /// Marks one activity done and settles what that finishes: its lesson,
    /// and the current-lesson pointer, which moves on once, to the next open
    /// lesson. This is the only thing that advances the pointer. The lesson
    /// page's "Next lesson" used to advance it a second time and skip a lesson.
    /// No I/O, so the rule is testable without a store.
    func recordActivityCompletion(_ activityId: String) {
        guard let progress else { return }
        if !progress.completedActivityIds.contains(activityId) {
            progress.completedActivityIds.append(activityId)
            progress.lastActivityDate = Date()
        }
        // The lesson this activity finishes completes now; what the history
        // scan infers lands a moment later.
        _ = synchronizeLessonCompletionAndProgress(progress: progress)
    }

    // MARK: - Auto Completion

    /// Scans history off the main actor, then applies what it infers.
    ///
    /// The scan decodes the analysis of every take ever recorded. It ran on
    /// the main context each time Learn appeared and after every lesson take,
    /// so the tab froze for longer the more someone had practised.
    @MainActor
    private func refreshAutoCompletions(context: ModelContext) {
        autoCompletionScan?.cancel()
        let container = context.container
        autoCompletionScan = Task { [weak self] in
            let signals = await Task.detached(priority: .userInitiated) {
                let background = ModelContext(container)
                let recordingDescriptor = FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.date)])
                let recordings = (try? background.fetch(recordingDescriptor)) ?? []
                // One decode pass over history: every `recording.analysis`
                // access re-decodes a JSON blob, so per-activity reads made
                // this O(activities × recordings). Activities evaluate against
                // the signals.
                return CurriculumSessionSignals.scan(recordings)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.applyAutoCompletions(signals, context: context)
        }
    }

    @MainActor
    private func applyAutoCompletions(_ signals: CurriculumSessionSignals, context: ModelContext) {
        guard let progress else { return }
        var didMutate = false
        let allActivities = phases.flatMap { $0.lessons }.flatMap { $0.activities }
        for activity in allActivities {
            guard inferCompletion(for: activity, signals: signals) else { continue }
            autoCompletedActivityIds.insert(activity.id)
            if !progress.completedActivityIds.contains(activity.id) {
                progress.completedActivityIds.append(activity.id)
                progress.lastActivityDate = Date()
                didMutate = true
            }
        }

        if synchronizeLessonCompletionAndProgress(progress: progress) {
            didMutate = true
        }

        if didMutate {
            try? context.save()
        }
    }

    private func synchronizeLessonCompletionAndProgress(progress: CurriculumProgress) -> Bool {
        var didMutate = false
        for lesson in phases.flatMap(\.lessons) {
            let allDone = lesson.activities.allSatisfy { isActivityCompleted($0.id) }
            if allDone && !progress.completedLessonIds.contains(lesson.id) {
                progress.completedLessonIds.append(lesson.id)
                didMutate = true
            }
        }

        if let currentLesson = lesson(for: progress.currentLessonId),
           currentLesson.activities.allSatisfy({ isActivityCompleted($0.id) }),
           let next = nextIncompleteLesson(after: currentLesson.id) {
            if progress.currentLessonId != next.lessonId {
                progress.currentPhaseId = next.phaseId
                progress.currentLessonId = next.lessonId
                didMutate = true
            }
        }

        return didMutate
    }

    private func nextIncompleteLesson(after lessonId: String) -> (phaseId: String, lessonId: String)? {
        let ordered = phases.flatMap { phase in
            phase.lessons.map { (phaseId: phase.id, lessonId: $0.id) }
        }
        guard let currentIndex = ordered.firstIndex(where: { $0.lessonId == lessonId }) else { return nil }
        guard currentIndex + 1 < ordered.count else { return nil }
        return ordered[(currentIndex + 1)...].first(where: { !isLessonCompleted($0.lessonId) })
    }

    func nextLessonAfter(_ lessonId: String) -> CurriculumLesson? {
        let allLessons = phases.flatMap(\.lessons)
        guard let idx = allLessons.firstIndex(where: { $0.id == lessonId }),
              idx + 1 < allLessons.count else { return nil }
        return allLessons[idx + 1]
    }

    private func lesson(for lessonId: String) -> CurriculumLesson? {
        phases.flatMap(\.lessons).first { $0.id == lessonId }
    }

    private func inferCompletion(for activity: CurriculumActivity, signals: CurriculumSessionSignals) -> Bool {
        switch activity.type {
        case .lesson:
            return false

        case .drill:
            if let mode = activity.drillMode {
                return CurriculumActivitySignalStore.completedDrillModes.contains(mode)
            }
            return false

        case .exercise:
            if let exerciseId = activity.exerciseId {
                return CurriculumActivitySignalStore.completedExerciseIDs.contains(exerciseId)
            }
            return false

        case .review:
            if activity.id == "w4_l4_a1" || activity.id == "w4_l3_a2" {
                return signals.analyzedCount >= 2
            }
            return signals.recordingCount > 0

        case .practice:
            return inferPracticeCompletion(for: activity, signals: signals)
        }
    }

    private func inferPracticeCompletion(
        for activity: CurriculumActivity,
        signals: CurriculumSessionSignals
    ) -> Bool {
        switch activity.id {
        case "w1_l1_a2":
            return signals.durationReached(50)
        case "w1_l2_a2":
            return signals.hasAnyFiller
        case "w1_l3_a2":
            return signals.hasPositivePace
        case "w2_l1_a2":
            return CurriculumActivitySignalStore.completedExerciseIDs.contains("box_breathing") && signals.recordingCount > 0
        case "w2_l2_a2":
            return signals.hasFocusedTake
        case "w2_l3_a2":
            return signals.hasOnPaceTake
        case "w3_l1_a2":
            return signals.hasPrepFramework
        case "w3_l2_a2":
            return signals.hasStarFramework
        case "w3_l3_a2":
            return signals.hasDeliberatePauses
        case "w3_l4_a2":
            return signals.hasStructuredTake
        case "w4_l2_a2":
            return signals.hasPromptedTake
        case "w4_l3_a1":
            return signals.durationReached(170)
        default:
            let requiredSeconds = requiredDurationSeconds(in: "\(activity.title) \(activity.description)")
            if requiredSeconds > 0 {
                return signals.durationReached(requiredSeconds - 5)
            }
            if activity.title.localizedCaseInsensitiveContains("read aloud") {
                return CurriculumActivitySignalStore.hasCompletedReadAloud
            }
            return signals.recordingCount > 0
        }
    }

    private func requiredDurationSeconds(in text: String) -> TimeInterval {
        let lowered = text.lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"(\\d+)\s*[- ]?\s*(second|seconds|sec|minute|minutes|min)\b"#) else {
            return 0
        }
        let range = NSRange(lowered.startIndex..., in: lowered)
        guard let match = regex.firstMatch(in: lowered, range: range),
              let valueRange = Range(match.range(at: 1), in: lowered),
              let unitRange = Range(match.range(at: 2), in: lowered),
              let value = Double(lowered[valueRange]) else { return 0 }

        let unit = String(lowered[unitRange])
        if unit.hasPrefix("min") {
            return value * 60
        }
        return value
    }
}

// MARK: - Session Signals

/// Everything auto-completion infers from practice history, projected in one
/// pass. `Recording.analysis` is a Codable blob that re-decodes on every
/// access - reading it per activity made a refresh O(activities × sessions).
nonisolated struct CurriculumSessionSignals: Sendable {
    private(set) var recordingCount = 0
    private(set) var analyzedCount = 0
    private(set) var longestDuration: TimeInterval = 0
    private(set) var hasAnyFiller = false
    private(set) var hasPositivePace = false
    /// A take with at least 25 words and at most 2 fillers.
    private(set) var hasFocusedTake = false
    /// A take with at least 30 words at 130-170 wpm.
    private(set) var hasOnPaceTake = false
    private(set) var hasPrepFramework = false
    private(set) var hasStarFramework = false
    private(set) var hasDeliberatePauses = false
    /// At least 3 sentences, no more than 2 left incomplete.
    private(set) var hasStructuredTake = false
    private(set) var hasPromptedTake = false

    static func scan(_ recordings: [Recording]) -> CurriculumSessionSignals {
        var signals = CurriculumSessionSignals()
        signals.recordingCount = recordings.count

        for recording in recordings {
            // The single decode this session contributes to the refresh.
            let analysis = recording.analysis
            if analysis != nil {
                signals.analyzedCount += 1
            }
            if recording.actualDuration > signals.longestDuration {
                signals.longestDuration = recording.actualDuration
            }
            if (analysis?.totalFillerCount ?? 0) > 0 {
                signals.hasAnyFiller = true
            }
            if (analysis?.wordsPerMinute ?? 0) > 0 {
                signals.hasPositivePace = true
            }
            if let analysis, analysis.totalWords >= 25 && analysis.totalFillerCount <= 2 {
                signals.hasFocusedTake = true
            }
            if let analysis,
               analysis.totalWords >= 30,
               analysis.speechScore.subscores.pace >= 70 {
                signals.hasOnPaceTake = true
            }
            if (analysis?.pauseCount ?? 0) >= 3 {
                signals.hasDeliberatePauses = true
            }
            if let sentences = analysis?.sentenceAnalysis,
               sentences.totalSentences >= 3, sentences.incompleteSentences <= 2 {
                signals.hasStructuredTake = true
            }
            let framework = recording.frameworkUsed ?? ""
            if framework.localizedCaseInsensitiveContains("prep") {
                signals.hasPrepFramework = true
            }
            if framework.localizedCaseInsensitiveContains("star") {
                signals.hasStarFramework = true
            }
            if recording.prompt != nil {
                signals.hasPromptedTake = true
            }
        }

        return signals
    }

    /// Guarded on having any history so an empty library never reads as "a
    /// take under every threshold" once `seconds` dips to zero or below.
    func durationReached(_ seconds: TimeInterval) -> Bool {
        recordingCount > 0 && longestDuration >= seconds
    }
}
