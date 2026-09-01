import AVFoundation
import UIKit

@Observable
class PronunciationService: NSObject {
    var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak a word, sentence, or short paragraph for the user to model.
    /// Longer text uses a slightly slower rate so each word stays clear.
    func speak(word: String) {
        stop()
        let cleaned = Self.stripPunctuation(word)
        guard !cleaned.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: cleaned)
        let tokenCount = cleaned.split(whereSeparator: { $0.isWhitespace }).count
        // Slightly slower on multi-word text so each syllable stays modelable.
        utterance.rate = tokenCount <= 3 ? 0.35 : 0.32
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    static func canDefine(_ word: String) -> Bool {
        let cleaned = stripPunctuation(word)
        guard !cleaned.isEmpty else { return false }
        // Dictionary lookup is for single tokens — not full sentences.
        guard !cleaned.contains(where: { $0.isWhitespace }) else { return false }
        return UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: cleaned)
    }

    static func stripPunctuation(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension PronunciationService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
