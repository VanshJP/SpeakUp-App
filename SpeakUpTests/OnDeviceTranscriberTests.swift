import AVFoundation
import Foundation
import Speech
import Testing
@testable import SpeakUp

@MainActor
struct OnDeviceTranscriberTests {
    private typealias Run = OnDeviceTranscriber.TimedRun

    @Test func singleWordRunsKeepPunctuationAndDropSpaces() {
        let words = OnDeviceTranscriber.words(from: [
            Run(text: "Every", start: 1.68, end: 1.98, confidence: 0.97),
            Run(text: " day,", start: 1.98, end: 2.52, confidence: 0.57)
        ])

        #expect(words.map(\.word) == ["Every", "day,"])
        #expect(words[1].start == 1.98)
        #expect(words[1].end == 2.52)
        #expect(words[1].confidence == 0.57)
    }

    @Test func multiWordRunSharesItsTimeByLength() {
        // DictationTranscriber groups words into one run.
        let words = OnDeviceTranscriber.words(from: [Run(text: "a lot of ", start: 2.0, end: 2.6, confidence: 0.9)])

        #expect(words.map(\.word) == ["a", "lot", "of"])
        #expect(words.first?.start == 2.0)
        #expect(abs((words.last?.end ?? 0) - 2.6) < 0.0001)
        #expect(words[1].end - words[1].start > words[0].end - words[0].start)
    }

    @Test func barePunctuationJoinsThePreviousWord() {
        let words = OnDeviceTranscriber.words(from: [
            Run(text: "Yeah", start: 0.45, end: 0.87, confidence: 0.89),
            Run(text: ", ", start: 0.87, end: 0.87, confidence: 0.89),
            Run(text: "this ", start: 0.87, end: 1.08, confidence: 0.95)
        ])

        #expect(words.map(\.word) == ["Yeah,", "this"])
        #expect(words[0].end == 0.87)
    }

    @Test func runWithoutTimingNeverRewindsTheClock() {
        let words = OnDeviceTranscriber.words(from: [
            Run(text: "one", start: 1.0, end: 1.4, confidence: nil),
            Run(text: " two", start: nil, end: nil, confidence: nil),
            Run(text: " three", start: 0.2, end: 1.9, confidence: nil)
        ])

        #expect(words.map(\.word) == ["one", "two", "three"])
        #expect(words[1].start == 1.4)
        #expect(words[2].start >= words[1].end)
        #expect(words.allSatisfy { $0.confidence == 1 })
    }

    /// End to end on the real engine: a synthesized take comes back as timed
    /// words, with its hesitations tagged where the device keeps them
    /// (`SpeechTranscriber`; the simulator and iPhone 11-class phones fall
    /// back to `DictationTranscriber`, which strips them). Returns early when
    /// the model is not installed rather than downloading in a test run, and
    /// in the simulator, which cannot transcribe.
    @Test(.timeLimit(.minutes(1)))
    func transcribesATakeEndToEnd() async throws {
        guard await !OnDeviceTranscriber.needsDownload() else { return }

        let url = try await Self.synthesize(
            "So, um, I was thinking about the project. Um, it is kind of hard to explain, you know."
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let pcm = try #require(MonoPCM.decode(url: url))
        let transcript: OnDeviceTranscriber.Transcript
        do {
            transcript = try await OnDeviceTranscriber.transcribe(pcm)
        } catch OnDeviceTranscriberError.unsupported {
            return // The simulator lists no audio formats for either transcriber.
        }
        let tagged = FillerDetectionPipeline.tagFillers(in: transcript.words)

        #expect(transcript.backend == (SpeechTranscriber.isAvailable ? .speechTranscriber : .dictationTranscriber))
        #expect(tagged.count >= 12)
        #expect(tagged.contains { $0.isFiller && $0.word.lowercased().hasPrefix("you") })
        #expect(zip(tagged, tagged.dropFirst()).allSatisfy { $0.start <= $1.start && $0.end <= $1.start + 0.001 })
        if transcript.backend == .speechTranscriber {
            #expect(tagged.contains { $0.isFiller && $0.word.lowercased().hasPrefix("um") })
        }
    }

    private static func synthesize(_ text: String) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-\(UUID().uuidString).caf")
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        var file: AVAudioFile?

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if !finished {
                        finished = true
                        continuation.resume()
                    }
                    return
                }
                if file == nil {
                    file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings)
                }
                try? file?.write(from: pcm)
            }
        }
        file = nil
        return url
    }
}
