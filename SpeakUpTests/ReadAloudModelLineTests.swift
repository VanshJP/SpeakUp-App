import Testing
@testable import SpeakUp

/// "Hear it" mid-read plays from the start of the sentence the reader is in.
@MainActor
@Suite("Read-aloud model line")
struct ReadAloudModelLineTests {
    private let words = ["One", "two.", "Three", "four!", "Five", "\"six.\"", "Seven"]

    @Test("Starts at the sentence holding the index")
    func startsAtSentence() {
        #expect(ReadAloudSessionView.modelLine(in: words, from: 3) == "Three four! Five \"six.\" Seven")
    }

    @Test("Closing quotes still end a sentence; out-of-range and empty are safe")
    func edges() {
        #expect(ReadAloudSessionView.modelLine(in: words, from: 0) == words.joined(separator: " "))
        #expect(ReadAloudSessionView.modelLine(in: words, from: 6) == "Seven")
        #expect(ReadAloudSessionView.modelLine(in: words, from: 42) == "Seven")
        #expect(ReadAloudSessionView.modelLine(in: [], from: 2) == "")
    }
}
