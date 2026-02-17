import Foundation
import SwiftData

@Observable
class CurriculumService {
    var progress: CurriculumProgress?
    var phases: [CurriculumPhase] = DefaultCurriculum.phases

    @MainActor
    func loadProgress(context: ModelContext) {
        let descriptor = FetchDescriptor<CurriculumProgress>()
        progress = try? context.fetch(descriptor).first
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
        progress?.completedActivityIds.contains(activityId) ?? false
    }

    func isLessonCompleted(_ lessonId: String) -> Bool {
        progress?.completedLessonIds.contains(lessonId) ?? false
    }

    @MainActor
    func completeActivity(_ activityId: String, context: ModelContext) {
        guard let progress else { return }
        if !progress.completedActivityIds.contains(activityId) {
            progress.completedActivityIds.append(activityId)
            progress.lastActivityDate = Date()
        }

        // Check if current lesson is now complete
        if let lesson = currentLesson {
            let allActivitiesCompleted = lesson.activities.allSatisfy { activity in
                progress.completedActivityIds.contains(activity.id)
            }
            if allActivitiesCompleted && !progress.completedLessonIds.contains(lesson.id) {
                progress.completedLessonIds.append(lesson.id)
                advanceToNextLesson(context: context)
            }
        }

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
}
