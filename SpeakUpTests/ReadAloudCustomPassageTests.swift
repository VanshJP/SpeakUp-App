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
}
