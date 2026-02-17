import Foundation

enum CurriculumActivityType: String, Codable {
    case lesson
    case practice
    case drill
    case exercise
    case review
}

struct CurriculumActivity: Identifiable, Codable {
    let id: String
    let type: CurriculumActivityType
    let title: String
    let description: String
    var targetMetric: String?
    var targetValue: Int?
    var drillMode: String?
    var exerciseId: String?
}

struct CurriculumLesson: Identifiable, Codable {
    let id: String
    let title: String
    let objective: String
    let activities: [CurriculumActivity]
    var isCompleted: Bool = false
}

struct CurriculumPhase: Identifiable, Codable {
    let id: String
    let week: Int
    let title: String
    let description: String
    let lessons: [CurriculumLesson]
}
