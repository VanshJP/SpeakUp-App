import Foundation
import SwiftData

@MainActor
enum SharedPromptResolver {
    static func resolve(_ payload: SharedPromptPayload, in context: ModelContext) -> Prompt? {
        if let id = payload.promptID, !id.isEmpty, let existing = prompt(id: id, in: context) {
            return existing
        }

        guard let text = payload.trimmedText else { return nil }

        if let existing = prompt(matchingText: text, in: context) {
            return existing
        }

        return insert(from: payload, text: text, in: context)
    }

    static func prompt(id: String, in context: ModelContext) -> Prompt? {
        let target = id
        var descriptor = FetchDescriptor<Prompt>()
        descriptor.predicate = #Predicate { $0.id == target }
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func prompt(matchingText text: String, in context: ModelContext) -> Prompt? {
        let target = text
        var descriptor = FetchDescriptor<Prompt>()
        descriptor.predicate = #Predicate { $0.text == target }
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func insert(
        from payload: SharedPromptPayload,
        text: String,
        in context: ModelContext
    ) -> Prompt {
        let catalogID = payload.promptID.flatMap { SharedPromptLink.isCatalogID($0) ? $0 : nil }
        let id = catalogID ?? SharedPromptLink.stableID(for: text)
        let difficulty = payload.difficulty.flatMap(PromptDifficulty.init(rawValue:)) ?? .medium
        let category = payload.category.flatMap { $0.isEmpty ? nil : $0 }
            ?? PromptCategory.conversationStarters.rawValue

        let prompt = Prompt(
            id: id,
            text: text,
            category: category,
            difficulty: difficulty,
            isUserCreated: catalogID == nil
        )
        context.insert(prompt)
        try? context.save()
        return prompt
    }
}
