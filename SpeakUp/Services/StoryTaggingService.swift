import Foundation

@MainActor @Observable
final class StoryTaggingService {

    enum TaggingError: LocalizedError {
        case llmUnavailable
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .llmUnavailable: return "No language model is available for tag extraction."
            case .parsingFailed: return "Could not parse tags from the response."
            }
        }
    }

    var isExtracting = false

    /// Extracts tags from story text using the best available LLM backend.
    /// Returns an empty array if no LLM is available (graceful degradation).
    func extractTags(from text: String, using llmService: LLMService) async -> [StoryTag] {
        guard llmService.isAvailable else { return [] }

        isExtracting = true
        defer { isExtracting = false }

        let truncated = String(text.prefix(1500))

        let systemPrompt = """
        You are a story metadata extractor. Given a personal story or script, extract:
        1. FRIENDS: Proper names of specific people mentioned (first names or full names). Do NOT include pronouns, generic references like "friend", "someone", "people", or "everyone".
        2. DATES: Specific dates, time references, or occasions mentioned. Use the format: display_text|YYYY-MM-DD (approximate the date if needed). Example: "Christmas 2024|2024-12-25", "last summer|2024-07-01". Do NOT include vague words like "recently", "sometimes", "often", "always", or "never".
        3. LOCATIONS: Specific named places, venues, cities, or locations. Do NOT include vague words like "here", "there", "somewhere", "home", or "outside".
        4. TOPICS: 2-4 key themes or topics that summarize what the story is about. Each topic should be 1-3 words and meaningful.

        Output EXACTLY in this format with no other text. If a category has no matches, leave it empty after the colon:
        FRIENDS: name1, name2
        DATES: display_text1|YYYY-MM-DD, display_text2|YYYY-MM-DD
        LOCATIONS: place1, place2
        TOPICS: topic1, topic2
        """

        let userPrompt = "Extract metadata from this story:\n\n\(truncated)"

        guard let output = await llmService.generateText(prompt: userPrompt, systemPrompt: systemPrompt) else {
            return []
        }

        let tags = parseTags(from: output)
        return deduplicate(tags)
    }

    // MARK: - Parsing

    private func parseTags(from output: String) -> [StoryTag] {
        var tags: [StoryTag] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let values = extractValues(from: trimmed, prefix: "FRIENDS:") {
                tags += values.map { StoryTag(type: .friend, value: $0) }
            } else if let values = extractValues(from: trimmed, prefix: "DATES:") {
                tags += values.compactMap { parseDateTag($0) }
            } else if let values = extractValues(from: trimmed, prefix: "LOCATIONS:") {
                tags += values.map { StoryTag(type: .location, value: $0) }
            } else if let values = extractValues(from: trimmed, prefix: "TOPICS:") {
                tags += values.map { StoryTag(type: .topic, value: $0) }
            }
        }

        return tags.filter { validateTag($0) }
    }

    private func parseDateTag(_ raw: String) -> StoryTag {
        let parts = raw.components(separatedBy: "|")
        let displayText = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)

        var parsed: Date?
        if parts.count >= 2 {
            let dateStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            parsed = Self.isoFormatter.date(from: dateStr)
        }

        // Fallback: try NSDataDetector on the display text
        if parsed == nil {
            parsed = detectDate(from: displayText)
        }

        return StoryTag(type: .date, value: displayText, parsedDate: parsed)
    }

    private func detectDate(from text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let match = detector.firstMatch(in: text, range: range)
        return match?.date
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    // MARK: - Validation

    private static let invalidFriendNames: Set<String> = [
        "i", "me", "my", "he", "she", "they", "them", "we", "us", "you",
        "him", "her", "his", "it", "its", "our", "their", "friend", "someone",
        "people", "everyone", "somebody", "anybody", "person", "man", "woman",
        "boy", "girl", "guy", "folks", "the", "a", "an"
    ]

    private static let invalidLocations: Set<String> = [
        "here", "there", "somewhere", "nowhere", "everywhere", "outside",
        "inside", "home", "place", "around", "nearby", "away"
    ]

    private static let invalidDateWords: Set<String> = [
        "recently", "sometimes", "often", "always", "never", "usually",
        "occasionally", "frequently", "rarely", "soon", "later", "before",
        "after", "once", "twice", "again", "now", "then"
    ]

    private static let invalidTopics: Set<String> = [
        "story", "thing", "things", "stuff", "something", "nothing",
        "everything", "anything", "it", "that", "this", "general", "other",
        "various", "misc", "miscellaneous"
    ]

    private func validateTag(_ tag: StoryTag) -> Bool {
        let value = tag.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()

        // Length checks
        guard value.count >= 2, value.count <= 60 else { return false }

        switch tag.type {
        case .friend:
            if Self.invalidFriendNames.contains(lower) { return false }
            // Names should have at least one uppercase letter
            if value == value.lowercased() && !value.contains(" ") { return false }
        case .location:
            if Self.invalidLocations.contains(lower) { return false }
        case .date:
            if Self.invalidDateWords.contains(lower) { return false }
        case .topic:
            if Self.invalidTopics.contains(lower) { return false }
        case .custom:
            break
        }

        return true
    }

    // MARK: - Deduplication

    private func deduplicate(_ tags: [StoryTag]) -> [StoryTag] {
        var seen: Set<String> = []
        return tags.filter { tag in
            let key = "\(tag.type.rawValue):\(tag.value.lowercased())"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    // MARK: - Helpers

    private func extractValues(from line: String, prefix: String) -> [String]? {
        guard line.uppercased().hasPrefix(prefix.uppercased()) else { return nil }
        let remainder = String(line.dropFirst(prefix.count))
        let values = remainder
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }
}
