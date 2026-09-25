import Testing
@testable import SpeakUp

/// The current-lesson pointer moves once per finished lesson, and only from
/// completion. The lesson page's "Next lesson" used to advance it a second
/// time, which skipped a lesson and put a locked one on the Studio card.
///
/// Progress here is unsaved: these rules touch no store, and any
/// `ModelContainer` fetch traps in the current simulator test runner.
@MainActor
@Suite("Curriculum progression")
struct CurriculumProgressionTests {
    private func makeService() -> CurriculumService {
        let service = CurriculumService()
        service.progress = CurriculumProgress()
        return service
    }

    private func finish(_ lesson: CurriculumLesson, in service: CurriculumService) {
        for activity in lesson.activities {
            service.recordActivityCompletion(activity.id)
        }
    }

    @Test("Finishing the current lesson moves the pointer to the next lesson exactly once")
    func finishingALessonAdvancesOnce() throws {
        let service = makeService()
        let progress = try #require(service.progress)
        let lessons = service.phases.flatMap(\.lessons)
        let first = lessons[0]
        let second = lessons[1]
        #expect(progress.currentLessonId == first.id)

        finish(first, in: service)

        #expect(service.isLessonCompleted(first.id))
        #expect(progress.currentLessonId == second.id)
        // The page swaps in the lesson the pointer now names.
        #expect(service.nextLessonAfter(first.id)?.id == second.id)

        // Settling again - a repeat take, the history scan - never moves it on.
        finish(first, in: service)
        #expect(progress.currentLessonId == second.id)
    }

    @Test("Finishing a week's last lesson moves the pointer into the next week")
    func finishingAWeekCrossesIntoTheNext() {
        let service = makeService()
        let firstWeek = service.phases[0]
        let secondWeek = service.phases[1]

        for lesson in firstWeek.lessons {
            finish(lesson, in: service)
        }

        #expect(service.progress?.currentPhaseId == secondWeek.id)
        #expect(service.progress?.currentLessonId == secondWeek.lessons.first?.id)
    }

    @Test("A lesson opens on its first open step, and a finished one on its practice step")
    func openingStep() throws {
        let viewModel = CurriculumViewModel()
        viewModel.service.progress = CurriculumProgress()
        let lesson = viewModel.phases[0].lessons[0]
        let practiceIndex = try #require(lesson.activities.firstIndex { $0.type == .practice })
        #expect(viewModel.initialStepIndex(for: lesson) == 0)

        finish(lesson, in: viewModel.service)

        #expect(viewModel.firstOpenStepIndex(for: lesson) == nil)
        #expect(viewModel.initialStepIndex(for: lesson) == practiceIndex)
    }
}
