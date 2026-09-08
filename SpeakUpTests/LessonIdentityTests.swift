import Testing
@testable import SpeakUp

@Suite("Lesson identity")
struct LessonIdentityTests {
    @Test("Every seeded lesson has a catalog identity")
    func catalogCoversDefaultCurriculum() {
        let lessonIds = DefaultCurriculum.phases.flatMap(\.lessons).map(\.id)
        #expect(!lessonIds.isEmpty)

        for id in lessonIds {
            #expect(LessonIdentity.catalog[id] != nil, "Missing LessonIdentity for \(id)")
        }
    }

    @Test("Catalog has no orphan ids outside the seed")
    func catalogHasNoOrphans() {
        let seeded = Set(DefaultCurriculum.phases.flatMap(\.lessons).map(\.id))
        for id in LessonIdentity.catalog.keys {
            #expect(seeded.contains(id), "Orphan LessonIdentity for \(id)")
        }
    }
}
