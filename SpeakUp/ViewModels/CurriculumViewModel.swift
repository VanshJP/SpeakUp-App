import Foundation
import SwiftData

@Observable
class CurriculumViewModel {
    let service = CurriculumService()

    var phases: [CurriculumPhase] { service.phases }
    var currentPhase: CurriculumPhase? { service.currentPhase }
    var currentLesson: CurriculumLesson? { service.currentLesson }
    var overallProgress: Double { service.overallProgress }
    var completedLessonsCount: Int { service.completedLessonsCount }
    var totalLessonsCount: Int { service.totalLessonsCount }

    @MainActor
    func loadProgress(context: ModelContext) {
        service.loadProgress(context: context)
    }

    func isActivityCompleted(_ activityId: String) -> Bool {
        service.isActivityCompleted(activityId)
    }

    func isLessonCompleted(_ lessonId: String) -> Bool {
        service.isLessonCompleted(lessonId)
    }

    /// Also moves the current lesson on when this finishes it - see
    /// `CurriculumService.recordActivityCompletion`.
    @MainActor
    func completeActivity(_ activityId: String, context: ModelContext) {
        service.completeActivity(activityId, context: context)
    }

    /// The first step not done yet, in teaching order.
    func firstOpenStepIndex(for lesson: CurriculumLesson) -> Int? {
        lesson.activities.firstIndex { !isActivityCompleted($0.id) }
    }

    /// Where a lesson opens: its first open step - or, once the lesson is
    /// finished, its speaking step. Reopening a finished lesson ("Prove it
    /// again", "Practice again") is to speak it again, not to reread it; the
    /// reading stays one tap away in the title menu.
    func initialStepIndex(for lesson: CurriculumLesson) -> Int {
        if isLessonCompleted(lesson.id) {
            return lesson.activities.firstIndex { $0.type == .practice } ?? 0
        }
        return firstOpenStepIndex(for: lesson) ?? 0
    }

    func isLessonAccessible(_ lesson: CurriculumLesson, in phase: CurriculumPhase) -> Bool {
        // Completed lessons are always accessible (for review)
        if isLessonCompleted(lesson.id) { return true }

        // Phase gate: previous phase must be fully complete
        if let phaseIndex = phases.firstIndex(where: { $0.id == phase.id }), phaseIndex > 0 {
            let previousPhase = phases[phaseIndex - 1]
            if !previousPhase.lessons.allSatisfy({ isLessonCompleted($0.id) }) {
                return false
            }
        }

        // Lesson gate: previous lesson in same phase must be complete
        if let lessonIndex = phase.lessons.firstIndex(where: { $0.id == lesson.id }), lessonIndex > 0 {
            if !isLessonCompleted(phase.lessons[lessonIndex - 1].id) {
                return false
            }
        }

        return true
    }

    func nextLesson(after lessonId: String) -> CurriculumLesson? {
        service.nextLessonAfter(lessonId)
    }
}
