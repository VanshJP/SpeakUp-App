import Foundation
import SwiftData

@Model
final class CurriculumProgress {
    var id: String = UUID().uuidString
    var currentPhaseId: String = "week1"
    var currentLessonId: String = "w1_l1"
    var completedLessonIds: [String] = []
    var completedActivityIds: [String] = []
    var startDate: Date = Date()
    var lastActivityDate: Date?

    init() {}
}
