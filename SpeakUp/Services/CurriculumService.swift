import Foundation
import SwiftData

@Observable
class CurriculumService {
    var progress: CurriculumProgress?
    var phases: [CurriculumPhase] = DefaultCurriculum.phases
    private var modelContext: ModelContext?
    private var autoCompletedActivityIds: Set<String> = []

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
        guard let progress else { return }
        if !progress.completedActivityIds.contains(activityId) {
            progress.completedActivityIds.append(activityId)
            progress.lastActivityDate = Date()
        }
        refreshAutoCompletions(context: context)
        try? context.save()
    }

    @MainActor
    func advanceToNextLesson(context: ModelContext) {
        guard let progress, let currentPhase = currentPhase else { return }

        let lessons = currentPhase.lessons
        if let currentIndex = lessons.firstIndex(where: { $0.id == progress.currentLessonId }),
           currentIndex + 1 < lessons.count {
            progress.currentLessonId = lessons[currentIndex + 1].id
        } else {
            // Move to next phase
            if let phaseIndex = phases.firstIndex(where: { $0.id == currentPhase.id }),
               phaseIndex + 1 < phases.count {
                let nextPhase = phases[phaseIndex + 1]
                progress.currentPhaseId = nextPhase.id
                progress.currentLessonId = nextPhase.lessons.first?.id ?? ""
            }
        }

        try? context.save()
    }

    // MARK: - Auto Completion

    @MainActor
    private func refreshAutoCompletions(context: ModelContext) {
        guard let progress else { return }
        let recordingDescriptor = FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.date)])
        let recordings = (try? context.fetch(recordingDescriptor)) ?? []

        var didMutate = false
        let allActivities = phases.flatMap { $0.lessons }.flatMap { $0.activities }
        for activity in allActivities {
            guard inferCompletion(for: activity, recordings: recordings) else { continue }
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

    private func inferCompletion(for activity: CurriculumActivity, recordings: [Recording]) -> Bool {
        let analyzed = recordings.compactMap(\.analysis)

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
                return analyzed.count >= 2
            }
            return !recordings.isEmpty

        case .practice:
            return inferPracticeCompletion(for: activity, recordings: recordings, analyzedCount: analyzed.count)
        }
    }

    private func inferPracticeCompletion(
        for activity: CurriculumActivity,
        recordings: [Recording],
        analyzedCount: Int
    ) -> Bool {
        switch activity.id {
        case "w1_l1_a2":
            return recordings.contains { $0.actualDuration >= 50 }
        case "w1_l2_a2":
            return recordings.contains { ($0.analysis?.totalFillerCount ?? 0) > 0 }
        case "w1_l3_a2":
            return recordings.contains { ($0.analysis?.wordsPerMinute ?? 0) > 0 }
        case "w2_l1_a2":
            return CurriculumActivitySignalStore.completedExerciseIDs.contains("box_breathing") && !recordings.isEmpty
        case "w2_l2_a2":
            return recordings.contains {
                guard let analysis = $0.analysis else { return false }
                return analysis.totalWords >= 25 && analysis.totalFillerCount <= 2
            }
        case "w2_l3_a2":
            return recordings.contains {
                guard let analysis = $0.analysis else { return false }
                return analysis.totalWords >= 30 && (130...170).contains(Int(analysis.wordsPerMinute.rounded()))
            }
        case "w3_l1_a2":
            return recordings.contains { ($0.frameworkUsed ?? "").localizedCaseInsensitiveContains("prep") } || analyzedCount > 0
        case "w3_l2_a2":
            return recordings.contains { ($0.frameworkUsed ?? "").localizedCaseInsensitiveContains("star") } || analyzedCount > 0
        case "w3_l3_a2":
            return recordings.contains { ($0.analysis?.pauseCount ?? 0) >= 3 }
        case "w3_l4_a2":
            return recordings.contains {
                guard let sentenceAnalysis = $0.analysis?.sentenceAnalysis else { return false }
                return sentenceAnalysis.totalSentences >= 3 && sentenceAnalysis.incompleteSentences <= 2
            }
        case "w4_l2_a2":
            return recordings.contains { $0.prompt != nil }
        case "w4_l3_a1":
            return recordings.contains { $0.actualDuration >= 170 }
        default:
            let requiredSeconds = requiredDurationSeconds(in: "\(activity.title) \(activity.description)")
            if requiredSeconds > 0 {
                return recordings.contains { $0.actualDuration >= requiredSeconds - 5 }
            }
            if activity.title.localizedCaseInsensitiveContains("read aloud") {
                return CurriculumActivitySignalStore.hasCompletedReadAloud
            }
            return !recordings.isEmpty
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
