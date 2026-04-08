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
    var content: LessonContent?
    var targetDuration: Int?
    var frameworkHint: String?

    // MARK: - Factory Methods

    static func lesson(id: String, title: String, description: String, content: LessonContent) -> CurriculumActivity {
        CurriculumActivity(id: id, type: .lesson, title: title, description: description, content: content)
    }

    static func practice(id: String, title: String, description: String, duration: Int, framework: String? = nil) -> CurriculumActivity {
        CurriculumActivity(id: id, type: .practice, title: title, description: description, targetDuration: duration, frameworkHint: framework)
    }

    static func drill(id: String, title: String, description: String, mode: String) -> CurriculumActivity {
        CurriculumActivity(id: id, type: .drill, title: title, description: description, drillMode: mode)
    }

    static func exercise(id: String, title: String, description: String, exerciseId: String) -> CurriculumActivity {
        CurriculumActivity(id: id, type: .exercise, title: title, description: description, exerciseId: exerciseId)
    }

    static func review(id: String, title: String, description: String) -> CurriculumActivity {
        CurriculumActivity(id: id, type: .review, title: title, description: description)
    }
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
