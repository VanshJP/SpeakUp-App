import Testing
@testable import SpeakUp

struct PromptCSVParserTests {

    @Test("Quoted fields keep their commas, quotes and line breaks")
    func quotedFields() {
        // `#"""`: the escaped quotes before the comma would close a plain
        // multi-line literal.
        let csv = #"""
        text,category,difficulty
        "Tell me, briefly, about ""home""",Storytelling,easy
        "Line one
        line two",Quick Fire,hard

        """#
        let result = PromptCSVService.parse(csv)

        #expect(result.skipped == 0)
        #expect(result.prompts.map(\.text) == ["Tell me, briefly, about \"home\"", "Line one\nline two"])
        #expect(result.prompts.map(\.category) == ["Storytelling", "Quick Fire"])
        #expect(result.prompts.map(\.difficulty) == [.easy, .hard])
    }

    @Test("A row with no text is skipped and counted; unknown values fall back")
    func skipsAndDefaults() {
        let csv = "text,category,difficulty\r\n,Interview Prep,hard\r\nWhat changed your mind?,Not a category,extreme\r\n\r\nPlain prompt\r\n"
        let result = PromptCSVService.parse(csv)

        #expect(result.skipped == 1)
        #expect(result.prompts.map(\.text) == ["What changed your mind?", "Plain prompt"])
        #expect(result.prompts.allSatisfy { $0.category == PromptCategory.personalGrowth.rawValue })
        #expect(result.prompts.allSatisfy { $0.difficulty == .medium })
    }

    @Test("An export reads back as the same prompts")
    func roundTrip() throws {
        let service = PromptCSVService()
        let prompts = [
            Prompt(id: "a", text: "Say \"why\", then how", category: PromptCategory.debatePersuasion.rawValue, difficulty: .hard),
            Prompt(id: "b", text: "First line\nsecond line", category: PromptCategory.storytelling.rawValue, difficulty: .easy)
        ]

        let result = try service.parseCSV(from: service.exportToCSV(prompts: prompts))

        #expect(result.skipped == 0)
        #expect(result.prompts.map(\.text) == prompts.map(\.text))
        #expect(result.prompts.map(\.category) == prompts.map(\.category))
    }

    @Test("Duplicates ignore case and surrounding whitespace, in the file and against the library")
    func duplicates() {
        let result = PromptCSVService.removingDuplicates(
            ["  Hello there ", "hello THERE", "New one", "new one"],
            text: { $0 },
            existing: ["Hello there"]
        )

        #expect(result.unique == ["New one"])
        #expect(result.duplicates == 3)
    }
}
