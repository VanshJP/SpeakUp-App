import Testing
@testable import SpeakUp

@Suite("Curriculum studio plan")
struct CurriculumStudioPlanTests {
    @Test("Studio plan keeps first-seen activity roles in order")
    func studioPlanUniquesInOrder() {
        let lesson = CurriculumLesson(
            id: "test_plan",
            title: "Plan Test",
            objective: "Prove plan order.",
            activities: [
                .lesson(
                    id: "a1",
                    title: "Read",
                    description: "Concept",
                    content: LessonContent(sections: [
                        .keyTakeaway("Takeaway")
                    ])
                ),
                .drill(id: "a2", title: "Drill", description: "Reps", mode: "fillerElimination"),
                .practice(id: "a3", title: "Speak", description: "Take", duration: 60),
                .practice(id: "a4", title: "Speak again", description: "Another take", duration: 30),
            ]
        )

        #expect(lesson.studioPlan == [.lesson, .drill, .practice])
        #expect(lesson.practiceSeconds == 90)
    }

    @Test("Seeded lessons expose a non-empty studio plan")
    func seededLessonsHavePlans() {
        for lesson in DefaultCurriculum.phases.flatMap(\.lessons) {
            #expect(!lesson.studioPlan.isEmpty, "Empty studio plan for \(lesson.id)")
        }
    }
}
