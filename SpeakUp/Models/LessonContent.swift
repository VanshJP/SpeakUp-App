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
    /// One block per line. A line that opens on `**Term**` is a point - the
    /// term over its detail (`LessonLine`); every other line is a paragraph.
    let body: String
    let icon: String?

    // MARK: - Factory Methods

    /// No icon: a reading section is headed by its title alone, like every
    /// section header in the app (`GlassSectionHeader` is text only).
    static func concepts(title: String, body: String) -> LessonSection {
        LessonSection(id: UUID().uuidString, type: .concepts, title: title, body: body, icon: nil)
    }

    static func tip(_ body: String, title: String = "Pro tip") -> LessonSection {
        LessonSection(id: UUID().uuidString, type: .tip, title: title, body: body, icon: "lightbulb.fill")
    }

    static func example(title: String = "Example", body: String) -> LessonSection {
        LessonSection(id: UUID().uuidString, type: .example, title: title, body: body, icon: "quote.opening")
    }

    static func keyTakeaway(_ body: String) -> LessonSection {
        LessonSection(id: UUID().uuidString, type: .keyTakeaway, title: "Key takeaway", body: body, icon: "star.fill")
    }

    static func callout(title: String, body: String, icon: String = "info.circle.fill") -> LessonSection {
        LessonSection(id: UUID().uuidString, type: .callout, title: title, body: body, icon: icon)
    }
}

struct LessonContent: Codable {
    let sections: [LessonSection]

    /// Minutes to read at an unhurried 200 words a minute, never less than one.
    var readingMinutes: Int {
        let words = sections.reduce(0) { $0 + $1.body.split(whereSeparator: \.isWhitespace).count }
        return max(1, Int((Double(words) / 200).rounded(.up)))
    }
}

// MARK: - Lines

/// One line of a section body. The seed marks a point explicitly -
/// `**Point** State your main idea upfront.` - rather than the view guessing
/// from a colon: "The result: a calmer mind" is a sentence, not a term.
nonisolated enum LessonLine: Hashable {
    case paragraph(String)
    case point(term: String, detail: String)

    static func parse(_ body: String) -> [LessonLine] {
        body.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            guard line.hasPrefix("**"),
                  let close = line.range(of: "**", range: line.index(line.startIndex, offsetBy: 2)..<line.endIndex)
            else { return .paragraph(line) }

            let term = line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound]
            let detail = line[close.upperBound...]
            return .point(
                term: term.trimmingCharacters(in: .whitespaces),
                detail: detail.trimmingCharacters(in: .whitespaces)
            )
        }
    }
}
