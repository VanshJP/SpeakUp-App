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
    /// Conservative: only tags things explicitly and clearly mentioned in the text.
    func extractTags(from text: String, using llmService: LLMService) async -> [StoryTag] {
        guard llmService.isAvailable else { return [] }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else { return [] }

        isExtracting = true
        defer { isExtracting = false }

        let truncated = String(text.prefix(1500))

        let systemPrompt = """
        You are a conservative metadata extractor. Given a personal story, extract ONLY items you are very confident about. When in doubt, leave a category empty.

        Rules:
        - FRIENDS: Only proper names explicitly written in the text (e.g. "Sarah", "John Smith"). Skip pronouns, titles, generic words like "friend", "my boss", "someone".
        - DATES: Only specific dates or events with clear timeframes (e.g. "July 4th", "Christmas 2024"). Skip vague time words like "recently", "last week", "sometimes".
        - LOCATIONS: Only named places explicitly mentioned (e.g. "Central Park", "Tokyo", "Stanford University"). Skip generic words like "home", "school", "the office", "outside".
        - TOPICS: 1-3 key themes. Only include if clearly a central theme, not just mentioned in passing.

        Be strict. It is better to return nothing than to return something wrong.

        Output format (leave empty after colon if nothing qualifies):
        FRIENDS: name1, name2
        DATES: display_text1|YYYY-MM-DD, display_text2|YYYY-MM-DD
        LOCATIONS: place1, place2
        TOPICS: topic1, topic2
        """

        let userPrompt = "Extract metadata from this text:\n\n\(truncated)"

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
        "boy", "girl", "guy", "folks", "the", "a", "an", "who", "whom",
        "myself", "yourself", "himself", "herself", "themselves", "ourselves",
        "boss", "teacher", "doctor", "mom", "dad", "brother", "sister",
        "uncle", "aunt", "cousin", "colleague", "coworker", "neighbor",
        "none", "n/a", "na", "nobody"
    ]

    private static let invalidLocations: Set<String> = [
        "here", "there", "somewhere", "nowhere", "everywhere", "outside",
        "inside", "home", "place", "around", "nearby", "away", "room",
        "house", "building", "office", "school", "work", "store", "shop",
        "restaurant", "hotel", "airport", "hospital", "church", "park",
        "street", "road", "downtown", "uptown", "town", "city", "country",
        "none", "n/a", "na", "location", "place"
    ]

    private static let invalidDateWords: Set<String> = [
        "recently", "sometimes", "often", "always", "never", "usually",
        "occasionally", "frequently", "rarely", "soon", "later", "before",
        "after", "once", "twice", "again", "now", "then", "today",
        "yesterday", "tomorrow", "morning", "afternoon", "evening", "night",
        "weekend", "weekday", "sometime", "time", "day", "week", "month",
        "year", "none", "n/a", "na", "date", "last week", "this week",
        "last month", "this month", "last year", "this year"
    ]

    private static let invalidTopics: Set<String> = [
        "story", "thing", "things", "stuff", "something", "nothing",
        "everything", "anything", "it", "that", "this", "general", "other",
        "various", "misc", "miscellaneous", "topic", "topics", "theme",
        "personal", "experience", "life", "event", "moment", "memory",
        "none", "n/a", "na", "personal story", "personal experience"
    ]

    private func validateTag(_ tag: StoryTag) -> Bool {
        let value = tag.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()

        guard value.count >= 2, value.count <= 50 else { return false }

        // Reject anything that looks like the LLM is hedging
        if lower.hasPrefix("none") || lower.hasPrefix("n/a") || lower.hasPrefix("no ") { return false }

        switch tag.type {
        case .friend:
            if Self.invalidFriendNames.contains(lower) { return false }
            // Names must have at least one uppercase letter (proper noun signal)
            if value == value.lowercased() { return false }
            // Single-character "names" are noise
            if value.count < 2 { return false }
        case .location:
            if Self.invalidLocations.contains(lower) { return false }
            // Locations should be proper nouns (at least one capital letter)
            if value == value.lowercased() { return false }
        case .date:
            if Self.invalidDateWords.contains(lower) { return false }
        case .topic:
            if Self.invalidTopics.contains(lower) { return false }
            // Topics should be at least 3 chars to be meaningful
            if value.count < 3 { return false }
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
