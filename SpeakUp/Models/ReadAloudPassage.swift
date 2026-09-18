import Foundation

// MARK: - Read Aloud Passage

nonisolated struct ReadAloudPassage: Identifiable, Hashable {
    let id: String
    let title: String
    let text: String
    let difficulty: ReadAloudDifficulty
    let category: ReadAloudCategory

    var wordCount: Int {
        text.split(separator: " ").count
    }

    var words: [String] {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }

    /// User-typed word, sentence, or short paragraph for pronunciation practice.
    static let customMinCharacters = 2
    static let customMaxCharacters = 800

    /// Builds an ephemeral passage from freeform text. Returns `nil` when the
    /// input is empty or only punctuation/whitespace.
    static func custom(from raw: String) -> ReadAloudPassage? {
        guard let text = normalizedCustomText(raw) else { return nil }
        return make(text: text, id: "custom-\(UUID().uuidString)")
    }

    /// A custom passage the user kept. Identical title/difficulty rules to
    /// `custom(from:)`, but the id is derived from the text rather than a fresh
    /// UUID, so a saved row keeps one identity across re-renders and launches.
    /// Saved texts are de-duplicated, so the text is a sound key.
    static func saved(from raw: String) -> ReadAloudPassage? {
        guard let text = normalizedCustomText(raw) else { return nil }
        return make(text: text, id: "saved-\(text)")
    }

    /// Trimmed, length-checked, cap-applied. `nil` when there is nothing to say.
    static func normalizedCustomText(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= customMinCharacters else { return nil }

        let capped = String(cleaned.prefix(customMaxCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? nil : capped
    }

    /// Returns an opening that fits one scored take. Prefer a sentence or
    /// paragraph boundary near the cap, then a word boundary, before using a
    /// hard character boundary as the final fallback.
    static func practiceSizedExcerpt(from raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= customMinCharacters else { return nil }
        guard cleaned.count > customMaxCharacters else { return cleaned }

        let capped = String(cleaned.prefix(customMaxCharacters))
        let preferredStart = capped.index(
            capped.startIndex,
            offsetBy: customMaxCharacters / 2
        )
        let preferredRange = preferredStart..<capped.endIndex

        if let boundary = capped[preferredRange].lastIndex(where: {
            $0 == "." || $0 == "!" || $0 == "?" || $0 == "\n"
        }) {
            let end = capped.index(after: boundary)
            return String(capped[..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let boundary = capped[preferredRange].lastIndex(where: \.isWhitespace) {
            return String(capped[..<boundary])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return capped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func make(text: String, id: String) -> ReadAloudPassage {
        let count = text.split(whereSeparator: { $0.isWhitespace }).count
        let title: String
        switch count {
        case 1: title = "Word practice"
        case 2...20: title = "Sentence practice"
        default: title = "Paragraph practice"
        }

        let difficulty: ReadAloudDifficulty
        switch count {
        case 1...8: difficulty = .easy
        case 9...40: difficulty = .medium
        default: difficulty = .hard
        }

        return ReadAloudPassage(
            id: id,
            title: title,
            text: text,
            difficulty: difficulty,
            category: .custom
        )
    }

    /// True when this passage came from the freeform practice field.
    var isCustom: Bool { category == .custom }
}

// MARK: - Saved Passage List

/// The list rules for the passages a user keeps, kept out of `UserSettings` so
/// they are testable without standing up a `ModelContainer` (gotcha §12).
/// `nonisolated` because default isolation here is MainActor (gotcha §1).
nonisolated enum SavedReadAloudTexts {

    /// Newest first, so a passage you just kept is the first one you see.
    /// De-duplicated case-insensitively: the text *is* the passage's identity,
    /// since `ReadAloudPassage.saved(from:)` derives the id from it.
    static func adding(_ raw: String, to list: [String]) -> [String] {
        guard let text = ReadAloudPassage.normalizedCustomText(raw) else { return list }
        guard !contains(text, in: list) else { return list }
        return [text] + list
    }

    static func removing(_ raw: String, from list: [String]) -> [String] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return list.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
    }

    static func contains(_ raw: String, in list: [String]) -> Bool {
        guard let text = ReadAloudPassage.normalizedCustomText(raw) else { return false }
        return list.contains { $0.caseInsensitiveCompare(text) == .orderedSame }
    }
}

// MARK: - Difficulty

nonisolated enum ReadAloudDifficulty: String, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }

    var icon: String {
        switch self {
        case .easy: return "1.circle.fill"
        case .medium: return "2.circle.fill"
        case .hard: return "3.circle.fill"
        }
    }
}

// MARK: - Category

nonisolated enum ReadAloudCategory: String, CaseIterable, Identifiable {
    case news
    case literature
    case technical
    case tongueTwister
    case minimalPairs
    /// Ephemeral user-typed practice - not shown in catalog filters.
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .news: return "News"
        case .literature: return "Literature"
        case .technical: return "Technical"
        case .tongueTwister: return "Tongue Twister"
        case .minimalPairs: return "Minimal Pairs"
        case .custom: return "Yours"
        }
    }

    var icon: String {
        switch self {
        case .news: return "newspaper"
        case .literature: return "book"
        case .technical: return "gearshape.2"
        case .tongueTwister: return "mouth"
        case .minimalPairs: return "ear"
        case .custom: return "text.cursor"
        }
    }

    /// The shared axis. A passage's source material is not why you'd pick it:
    /// news copy trains holding a steady clip, literature trains expression,
    /// and the precision material trains being understood. Your own passages
    /// follow whatever you pasted in, so they sit under clarity - the reason
    /// the feature scores word-by-word in the first place.
    var focus: PracticeFocus {
        switch self {
        case .news: return .pace
        case .literature: return .presence
        case .technical, .tongueTwister, .minimalPairs, .custom: return .clarity
        }
    }

    /// Catalog filters - excludes freeform custom passages.
    static var catalogCases: [ReadAloudCategory] {
        allCases.filter { $0 != .custom }
    }

}

