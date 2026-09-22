import AVFoundation
import UIKit

@Observable
class PronunciationService: NSObject {
    var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    /// The line `isSpeaking` describes. Held strongly so a finished line's
    /// identity can never be reused by the next one. See `utteranceDidEnd(_:)`.
    @ObservationIgnored private var speakingUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak a word, sentence, or short paragraph for the user to model.
    /// Longer text uses a slightly slower rate so each word stays clear.
    func speak(word: String) {
        let cleaned = Self.stripPunctuation(word)
        let tokenCount = cleaned.split(whereSeparator: { $0.isWhitespace }).count
        // Slightly slower on multi-word text so each syllable stays modelable.
        speak(text: cleaned, rate: tokenCount <= 3 ? 0.35 : 0.32)
    }

    /// Speak a full phrase or passage (shadowing model). Keeps punctuation so
    /// prosody has something to chew on; slower than system default.
    func speak(text: String, rate: Float = 0.42) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = rate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speakingUtterance = utterance
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingUtterance = nil
        isSpeaking = false
    }

    /// Only the line playing now may clear `isSpeaking`. Speaking a new line
    /// stops the old one, and the old one's cancel callback lands a hop later
    /// - after the new line has set `isSpeaking` - which reported the new line
    /// finished the moment it began: guided Calm started its hold mid-sentence,
    /// and Read Aloud reopened the mic under the model line.
    private func utteranceDidEnd(_ id: ObjectIdentifier) {
        guard let speakingUtterance, ObjectIdentifier(speakingUtterance) == id else { return }
        self.speakingUtterance = nil
        isSpeaking = false
    }

    // MARK: - Spoken guidance

    /// Spoken-audio playback for a guided exercise, so the voice is heard with
    /// the ring switch off. The synthesiser otherwise inherits whatever the
    /// last practice screen left behind - often the ambient category the cue
    /// chirps use, which the ring switch silences. Mixes with the user's own
    /// audio rather than stopping it.
    ///
    /// The category is set here, on the main actor, so it is ordered with
    /// `endGuidance`; only activation, which blocks until the audio server
    /// answers, leaves it. An activation that lands late only activates.
    func prepareForGuidance() async {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? await Task.detached(priority: .userInitiated) {
            try AVAudioSession.sharedInstance().setActive(true)
        }.value
    }

    /// Hands the session back to the ambient category the cue chirps expect,
    /// so they respect the ring switch again after a guided exercise.
    /// Synchronous, so a screen that configures its own session straight
    /// after this one - a lesson's next recording - cannot be overwritten.
    func endGuidance() {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
    }

    static func canDefine(_ word: String) -> Bool {
        let cleaned = stripPunctuation(word)
        guard !cleaned.isEmpty else { return false }
        // Dictionary lookup is for single tokens - not full sentences.
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
        let ended = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.utteranceDidEnd(ended)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let ended = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.utteranceDidEnd(ended)
        }
    }
}
