import Foundation

// MARK: - Consonant Sound

/// A consonant sound, as far as spelling can tell. The TH in "this" and the
/// TH in "thin" share one case: spelling cannot tell them apart, and the
/// advice for both is the same.
nonisolated enum ConsonantSound: String, Sendable {
    case p, b, t, d, k, g, f, v, th, s, z, sh, zh, ch, j, m, n, ng, l, r, w, y, h

    /// How the app writes the sound: "TH", "SH", "K".
    var label: String {
        rawValue.uppercased()
    }

    /// Sounds that spelling alone cannot keep apart: the S in "is" is a Z,
    /// the G in "gem" is a J, the N in "think" is an NG. Treating them as
    /// the same keeps a guess about spelling from turning into a slip.
    func soundsLike(_ other: ConsonantSound) -> Bool {
        self == other || Self.spellingTwins.contains([self, other])
    }

    /// Whether a swap between the two could be a pronunciation slip rather
    /// than a different word: they are made in the same place or the same
    /// way, or they are a swap people commonly make. S heard as M ("house"
    /// heard as "home") shares neither, and is a misread.
    func isRelated(to other: ConsonantSound) -> Bool {
        place == other.place
            || manner == other.manner
            || Self.commonSwaps.contains([self, other])
    }

    private static let spellingTwins: Set<Set<ConsonantSound>> = [
        [.s, .z], [.sh, .zh], [.g, .j], [.n, .ng]
    ]

    private static let commonSwaps: Set<Set<ConsonantSound>> = [
        [.th, .t], [.th, .d], [.v, .w], [.v, .b], [.p, .f], [.t, .ch], [.d, .j], [.j, .y]
    ]

    /// Where in the mouth the sound is made.
    private var place: String {
        switch self {
        case .p, .b, .m, .w: return "lips"
        case .f, .v: return "lip and teeth"
        case .th: return "teeth"
        case .t, .d, .s, .z, .n, .l: return "ridge"
        case .r, .sh, .zh, .ch, .j, .y: return "palate"
        case .k, .g, .ng: return "back"
        case .h: return "throat"
        }
    }

    /// How the air is shaped: stopped, hissed, stopped then hissed, hummed
    /// through the nose, or glided.
    private var manner: String {
        switch self {
        case .p, .b, .t, .d, .k, .g: return "stop"
        case .f, .v, .th, .s, .z, .sh, .zh, .h: return "hiss"
        case .ch, .j: return "burst"
        case .m, .n, .ng: return "hum"
        case .l, .r, .w, .y: return "glide"
        }
    }

    private var isVoiced: Bool {
        switch self {
        case .p, .t, .k, .f, .th, .s, .sh, .ch, .h: return false
        default: return true
        }
    }

    // MARK: Tips

    /// Where to put the tongue, lips and voice. A placement cue for a
    /// reader, not a diagnosis.
    var tip: String {
        switch self {
        case .p: return "Press your lips together, then pop them open with a small puff of air."
        case .b: return "Press your lips together and open them with your voice already on."
        case .t: return "Tap your tongue tip on the ridge just behind your top teeth, then let go with a small puff."
        case .d: return "Tap your tongue tip on the ridge behind your top teeth with your voice on."
        case .k: return "Lift the back of your tongue against the roof of your mouth, then release a small puff."
        case .g: return "Lift the back of your tongue against the roof of your mouth and release it with your voice on."
        case .f: return "Rest your top teeth lightly on your lower lip and blow."
        case .v: return "Rest your top teeth on your lower lip and turn your voice on. You should feel a buzz."
        case .th: return "Put your tongue tip lightly between your teeth and let the air flow over it."
        case .s: return "Keep your tongue tip just behind your top teeth and push a thin, steady stream of air."
        case .z: return "Make an S, then turn your voice on so it buzzes."
        case .sh: return "Round your lips a little, draw your tongue back and push air through: shh."
        case .zh: return "Make an SH with your voice on, like the middle of \"measure\"."
        case .ch: return "Start with your tongue on the ridge behind your top teeth and release it straight into an SH."
        case .j: return "Start like a D and release it straight into a buzzing SH, as in \"judge\"."
        case .m: return "Close your lips and hum."
        case .n: return "Press your tongue tip to the ridge behind your top teeth and hum through your nose."
        case .ng: return "Lift the back of your tongue to the roof of your mouth and hum through your nose."
        case .l: return "Touch your tongue tip to the ridge behind your top teeth and let the sound flow around its sides."
        case .r: return "Pull your tongue back and up without touching the roof of your mouth, lips slightly rounded."
        case .w: return "Round your lips tightly, then open them into the vowel. Keep your teeth off your lip."
        case .y: return "Raise the middle of your tongue toward the roof of your mouth, as at the start of \"yes\"."
        case .h: return "Breathe out through an open mouth, like fogging a mirror, then start the vowel."
        }
    }

    /// The cue for this sound when it came out as `heard`, which is more
    /// useful than the general one: it says what to change.
    func tip(whenHeardAs heard: ConsonantSound) -> String {
        switch (self, heard) {
        case (.th, .f), (.th, .v):
            return "Put your tongue tip between your teeth, not your lip under them, and let the air flow."
        case (.th, .t), (.th, .d):
            return "Keep your tongue between your teeth and let the air keep flowing. A tap behind the teeth makes a T or D."
        case (.th, .s), (.th, .z):
            return "Bring your tongue forward so it rests lightly between your teeth. Behind them, it hisses like an S."
        case (.r, .l):
            return "Keep your tongue tip off the roof of your mouth. Touching it turns an R into an L."
        case (.l, .r):
            return "Touch your tongue tip to the ridge behind your top teeth and hold it there through the sound."
        case (.r, .w):
            return "Pull your tongue back and up. Rounded lips on their own make a W."
        case (.v, .w):
            return "Rest your top teeth on your lower lip and buzz. Rounded lips make a W."
        case (.v, .b):
            return "Let your top teeth touch your lower lip and keep the air flowing. Closed lips make a B."
        case (.w, .v):
            return "Round your lips and keep your teeth off your lower lip."
        case (.b, .v):
            return "Close both lips fully, then open them. Teeth on the lip make a V."
        case (.sh, .s):
            return "Round your lips a little and pull your tongue back. Spread lips make an S."
        case (.s, .sh):
            return "Spread your lips a little and keep your tongue tip forward, just behind your top teeth."
        case (.ch, .sh):
            return "Start with your tongue touching the ridge behind your top teeth, so the sound begins with a small stop."
        case (.sh, .ch):
            return "Keep your tongue off the roof of your mouth and let the air flow from the start."
        case (.j, .y):
            return "Start with your tongue touching the ridge behind your top teeth, as in \"jam\"."
        case (.y, .j):
            return "Keep your tongue off the roof of your mouth and glide into the vowel, as in \"yes\"."
        default:
            // The same mouth shape with the voice switched: P for B, K for G.
            if place == heard.place, manner == heard.manner, isVoiced != heard.isVoiced {
                return isVoiced
                    ? "Same mouth shape, voice on. Feel the buzz in your throat."
                    : "Same mouth shape, voice off. Add a small puff of air."
            }
            return tip
        }
    }
}

// MARK: - Spelled Consonant

/// One consonant sound in a written word, and the characters that spell it.
nonisolated struct SpelledConsonant: Equatable, Sendable {
    let sound: ConsonantSound
    /// Character offsets into the word as written, punctuation included, so
    /// a view can mark exactly these letters.
    let letters: Range<Int>
}

// MARK: - Consonant Slip

nonisolated enum ConsonantSlipKind: Hashable, Sendable {
    /// Came out as another consonant: "three" heard as "free".
    case swapped(expected: ConsonantSound, heard: ConsonantSound)
    /// Not heard at all. `atEnd` when it closed the word: "cold" heard as
    /// "coal".
    case dropped(ConsonantSound, atEnd: Bool)
}

/// The one consonant that separates a word on the page from the word the
/// recognizer heard in its place.
nonisolated struct ConsonantSlip: Equatable, Sendable {
    let kind: ConsonantSlipKind
    /// Characters of the word as written that spell the consonant.
    let letters: Range<Int>
    /// Those characters, lowercased: "th", "ck", "ed".
    let spelling: String

    var expected: ConsonantSound {
        switch kind {
        case .swapped(let expected, _): return expected
        case .dropped(let sound, _): return sound
        }
    }

    /// A past-tense ending the recognizer did not hear. Named for the ending
    /// rather than its sound: it is a T in "asked" and a D in "played", and
    /// what helps is "say the ending".
    var isPastTenseEnding: Bool {
        spelling == "ed"
    }

    /// One line for the reader: "The TH sounded like F."
    var summary: String {
        let name = isPastTenseEnding ? "-ed ending" : spelling.uppercased()
        switch kind {
        case .swapped(_, let heard):
            return "The \(name) sounded like \(heard.label)."
        case .dropped(_, let atEnd):
            if isPastTenseEnding { return "The -ed ending wasn't heard." }
            return atEnd ? "The final \(name) wasn't heard." : "The \(name) wasn't heard."
        }
    }

    var tip: String {
        switch kind {
        case .swapped(let expected, let heard):
            return expected.tip(whenHeardAs: heard)
        case .dropped(let sound, let atEnd):
            if isPastTenseEnding { return Self.pastTenseTip }
            if atEnd {
                return "Finish the word. Land the final \(spelling.uppercased()) before the next word starts."
            }
            return sound.tip
        }
    }

    /// Which group of the result screen's "Sounds to check" this belongs to.
    var patternKey: SoundPatternKey {
        if case .dropped(_, atEnd: true) = kind { return .endings }
        return .sound(expected)
    }

    static let pastTenseTip = "Say the -ed. It is a quick T or D after most sounds, and its own syllable after a T or D."
}

// MARK: - Sound Check

/// A missed word whose heard stand-in differs from it by one consonant.
nonisolated struct SoundSlipWord: Equatable, Sendable {
    /// Position in the passage.
    let index: Int
    /// The passage word as written, punctuation included.
    let word: String
    /// What the recognizer heard in its place.
    let heard: String
    let slip: ConsonantSlip

    /// `word` without the punctuation around it, for showing on its own.
    var bareWord: String {
        word.trimmingCharacters(in: .punctuationCharacters)
    }

    /// `slip.letters`, measured in `bareWord`.
    var bareLetters: Range<Int> {
        let shift = word.prefix { character in
            character.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
        }.count
        return (slip.letters.lowerBound - shift)..<(slip.letters.upperBound - shift)
    }

    var bareHeard: String {
        heard.trimmingCharacters(in: .punctuationCharacters)
    }
}

nonisolated enum SoundPatternKey: Hashable, Sendable {
    /// One sound swapped or not heard anywhere but the end of a word.
    case sound(ConsonantSound)
    /// Last sounds not heard, whichever they were. The advice is the same
    /// for all of them: finish the word.
    case endings
}

/// Slips that share a sound, across one take.
nonisolated struct SoundPattern: Identifiable, Equatable, Sendable {
    let key: SoundPatternKey
    /// The words it showed up in, in reading order.
    let words: [SoundSlipWord]
    /// "TH", "C", or "Word endings".
    let title: String
    /// "3 words · sounded like F or T".
    let summary: String
    let tip: String
    /// A short passage to read next: each word on its own, then the
    /// stretches of the page it came from. Nil when there is nothing to read.
    let practiceText: String?

    var id: SoundPatternKey { key }

    init(key: SoundPatternKey, words: [SoundSlipWord], passageWords: [String]) {
        self.key = key
        self.words = words

        let count = words.count == 1 ? "1 word" : "\(words.count) words"
        switch key {
        case .endings:
            title = "Word endings"
            summary = "\(count) · last sound not heard"
            tip = words.allSatisfy(\.slip.isPastTenseEnding)
                ? ConsonantSlip.pastTenseTip
                : "Finish each word. Land its last sound before the next word starts."

        case .sound(let sound):
            // The letters the reader saw marked, when every word spelled the
            // sound the same way: "C" for coat and cat, not "K".
            let spellings = Set(words.map(\.slip.spelling))
            if spellings.count == 1, let spelling = spellings.first {
                title = spelling.uppercased()
            } else {
                title = sound.label
            }

            var heardAs: [String] = []
            var wasDropped = false
            for word in words {
                switch word.slip.kind {
                case .swapped(_, let heard):
                    if !heardAs.contains(heard.label) { heardAs.append(heard.label) }
                case .dropped:
                    wasDropped = true
                }
            }
            let outcome: String
            if heardAs.isEmpty {
                outcome = "not heard"
            } else {
                outcome = "sounded like \(Self.joinedWithOr(heardAs))" + (wasDropped ? ", or not heard" : "")
            }
            summary = "\(count) · \(outcome)"
            tip = Self.mostCommon(words.map(\.slip.tip)) ?? sound.tip
        }

        practiceText = Self.drillText(for: words, in: passageWords)
    }

    /// Each word on its own, then the stretches of the page it came from:
    /// the sound first in isolation, then in connected speech, where most
    /// slips happen.
    private static func drillText(for words: [SoundSlipWord], in passageWords: [String]) -> String? {
        var seen = Set<String>()
        let drill = words
            .map(\.bareWord)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(6)
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) + "." }
            .joined(separator: " ")
        let phrases = ReadAloudPassage.practiceText(around: words.map(\.index), in: passageWords) ?? ""
        let text = [drill, phrases].filter { !$0.isEmpty }.joined(separator: " ")
        return ReadAloudPassage.practiceSizedExcerpt(from: text)
    }

    /// "F", "F or T", "F, T or S".
    private static func joinedWithOr(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " or " + last
    }

    /// The most frequent item, the earliest on a tie.
    private static func mostCommon(_ items: [String]) -> String? {
        let counts = Dictionary(items.map { ($0, 1) }, uniquingKeysWith: +)
        guard let top = counts.values.max() else { return nil }
        return items.first { counts[$0] == top }
    }
}

/// Every consonant slip in one take, grouped by sound, with each one findable
/// by word index for marking letters in the word review.
nonisolated struct SoundCheck: Equatable, Sendable {
    /// Grouped by sound, most frequent first, earliest first on a tie.
    let patterns: [SoundPattern]

    private let slipsByIndex: [Int: ConsonantSlip]

    /// - Parameters:
    ///   - passage: The passage's words as written.
    ///   - heard: What the recognizer heard in place of each missed word, by
    ///     word index.
    init(passage: [String], heard: [Int: String]) {
        let words = heard.keys.sorted().compactMap { index -> SoundSlipWord? in
            guard index < passage.count, let spoken = heard[index],
                  let slip = ConsonantAnalyzer.slip(target: passage[index], heard: spoken)
            else { return nil }
            return SoundSlipWord(index: index, word: passage[index], heard: spoken, slip: slip)
        }
        slipsByIndex = Dictionary(uniqueKeysWithValues: words.map { ($0.index, $0.slip) })

        var groups: [SoundPatternKey: [SoundSlipWord]] = [:]
        var order: [SoundPatternKey] = []
        for word in words {
            let key = word.slip.patternKey
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(word)
        }
        // `sorted` is stable, so groups of the same size keep reading order.
        patterns = order
            .sorted { (groups[$0]?.count ?? 0) > (groups[$1]?.count ?? 0) }
            .map { SoundPattern(key: $0, words: groups[$0] ?? [], passageWords: passage) }
    }

    func slip(at index: Int) -> ConsonantSlip? {
        slipsByIndex[index]
    }
}

// MARK: - Consonant Analyzer

/// Finds the consonant a reader most likely slipped on, from the word the
/// recognizer heard in place of the one on the page.
///
/// The recognizer hears words, not sounds, so this cannot score
/// pronunciation. What it can do is read a miss: when "three" comes back as
/// "free", the two differ by exactly one consonant, and that consonant is
/// the place to listen. Rules of English spelling turn both words into
/// consonant sounds, a comparison finds the one that changed, and the
/// letters that spell it are marked in the word as written.
///
/// Deliberately narrow, because a wrong call teaches the wrong thing:
/// - One consonant swapped or not heard, never more, and never an extra one.
///   Past that, the reader said a different word.
/// - A swap only between sounds that could be confused. "House" heard as
///   "home" is a misread, not an S.
/// - Same number of syllables, at least three letters, and no function
///   words that connected speech shrinks as a matter of course ("and" as
///   "an").
nonisolated enum ConsonantAnalyzer {

    /// The consonant sounds in `word`, in order. Empty when the word has no
    /// letters or a letter outside a-z after folding accents: these are
    /// English spelling rules.
    static func consonants(in word: String) -> [SpelledConsonant] {
        letters(in: word).map(consonants(spelled:)) ?? []
    }

    /// The slip that turns `target` into `heard`, or nil when the two do not
    /// differ by exactly one related consonant.
    static func slip(target: String, heard: String) -> ConsonantSlip? {
        guard !target.contains(where: \.isNumber), !heard.contains(where: \.isNumber),
              let targetSpelled = letters(in: target),
              let heardSpelled = letters(in: heard),
              targetSpelled.letters.count >= 3,
              targetSpelled.letters != heardSpelled.letters,
              !reducedWords.contains(String(targetSpelled.letters)),
              abs(targetSpelled.letters.count - heardSpelled.letters.count) <= 3,
              ConsonantSpeller(letters: targetSpelled.letters).syllableCount
                == ConsonantSpeller(letters: heardSpelled.letters).syllableCount
        else { return nil }

        let expected = consonants(spelled: targetSpelled)
        let said = consonants(spelled: heardSpelled).map(\.sound)
        guard let edit = singleEdit(from: expected.map(\.sound), to: said) else { return nil }

        let consonant = expected[edit.index]
        let characters = Array(target)
        let kind: ConsonantSlipKind
        if let heardSound = edit.heard {
            guard consonant.sound.isRelated(to: heardSound) else { return nil }
            kind = .swapped(expected: consonant.sound, heard: heardSound)
        } else {
            // A word whose only consonant was not heard is another word.
            guard !said.isEmpty else { return nil }
            // Only a silent E may follow the last consonant of a word that
            // ends on it: "made" ends on its D.
            let after = letters(in: String(characters[consonant.letters.upperBound...]))?.letters ?? []
            let atEnd = edit.index == expected.count - 1 && (after.isEmpty || after == ["e"])
            kind = .dropped(consonant.sound, atEnd: atEnd)
        }
        return ConsonantSlip(
            kind: kind,
            letters: consonant.letters,
            spelling: String(characters[consonant.letters]).lowercased()
        )
    }

    // MARK: - Gates

    /// Function words that shrink in ordinary connected speech. What the
    /// recognizer hears for them says more about pace than about a consonant.
    private static let reducedWords: Set<String> = [
        "and", "are", "but", "can", "for", "from", "had", "has", "have", "her", "him", "his",
        "its", "just", "must", "our", "the", "them", "was", "were", "you", "your"
    ]

    /// The word's letters folded to lowercase a-z, with each one's character
    /// offset in the word. Nil when there are none, or when a letter is
    /// outside a-z even after folding accents.
    private static func letters(in word: String) -> (letters: [Character], offsets: [Int])? {
        var letters: [Character] = []
        var offsets: [Int] = []
        for (offset, character) in word.enumerated() where character.isLetter {
            let folded = String(character).folding(options: .diacriticInsensitive, locale: nil).lowercased()
            guard folded.count == 1, let letter = folded.first, letter.isASCII, letter.isLetter else {
                return nil
            }
            letters.append(letter)
            offsets.append(offset)
        }
        guard !letters.isEmpty else { return nil }
        return (letters, offsets)
    }

    /// The speller's sounds, with letter ranges moved to character offsets in
    /// the word as written.
    private static func consonants(spelled: (letters: [Character], offsets: [Int])) -> [SpelledConsonant] {
        var speller = ConsonantSpeller(letters: spelled.letters)
        return speller.read().map { consonant in
            let start = spelled.offsets[consonant.letters.lowerBound]
            let end = spelled.offsets[consonant.letters.upperBound - 1] + 1
            return SpelledConsonant(sound: consonant.sound, letters: start..<end)
        }
    }

    /// Where `heard` differs from `target` by exactly one sound: swapped, and
    /// `heard` names what it became, or not heard, and `heard` is nil. Nil for
    /// any other difference, an extra sound included.
    ///
    /// Matched from the end first, so of two equal sounds in a row the
    /// earlier one is the one reported missing.
    private static func singleEdit(
        from target: [ConsonantSound],
        to heard: [ConsonantSound]
    ) -> (index: Int, heard: ConsonantSound?)? {
        let lengthDifference = target.count - heard.count
        guard lengthDifference == 0 || lengthDifference == 1 else { return nil }

        var suffix = 0
        while suffix < heard.count,
              target[target.count - 1 - suffix].soundsLike(heard[heard.count - 1 - suffix]) {
            suffix += 1
        }
        let index = target.count - 1 - suffix
        guard index >= 0, (0..<index).allSatisfy({ target[$0].soundsLike(heard[$0]) }) else { return nil }
        return (index, lengthDifference == 0 ? heard[index] : nil)
    }
}

// MARK: - Consonant Speller

/// Reads English spelling into consonant sounds. Rules of thumb, not a
/// pronouncing dictionary: they cover the common patterns and the silent
/// letters that most words carry. When they guess wrong on a rare word, the
/// word it is compared with usually shares the spelling and the guess.
///
/// Letter ranges here index `letters`, not the word as written.
private nonisolated struct ConsonantSpeller {
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

    let letters: [Character]
    let word: String
    private var sounds: [SpelledConsonant] = []

    init(letters: [Character]) {
        self.letters = letters
        self.word = String(letters)
    }

    private var count: Int { letters.count }

    mutating func read() -> [SpelledConsonant] {
        sounds = []
        let greekCh = Self.greekChWords.contains(word) || Self.greekChPrefixes.contains { word.hasPrefix($0) }
        let frenchCh = Self.frenchChWords.contains(word) || Self.frenchChPrefixes.contains { word.hasPrefix($0) }

        var index = 0
        while index < count {
            let letter = letters[index]
            if isVowel(index) || (letter == "y" && !yIsConsonant(index)) {
                index += 1
                continue
            }
            if index == 0, let next = readOpening() {
                index = next
                continue
            }
            if has("sch", at: index) {
                emit(.s, index, index + 1)
                emit(.k, index + 1, index + 3)
                index += 3
                continue
            }
            if has("ch", at: index) {
                let sound: ConsonantSound
                if greekCh || has("chr", at: index) || has("chl", at: index) {
                    sound = .k
                } else {
                    sound = frenchCh ? .sh : .ch
                }
                emit(sound, index, index + 2)
                index += 2
                continue
            }
            if let spelling = Self.spellings.first(where: { has($0.letters, at: index) }) {
                emit(spelling.sound, index, index + spelling.letters.count)
                index += spelling.letters.count
                continue
            }

            // Letters with more than one reading. Nil falls through to the
            // plain one.
            let next: Int?
            switch letter {
            case "b": next = readB(at: index)
            case "c": next = readC(at: index)
            case "d": next = readD(at: index)
            case "g": next = readG(at: index)
            case "l": next = readL(at: index)
            case "n": next = readN(at: index)
            case "q": next = readQ(at: index)
            case "s": next = readS(at: index)
            case "t": next = readT(at: index)
            case "w": next = readW(at: index)
            case "h":
                // Silent before a consonant and at the end: John, oh.
                if isVowel(index + 1) || at(index + 1) == "y" {
                    emit(.h, index, index + 1)
                }
                next = index + 1
            case "x":
                // xylophone; box
                if index == 0 {
                    emit(.z, index, index + 1)
                } else {
                    emit(.k, index, index + 1)
                    emit(.s, index, index + 1)
                }
                next = index + 1
            default:
                next = nil
            }
            if let next {
                index = next
            } else if let sound = Self.plainLetters[letter] {
                let end = runEnd(index)
                emit(sound, index, end)
                index = end
            } else {
                index += 1
            }
        }

        // One sound spelled across two rules - the S and soft C of
        // "science" - is still one sound.
        var merged: [SpelledConsonant] = []
        for sound in sounds {
            if let last = merged.last, last.sound == sound.sound, last.letters.upperBound == sound.letters.lowerBound {
                merged[merged.count - 1] = SpelledConsonant(
                    sound: last.sound,
                    letters: last.letters.lowerBound..<sound.letters.upperBound
                )
            } else {
                merged.append(sound)
            }
        }
        return merged
    }

    /// Vowel groups, less a silent final E, a silent -ed and a silent -es.
    /// Rough, but the same roughness on both words: a slip keeps the beat of
    /// the word, and a heard word with another beat is another word.
    var syllableCount: Int {
        var groups = 0
        var previousWasVowel = false
        for index in 0..<count {
            let vowel = isVowel(index) || (letters[index] == "y" && !yIsConsonant(index))
            if vowel && !previousWasVowel { groups += 1 }
            previousWasVowel = vowel
        }
        guard groups > 1 else { return 1 }

        func isConsonant(_ index: Int) -> Bool {
            index >= 0 && index < count && !isVowel(index) && letters[index] != "y"
        }
        if count > 2, word.hasSuffix("e"), isConsonant(count - 2),
           !(word.hasSuffix("le") && isConsonant(count - 3)) {
            return groups - 1
        }
        if count > 3, word.hasSuffix("ed"), isConsonant(count - 3),
           letters[count - 3] != "t", letters[count - 3] != "d" {
            return groups - 1
        }
        if count > 3, word.hasSuffix("que") || word.hasSuffix("gue") {
            return groups - 1
        }
        if count > 3, word.hasSuffix("es"), isConsonant(count - 3),
           !"sxzcg".contains(letters[count - 3]),
           !["ch", "sh"].contains(String(letters[(count - 4)..<(count - 2)])) {
            return groups - 1
        }
        return groups
    }

    // MARK: Letters with several readings

    /// Silent first letters and the few words that open with a sound their
    /// spelling hides: gnome, psychology, hour, who, sure.
    private mutating func readOpening() -> Int? {
        if let opening = Self.silentOpenings.first(where: { has($0.letters, at: 0) }) {
            emit(opening.sound, 0, 2)
            return 2
        }
        if letters[0] == "h", Self.silentHPrefixes.contains(where: { word.hasPrefix($0) }) {
            return 1
        }
        if has("who", at: 0) {
            emit(.h, 0, 2)
            return 2
        }
        if word.hasPrefix("sure") || word.hasPrefix("sugar") {
            emit(.sh, 0, 1)
            return 1
        }
        return nil
    }

    private mutating func readB(at index: Int) -> Int? {
        // climb, climbing - but not number
        if at(index - 1) == "m", Self.silentBEndings.contains(tail(from: index + 1)) {
            return index + 1
        }
        // debt, doubt - but not obtain
        if at(index + 1) == "t", Self.silentBStems.contains(where: { word.contains($0) }) {
            return index + 1
        }
        return nil
    }

    private mutating func readC(at index: Int) -> Int {
        if has("cc", at: index) {
            if isAny(index + 2, of: "eiy") {
                emit(.k, index, index + 1)
                emit(.s, index + 1, index + 2)
            } else {
                emit(.k, index, index + 2)
            }
            return index + 2
        }
        // special, ocean
        if index > 0, isAny(index + 1, of: "ie"), isAny(index + 2, of: "aou") {
            emit(.sh, index, index + 2)
            return index + 2
        }
        emit(isAny(index + 1, of: "eiy") ? .s : .k, index, index + 1)
        return index + 1
    }

    private mutating func readD(at index: Int) -> Int? {
        // A past-tense -ed after a consonant letter. It sounds as whatever
        // the sound touching it asks for: its own syllable after T or D, a
        // T after a voiceless sound, a D otherwise - including after a
        // silent letter, as in "sighed".
        guard index == count - 1, at(index - 1) == "e", count >= 5, let before = at(index - 2),
              !Self.vowels.contains(before), before != "y", before != "w"
        else { return nil }

        let last = sounds.last
        let touching = last?.letters.upperBound == index - 1
        if touching, let last, last.sound == .t || last.sound == .d {
            emit(.d, index, index + 1)
        } else if touching, let last, Self.voiceless.contains(last.sound) {
            emit(.t, index - 1, index + 1)
        } else {
            emit(.d, index - 1, index + 1)
        }
        return index + 1
    }

    private mutating func readG(at index: Int) -> Int {
        if has("gh", at: index) {
            // Silent inside a word - night, though, sighed - unless it is
            // one of the few that say F. Anchored at the start: "rough"
            // is inside "through" and "brought" too.
            if index == 0 || word.hasPrefix("spaghett") {
                emit(.g, index, index + 2)
            } else if Self.fGhStems.contains(where: { word.hasPrefix($0) }) {
                emit(.f, index, index + 2)
            }
            return index + 2
        }
        // sign, designer - but not signal
        if has("gn", at: index), Self.silentGnEndings.contains(tail(from: index + 2)) {
            return index + 1
        }
        if has("gue", at: index), index + 3 == count {
            emit(.g, index, index + 3)
            return index + 3
        }
        if has("gu", at: index), isAny(index + 2, of: "aeiy") {
            emit(.g, index, index + 2)
            return index + 2
        }
        if has("gg", at: index) {
            emit(.g, index, index + 2)
            return index + 2
        }
        let hard = Self.hardGStems.contains { has($0, at: index) } || Self.hardGWords.contains { word.contains($0) }
        emit(isAny(index + 1, of: "eiy") && !hard ? .j : .g, index, index + 1)
        return index + 1
    }

    private mutating func readL(at index: Int) -> Int? {
        let previous = at(index - 1)
        let next = at(index + 1)
        // walk, calm, half - but not almost
        if previous == "a", index >= 2, next == "k" || next == "m" || next == "f" {
            return index + 1
        }
        // folk
        if previous == "o", next == "k" {
            return index + 1
        }
        // could, wouldn't - but not shoulder
        if index >= 2, has("ould", at: index - 2), ["", "nt", "ve"].contains(tail(from: index + 2)) {
            return index + 1
        }
        return nil
    }

    private mutating func readN(at index: Int) -> Int? {
        if has("ng", at: index) {
            // change, strange: the G is soft
            if ["e", "es", "ed"].contains(tail(from: index + 2)) {
                emit(.n, index, index + 1)
                emit(.j, index + 1, index + 2)
            } else {
                emit(.ng, index, index + 2)
            }
            return index + 2
        }
        // think, uncle - but not unknown
        let next = at(index + 1)
        let beforeK = (next == "k" && at(index + 2) != "n") || next == "q" || next == "x"
        let beforeHardC = next == "c" && !isAny(index + 2, of: "eiy")
        if beforeK || beforeHardC {
            emit(.ng, index, index + 1)
            return index + 1
        }
        // autumn, column
        if at(index - 1) == "m", ["", "s"].contains(tail(from: index + 1)) {
            return index + 1
        }
        return nil
    }

    private mutating func readQ(at index: Int) -> Int {
        // unique
        if has("que", at: index), index + 3 == count {
            emit(.k, index, index + 3)
            return index + 3
        }
        if has("qu", at: index) {
            emit(.k, index, index + 1)
            emit(.w, index + 1, index + 2)
            return index + 2
        }
        emit(.k, index, index + 1)
        return index + 1
    }

    private mutating func readS(at index: Int) -> Int? {
        if has("ssion", at: index) {
            emit(.sh, index, index + 3)
            return index + 3
        }
        // vision; tension
        if has("sion", at: index) {
            emit(index > 0 && isVowel(index - 1) ? .zh : .sh, index, index + 2)
            return index + 2
        }
        // pressure, issue
        if has("ssu", at: index), isAny(index + 3, of: "re") {
            emit(.sh, index, index + 2)
            return index + 2
        }
        // measure; insure
        if index > 0, has("sur", at: index), isAny(index + 3, of: "ae") {
            emit(isVowel(index - 1) ? .zh : .sh, index, index + 1)
            return index + 1
        }
        if has("sual", at: index) {
            emit(.zh, index, index + 1)
            return index + 1
        }
        return nil
    }

    private mutating func readT(at index: Int) -> Int? {
        // nation; question
        if index > 0, at(index + 1) == "i", isAny(index + 2, of: "aou") {
            emit(at(index - 1) == "s" ? .ch : .sh, index, index + 2)
            return index + 2
        }
        // nature, actual
        if index > 0, at(index + 1) == "u", has("ture", at: index) || isVowel(index + 2) {
            emit(.ch, index, index + 1)
            return index + 1
        }
        // castle, listen
        if at(index - 1) == "s", Self.silentTEndings.contains(tail(from: index + 1)) {
            return index + 1
        }
        return nil
    }

    private mutating func readW(at index: Int) -> Int {
        let silent = Self.silentW.contains { word.hasPrefix($0.word) && index == $0.index }
        // A W after a vowel is part of the vowel - power, flow - except in a
        // few words.
        let startsSound = index == 0 || !isVowel(index - 1) || Self.awWords.contains { word.hasPrefix($0) }
        if !silent, startsSound, isVowel(index + 1) {
            emit(.w, index, index + 1)
        }
        return index + 1
    }

    // MARK: Reading helpers

    private mutating func emit(_ sound: ConsonantSound, _ start: Int, _ end: Int) {
        sounds.append(SpelledConsonant(sound: sound, letters: start..<end))
    }

    private func at(_ index: Int) -> Character? {
        index >= 0 && index < count ? letters[index] : nil
    }

    private func isVowel(_ index: Int) -> Bool {
        at(index).map { Self.vowels.contains($0) } ?? false
    }

    private func isAny(_ index: Int, of set: String) -> Bool {
        at(index).map { set.contains($0) } ?? false
    }

    private func has(_ pattern: String, at index: Int) -> Bool {
        index >= 0 && index <= count && letters[index...].starts(with: pattern)
    }

    private func tail(from index: Int) -> String {
        index >= count ? "" : String(letters[max(0, index)...])
    }

    /// Y is a consonant before a vowel at the start of a word or after a
    /// consonant: yes, canyon. Elsewhere it is a vowel: happy, play.
    private func yIsConsonant(_ index: Int) -> Bool {
        at(index) == "y" && isVowel(index + 1) && (index == 0 || !isVowel(index - 1))
    }

    /// The end of a run of one repeated letter, so "ll" and "tt" are one
    /// sound.
    private func runEnd(_ index: Int) -> Int {
        var end = index + 1
        while end < count, letters[end] == letters[index] { end += 1 }
        return end
    }

    // MARK: Word lists

    private static let silentOpenings: [(letters: String, sound: ConsonantSound)] = [
        ("gn", .n), ("ps", .s), ("pn", .n), ("mn", .n)
    ]
    /// Spellings that always read as one sound.
    private static let spellings: [(letters: String, sound: ConsonantSound)] = [
        ("tch", .ch), ("dg", .j), ("ck", .k), ("sh", .sh), ("th", .th), ("ph", .f), ("wh", .w),
        ("wr", .r), ("rh", .r), ("kh", .k), ("kn", .n)
    ]
    /// Letters read as themselves when no rule above claims them, a doubled
    /// letter as one sound.
    private static let plainLetters: [Character: ConsonantSound] = [
        "b": .b, "d": .d, "f": .f, "j": .j, "k": .k, "l": .l, "m": .m, "n": .n, "p": .p, "r": .r,
        "s": .s, "t": .t, "v": .v, "y": .y, "z": .z
    ]
    private static let voiceless: Set<ConsonantSound> = [.p, .k, .f, .s, .sh, .ch, .th]

    /// CH said as K. Words opening CHR or CHL need no entry.
    private static let greekChPrefixes = [
        "chaos", "chaotic", "charact", "chem", "chord", "chorus", "choir", "charism", "chasm", "cholest",
        "echo", "stomach", "techn", "orchestr", "mechan", "psych", "architect", "anchor", "monarch", "anarch",
        "archiv", "archaeo", "orchid"
    ]
    private static let greekChWords: Set<String> = [
        "tech", "ache", "aches", "ached", "aching", "headache", "headaches"
    ]
    /// CH said as SH.
    private static let frenchChPrefixes = [
        "machin", "chef", "parachut", "brochur", "champagn", "chandelier", "chicago", "michigan",
        "mustach", "moustach", "chauffeur", "chalet", "chateau"
    ]
    private static let frenchChWords: Set<String> = ["chic", "chute", "cliche", "niche"]

    private static let silentHPrefixes = ["hour", "honest", "honor", "honour", "heir"]
    private static let fGhStems = ["rough", "tough", "enough", "laugh", "cough", "trough"]
    /// G before E, I or Y that stays hard.
    private static let hardGStems = [
        "get", "giv", "gift", "girl", "girth", "gear", "geese", "geek", "gecko", "gild", "gill", "gimm",
        "gizm", "gidd"
    ]
    private static let hardGWords = ["begin", "tiger", "eager", "burger"]
    private static let silentW: [(word: String, index: Int)] = [("two", 1), ("sword", 1), ("answer", 3)]
    private static let silentBStems = ["debt", "doubt", "subtl"]
    /// W after a vowel that is still a W.
    private static let awWords = ["away", "aware", "awake", "award", "awoke", "reward"]
    private static let silentTEndings: Set<String> = [
        "le", "les", "led", "ling", "en", "ens", "ened", "ening", "ener", "eners"
    ]
    private static let silentBEndings: Set<String> = ["", "s", "ed", "ing"]
    private static let silentGnEndings: Set<String> = ["", "s", "ed", "ing", "er", "ers"]
}
