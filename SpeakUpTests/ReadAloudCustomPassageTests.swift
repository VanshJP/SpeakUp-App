import Testing
import Foundation
@testable import SpeakUp

struct ReadAloudCustomPassageTests {

    @Test func singleWordBecomesWordPractice() throws {
        let passage = try #require(ReadAloudPassage.custom(from: "  entrepreneurial  "))
        #expect(passage.title == "Word practice")
        #expect(passage.text == "entrepreneurial")
        #expect(passage.wordCount == 1)
        #expect(passage.category == .custom)
        #expect(passage.isCustom)
        #expect(passage.difficulty == .easy)
    }

    @Test func shortSentenceBecomesSentencePractice() throws {
        let passage = try #require(ReadAloudPassage.custom(from: "Clarity beats volume every time."))
        #expect(passage.title == "Sentence practice")
        #expect(passage.wordCount == 5)
        #expect(passage.difficulty == .easy)
    }

    @Test func longerTextBecomesParagraphPractice() throws {
        let text = Array(repeating: "word", count: 25).joined(separator: " ")
        let passage = try #require(ReadAloudPassage.custom(from: text))
        #expect(passage.title == "Paragraph practice")
        #expect(passage.wordCount == 25)
        #expect(passage.difficulty == .medium)
    }

    @Test func emptyAndWhitespaceRejected() {
        #expect(ReadAloudPassage.custom(from: "") == nil)
        #expect(ReadAloudPassage.custom(from: "   \n\t  ") == nil)
        #expect(ReadAloudPassage.custom(from: "a") == nil) // below min characters
    }

    @Test func longInputIsCapped() throws {
        let raw = String(repeating: "abcdefghij ", count: 100) // > 800 chars
        let passage = try #require(ReadAloudPassage.custom(from: raw))
        #expect(passage.text.count <= ReadAloudPassage.customMaxCharacters)
    }

    @Test func catalogCasesOmitCustom() {
        #expect(!ReadAloudCategory.catalogCases.contains(.custom))
        #expect(ReadAloudCategory.allCases.contains(.custom))
    }

    @Test func canDefineRejectsMultiWord() {
        #expect(PronunciationService.canDefine("hello world") == false)
    }

    // MARK: - Saved passages

    @Test func savedPassageIdIsStableAcrossCalls() throws {
        let first = try #require(ReadAloudPassage.saved(from: "  Clarity beats volume.  "))
        let second = try #require(ReadAloudPassage.saved(from: "Clarity beats volume."))
        #expect(first.id == second.id)
        #expect(first.id.hasPrefix("saved-"))
    }

    @Test func customPassageIdIsFreshEachCall() throws {
        let first = try #require(ReadAloudPassage.custom(from: "Clarity beats volume."))
        let second = try #require(ReadAloudPassage.custom(from: "Clarity beats volume."))
        #expect(first.id != second.id)
    }

    @Test func savedPassageKeepsCustomTitleAndDifficultyRules() throws {
        let word = try #require(ReadAloudPassage.saved(from: "entrepreneurial"))
        #expect(word.title == "Word practice")
        #expect(word.difficulty == .easy)
        #expect(word.category == .custom)

        let paragraph = try #require(
            ReadAloudPassage.saved(from: Array(repeating: "word", count: 45).joined(separator: " "))
        )
        #expect(paragraph.title == "Paragraph practice")
        #expect(paragraph.difficulty == .hard)
    }

    @Test func savedPassageRejectsWhatCustomRejects() {
        #expect(ReadAloudPassage.saved(from: "") == nil)
        #expect(ReadAloudPassage.saved(from: "   \n\t  ") == nil)
        #expect(ReadAloudPassage.saved(from: "a") == nil)
    }

    @Test func savedTextsAreNewestFirstAndDeduplicated() {
        var list: [String] = []
        list = SavedReadAloudTexts.adding("Clarity beats volume.", to: list)
        list = SavedReadAloudTexts.adding("  Pause instead of filling.  ", to: list)
        list = SavedReadAloudTexts.adding("clarity BEATS volume.", to: list) // same passage

        #expect(list == ["Pause instead of filling.", "Clarity beats volume."])
        #expect(SavedReadAloudTexts.contains("CLARITY BEATS VOLUME.", in: list))
    }

    @Test func savedTextsIgnoreUnusableInput() {
        var list: [String] = []
        list = SavedReadAloudTexts.adding("   ", to: list)
        list = SavedReadAloudTexts.adding("a", to: list)
        #expect(list.isEmpty)
    }

    @Test func removingSavedTextIsCaseInsensitive() {
        let list = SavedReadAloudTexts.adding("Clarity beats volume.", to: [])
        let pruned = SavedReadAloudTexts.removing("clarity beats volume.", from: list)
        #expect(pruned.isEmpty)
        #expect(!SavedReadAloudTexts.contains("Clarity beats volume.", in: pruned))
    }
}
