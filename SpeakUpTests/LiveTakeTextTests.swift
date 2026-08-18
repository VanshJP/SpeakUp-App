import Testing
@testable import SpeakUp

struct LiveTakeTextTests {
    @Test func captionKeepsTheLatestWords() {
        let words = (1...20).map { "w\($0)" }
        let tokens = LiveTakeText.tokens(words: words, limit: 5)
        #expect(tokens.map(\.text) == ["w16", "w17", "w18", "w19", "w20"])
    }

    @Test func emptyWordsYieldNoTokens() {
        #expect(LiveTakeText.tokens(words: []).isEmpty)
    }

    @Test func hesitationsLightUp() {
        let tokens = LiveTakeText.tokens(words: ["So", "um", "today", "uh", "went"])
        #expect(tokens.map(\.isFiller) == [false, true, false, true, false])
    }

    @Test func punctuationDoesNotHideAHesitation() {
        let tokens = LiveTakeText.tokens(words: ["um,"])
        #expect(tokens == [LiveCaptionToken(text: "um,", isFiller: true)])
    }

    @Test func likeIsNotACaptionHesitation() {
        let tokens = LiveTakeText.tokens(words: ["I", "like", "this"])
        #expect(tokens.allSatisfy { !$0.isFiller })
    }

    @Test func normalizedWordStripsCaseAndPunctuation() {
        #expect(LiveTakeText.normalizedWord(" Um, ") == "um")
    }

    // MARK: - Spotlight matching

    @Test func spotlightWordIsHeardWithItsInflections() {
        let found = LiveTakeText.newlyHeard(
            targets: ["Candid", "ephemeral"],
            in: "she gave the most candidly honest answer",
            already: []
        )
        #expect(found == ["candid"])
    }

    @Test func alreadyHeardWordsAreNotRescanned() {
        let found = LiveTakeText.newlyHeard(
            targets: ["candid"],
            in: "another candid answer",
            already: ["candid"]
        )
        #expect(found.isEmpty)
    }

    /// Empty is the caller's signal to skip the `@Observable` write.
    @Test func nothingToMatchYieldsNoWrite() {
        #expect(LiveTakeText.newlyHeard(targets: ["candid"], in: "", already: []).isEmpty)
        #expect(LiveTakeText.newlyHeard(targets: [], in: "candid", already: []).isEmpty)
        #expect(LiveTakeText.newlyHeard(targets: ["candid"], in: "no match here", already: []).isEmpty)
    }
}
