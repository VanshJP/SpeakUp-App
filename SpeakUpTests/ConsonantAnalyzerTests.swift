import Testing
@testable import SpeakUp

/// Pins how Read Aloud reads a missed word down to the consonant: the
/// spelling rules, which misses count as a consonant slip and which are just
/// a different word, and how one take's slips group into "Sounds to check".
struct ConsonantAnalyzerTests {

    private func sounds(_ word: String) -> [ConsonantSound] {
        ConsonantAnalyzer.consonants(in: word).map(\.sound)
    }

    // MARK: - Spelling to sounds

    @Test func digraphsAndSilentLettersReadAsTheirSounds() {
        #expect(sounds("three") == [.th, .r])
        #expect(sounds("knight") == [.n, .t])
        #expect(sounds("school") == [.s, .k, .l])
        #expect(sounds("nation") == [.n, .sh, .n])
        #expect(sounds("measure") == [.m, .zh, .r])
        #expect(sounds("could") == [.k, .d])
        #expect(sounds("shoulder") == [.sh, .l, .d, .r])
        #expect(sounds("climb") == [.k, .l, .m])
        #expect(sounds("laughed") == [.l, .f, .t])
    }

    @Test func pastTenseEndingsSoundAsTheWordAsks() {
        #expect(sounds("walked") == [.w, .k, .t])
        #expect(sounds("needed") == [.n, .d, .d])
        #expect(sounds("sighed") == [.s, .d])
        #expect(sounds("played") == [.p, .l, .d])
    }

    @Test func lettersPointIntoTheWordAsWritten() {
        let spelled = ConsonantAnalyzer.consonants(in: "(Three,")
        #expect(spelled.map(\.letters) == [1..<3, 3..<4])
    }

    @Test func wordsOutsideEnglishSpellingAreLeftAlone() {
        #expect(ConsonantAnalyzer.consonants(in: "72").isEmpty)
        #expect(ConsonantAnalyzer.consonants(in: "日本").isEmpty)
        #expect(sounds("café") == [.k, .f])
    }

    // MARK: - Slips

    @Test func aSwappedConsonantIsNamedAndItsLettersMarked() throws {
        let slip = try #require(ConsonantAnalyzer.slip(target: "three", heard: "free"))
        #expect(slip.kind == .swapped(expected: .th, heard: .f))
        #expect(slip.letters == 0..<2)
        #expect(slip.summary == "The TH sounded like F.")
        #expect(slip.tip == ConsonantSound.th.tip(whenHeardAs: .f))
    }

    @Test func aWordEndingThatWasNotHeardIsCalledOut() throws {
        let asked = try #require(ConsonantAnalyzer.slip(target: "asked", heard: "ask"))
        #expect(asked.kind == .dropped(.t, atEnd: true))
        #expect(asked.letters == 3..<5)
        #expect(asked.summary == "The -ed ending wasn't heard.")

        let cold = try #require(ConsonantAnalyzer.slip(target: "cold,", heard: "coal"))
        #expect(cold.kind == .dropped(.d, atEnd: true))
        #expect(cold.summary == "The final D wasn't heard.")
    }

    @Test func aConsonantLostInsideAWordIsNotAnEnding() throws {
        let world = try #require(ConsonantAnalyzer.slip(target: "world", heard: "word"))
        #expect(world.kind == .dropped(.l, atEnd: false))
        #expect(world.letters == 3..<4)
        #expect(world.summary == "The L wasn't heard.")
    }

    @Test func commonConfusionsAreCaught() {
        let pairs: [(String, String, ConsonantSlipKind)] = [
            ("light", "right", .swapped(expected: .l, heard: .r)),
            ("vest", "west", .swapped(expected: .v, heard: .w)),
            ("very", "berry", .swapped(expected: .v, heard: .b)),
            ("chair", "share", .swapped(expected: .ch, heard: .sh)),
            ("think", "sink", .swapped(expected: .th, heard: .s)),
            ("they", "day", .swapped(expected: .th, heard: .d)),
            ("bad", "bat", .swapped(expected: .d, heard: .t)),
        ]
        for (target, heard, kind) in pairs {
            #expect(ConsonantAnalyzer.slip(target: target, heard: heard)?.kind == kind, "\(target) heard as \(heard)")
        }
    }

    @Test func vowelsHomophonesAndSilentLettersAreNotSlips() {
        let pairs = [
            ("ship", "sheep"), ("bat", "bet"), ("write", "right"), ("knight", "night"),
            ("passed", "past"), ("sighed", "side"), ("their", "there"), ("hour", "our"),
        ]
        for (target, heard) in pairs {
            #expect(ConsonantAnalyzer.slip(target: target, heard: heard) == nil, "\(target) heard as \(heard)")
        }
    }

    /// A misread is not a pronunciation slip, and calling it one would send
    /// the reader to fix a sound they made fine.
    @Test func aDifferentWordIsNotASlip() {
        let pairs = [
            ("house", "home"), ("mission", "vision"), ("tattoo", "too"), ("wants", "once"),
            ("quickly", "quick"), ("computer", "computers"), ("the", "a"), ("and", "an"),
            ("seventy", "70"),
        ]
        for (target, heard) in pairs {
            #expect(ConsonantAnalyzer.slip(target: target, heard: heard) == nil, "\(target) heard as \(heard)")
        }
    }

    // MARK: - Sounds to check

    @Test func slipsGroupBySoundWithEndingsTogether() {
        let passage = "Three thin cats asked for thanks tonight.".components(separatedBy: " ")
        let check = SoundCheck(passage: passage, heard: [0: "free", 1: "tin", 3: "ask", 5: "tanks"])

        #expect(check.patterns.map(\.key) == [.sound(.th), .endings])
        #expect(check.patterns.first?.title == "TH")
        #expect(check.patterns.first?.summary == "3 words · sounded like F or T")
        #expect(check.patterns.last?.title == "Word endings")
        #expect(check.patterns.last?.summary == "1 word · last sound not heard")
        #expect(check.slip(at: 3)?.isPastTenseEnding == true)
        #expect(check.slip(at: 2) == nil)
    }

    @Test func aPatternIsTitledByTheLettersTheReaderSaw() {
        let passage = "The coat and the cot".components(separatedBy: " ")
        let check = SoundCheck(passage: passage, heard: [1: "goat", 4: "got"])

        #expect(check.patterns.first?.title == "C")
        #expect(check.patterns.first?.summary == "2 words · sounded like G")
    }

    @Test func practiceLeadsWithTheWordsThenTheirSentences() {
        let passage = "I think three thin cats sat".components(separatedBy: " ")
        let check = SoundCheck(passage: passage, heard: [1: "sink", 2: "free"])

        #expect(check.patterns.first?.practiceText == "Think. Three. I think three thin cats")
    }

    @Test func aTakeWithoutConsonantSlipsHasNothingToCheck() {
        let passage = "I see a ship".components(separatedBy: " ")
        let check = SoundCheck(passage: passage, heard: [3: "sheep"])

        #expect(check.words.isEmpty)
        #expect(check.patterns.isEmpty)
        #expect(SoundCheck.empty.patterns.isEmpty)
    }

    @Test func onlyMissesCarryAHeardWord() {
        let states: [WordMatchState] = [.matched, .mismatched(spoken: "free"), .skipped, .current]
        #expect(ReadAloudResult.heardWords(in: states) == [1: "free"])
    }
}
