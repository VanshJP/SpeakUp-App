import Foundation
import PDFKit
import Testing
@testable import SpeakUp

struct JournalExportTests {
    /// The export runs fetch, snapshot and layout in one detached task. This
    /// pins that the renderer works there and still prints each take's lines.
    @Test func rendersTheJournalOffTheMainActor() async throws {
        let entries = JournalExportFixture.recordings().map(JournalEntry.init)
        let achievements = [JournalAchievement(icon: "star.fill", title: "First Steps")]

        let data = await Task.detached {
            JournalExportService().generatePDF(entries: entries, dateRange: "All Time", achievements: achievements)
        }.value

        let text = try #require(PDFDocument(data: data)?.string)
        #expect(text.contains("Total Sessions: 3"))
        #expect(text.contains("Achievements Unlocked (1)"))
        #expect(text.contains("Session 1: Tell me about your weekend"))
        #expect(text.contains("Category: Storytelling"))
        #expect(text.contains("Score: 62/100"))
        #expect(text.contains("Session 2: My take"))
        #expect(text.contains("Mode: pace"))
        #expect(text.contains("Session 3: A story"))
        #expect(text.contains("hello world"))
    }
}

/// Unsaved takes, oldest first: two analyzed (one from a prompt with a words
/// transcript, one drill with a long text-only transcript) and one unanalyzed.
@MainActor
enum JournalExportFixture {
    static func recordings() -> [Recording] {
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let prompt = Prompt(id: "p1", text: "Tell me about your weekend", category: "Storytelling", difficulty: .medium)

        let first = Recording(
            date: base,
            prompt: prompt,
            actualDuration: 75,
            transcriptionWords: [
                TranscriptionWord(word: "hello", start: 0, end: 0.4),
                TranscriptionWord(word: "world", start: 0.5, end: 0.9)
            ],
            analysis: SpeechAnalysis(
                fillerWords: [FillerWord(word: "um", count: 4), FillerWord(word: "like", count: 2)],
                totalWords: 180,
                wordsPerMinute: 144.6,
                pauseCount: 7,
                speechScore: SpeechScore(
                    overall: 62,
                    subscores: SpeechSubscores(clarity: 70, pace: 55, fillerUsage: 48, pauseQuality: 66)
                ),
                vocabWordsUsed: [VocabWordUsage(word: "strategic", count: 1)]
            )
        )

        let paragraph = Array(repeating: "Practice makes the words come easier every single day.", count: 40)
            .joined(separator: " ")
        let second = Recording(
            date: base.addingTimeInterval(86_400),
            actualDuration: 190,
            transcriptionText: Array(repeating: paragraph, count: 12).joined(separator: "\n"),
            analysis: SpeechAnalysis(
                fillerWords: [FillerWord(word: "so", count: 3)],
                totalWords: 420,
                wordsPerMinute: 132,
                pauseCount: 12,
                speechScore: SpeechScore(
                    overall: 75,
                    subscores: SpeechSubscores(clarity: 78, pace: 72, fillerUsage: 70, pauseQuality: 64)
                )
            ),
            customTitle: "My take",
            drillMode: "pace"
        )

        let third = Recording(date: base.addingTimeInterval(2 * 86_400), actualDuration: 30)
        third.storyTitle = "A story"

        return [first, second, third]
    }
}
