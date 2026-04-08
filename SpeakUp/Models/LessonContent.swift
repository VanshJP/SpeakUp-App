import Foundation

enum LessonSectionType: String, Codable {
    case concepts
    case tip
    case example
    case keyTakeaway
    case callout
}

struct LessonSection: Codable, Identifiable {
    let id: String
    let type: LessonSectionType
    let title: String?
    let body: String
    let icon: String?

    // MARK: - Factory Methods

    static func concepts(title: String, body: String, icon: String = "book") -> LessonSection {
        LessonSection(id: UUID().uuidString, type: .concepts, title: title, body: body, icon: icon)
    }

    static func tip(_ body: String, title: String = "Pro Tip") -> LessonSection {
        LessonSection(id: UUID().uuidString, type: .tip, title: title, body: body, icon: "lightbulb.fill")
    }

    static func example(title: String = "Example", body: String) -> LessonSection {
        LessonSection(id: UUID().uuidString, type: .example, title: title, body: body, icon: "quote.opening")
    }

    static func keyTakeaway(_ body: String) -> LessonSection {
        LessonSection(id: UUID().uuidString, type: .keyTakeaway, title: "Key Takeaway", body: body, icon: "star.fill")
    }

    static func callout(title: String, body: String, icon: String = "info.circle.fill") -> LessonSection {
        LessonSection(id: UUID().uuidString, type: .callout, title: title, body: body, icon: icon)
    }
}

struct LessonContent: Codable {
    let sections: [LessonSection]
}
