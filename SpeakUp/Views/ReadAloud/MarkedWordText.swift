import SwiftUI

// MARK: - Marked Word Text

/// A word with the letters of one consonant marked, built as a single `Text`
/// so it wraps, scales and reads under VoiceOver like the words around it.
///
/// Colour and underline only. A marked letter drawn heavier or larger would
/// change the word's width and re-flow everything after it.
enum MarkedWordText {
    /// - Parameters:
    ///   - letters: Character offsets into `word`, as `ConsonantAnalyzer`
    ///     reports them. Nil or out of range draws the word unmarked.
    static func make(_ word: String, marking letters: Range<Int>?, base: Color, mark: Color) -> Text {
        let characters = Array(word)
        guard let letters, !letters.isEmpty, letters.lowerBound >= 0, letters.upperBound <= characters.count else {
            return Text(verbatim: word).foregroundStyle(base)
        }

        let before = Text(verbatim: String(characters[..<letters.lowerBound])).foregroundStyle(base)
        let marked = Text(verbatim: String(characters[letters]))
            .foregroundStyle(mark)
            .underline(true, color: mark)
        let after = Text(verbatim: String(characters[letters.upperBound...])).foregroundStyle(base)
        return Text("\(before)\(marked)\(after)")
    }
}
