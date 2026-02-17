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

    @MainActor
    func completeActivity(_ activityId: String, context: ModelContext) {
        service.completeActivity(activityId, context: context)
    }
}
