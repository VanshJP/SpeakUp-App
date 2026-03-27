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
        1. FRIENDS: Names of people mentioned (first names or full names)
        2. DATES: Any dates, time references, or occasions mentioned (e.g. "last summer", "Christmas 2024", "March 5th")
        3. LOCATIONS: Places, venues, cities, or locations mentioned
        4. TOPICS: 2-4 key themes or topics that summarize what the story is about

        Output EXACTLY in this format with no other text. If a category has no matches, leave it empty after the colon:
        FRIENDS: name1, name2
        DATES: date1, date2
        LOCATIONS: place1, place2
        TOPICS: topic1, topic2
        """

        let userPrompt = "Extract metadata from this story:\n\n\(truncated)"

        guard let output = await llmService.generateText(prompt: userPrompt, systemPrompt: systemPrompt) else {
            return []
        }

        return parseTags(from: output)
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
                tags += values.map { StoryTag(type: .date, value: $0) }
            } else if let values = extractValues(from: trimmed, prefix: "LOCATIONS:") {
                tags += values.map { StoryTag(type: .location, value: $0) }
            } else if let values = extractValues(from: trimmed, prefix: "TOPICS:") {
                tags += values.map { StoryTag(type: .topic, value: $0) }
            }
        }

        return tags
    }

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
