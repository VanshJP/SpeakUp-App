#if DEBUG
import Foundation
import SwiftData

/// Populates the store with a realistic practice history so App Store captures
/// show the app in use rather than in its empty state. Runs only when the app
/// is launched with `-seedScreenshotData`, and only when no recordings exist.
///
/// The data is written directly rather than produced by recording, because the
/// simulator has no usable microphone and the screenshot set needs a three-week
/// upward trend that no capture session could perform live.
@MainActor
enum ScreenshotSeeder {
    static let launchArgument = "-seedScreenshotData"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func seedIfRequested(context: ModelContext) {
        guard isRequested else { return }

        let existing = (try? context.fetchCount(FetchDescriptor<Recording>())) ?? 0
        guard existing == 0 else { return }

        skipOnboarding(context: context)
        let story = insertStory(context: context)
        insertRecordings(context: context, story: story)

        try? context.save()
    }

    // MARK: - Onboarding

    private static func skipOnboarding(context: ModelContext) {
        let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
        guard let settings else { return }
        settings.hasCompletedOnboarding = true
        settings.userName = "Vansh"
        settings.targetWPM = 150
    }

    // MARK: - Story

    private static func insertStory(context: ModelContext) -> Story {
        let story = Story(
            title: "Wedding toast",
            content: """
            I have known the groom since we were fifteen, which means I have \
            watched him talk his way into, and out of, almost everything. But \
            the first time he mentioned her, he could not finish the sentence. \
            He just grinned at the floor.

            That is when I knew. He has never once been lost for words — until \
            her. So here is to the person who finally made my friend stop \
            talking, and to the two of them, who now get to spend a lifetime \
            interrupting each other.
            """,
            tags: [
                StoryTag(type: .topic, value: "Wedding"),
                StoryTag(type: .topic, value: "Toast"),
            ],
            createdAt: .now.addingTimeInterval(-26 * 86_400),
            updatedAt: .now.addingTimeInterval(-2 * 86_400),
            practiceCount: 4,
            occasion: "Wedding",
            estimatedDurationSeconds: 95,
            lastPracticeDate: .now.addingTimeInterval(-2 * 86_400),
            bestScore: 84
        )
        context.insert(story)
        return story
    }

    // MARK: - Recordings

    /// Twelve sessions across 24 days, scored 58 → 84. The climb is deliberate:
    /// the progress screens are only worth capturing if the trend has a shape.
    private static func insertRecordings(context: ModelContext, story: Story) {
        let sessions: [(daysAgo: Int, score: Int, wpm: Double, title: String, story: Bool)] = [
            (24, 58, 187, "Tell me about yourself", false),
            (22, 61, 181, "Describe a time you failed", false),
            (20, 63, 178, "Wedding toast", true),
            (17, 66, 172, "Why should we hire you?", false),
            (15, 68, 169, "Explain your work to a child", false),
            (13, 70, 166, "Wedding toast", true),
            (10, 73, 161, "Pitch your side project in 60s", false),
            (8, 75, 158, "Describe a time you failed", false),
            (6, 78, 155, "Wedding toast", true),
            (4, 80, 152, "Walk me through a hard decision", false),
            (2, 84, 149, "Wedding toast", true),
            (0, 82, 151, "Tell me about yourself", false),
        ]

        for session in sessions {
            let text = session.story ? toastTranscript : interviewTranscript
            let recording = Recording(
                date: .now.addingTimeInterval(-Double(session.daysAgo) * 86_400 - 3_600),
                targetDuration: 90,
                actualDuration: session.story ? 94 : 71,
                transcriptionText: text,
                transcriptionWords: words(from: text),
                analysis: analysis(score: session.score, wpm: session.wpm, text: text),
                customTitle: session.title
            )
            if session.story {
                recording.storyId = story.id
                recording.storyTitle = story.title
            }
            context.insert(recording)
        }
    }

    // MARK: - Analysis

    private static func analysis(score: Int, wpm: Double, text: String) -> SpeechAnalysis {
        // Sub-scores are spread around the overall rather than set equal to it,
        // so the radar reads as a real profile with a weak axis to coach.
        func near(_ delta: Int) -> Int { min(97, max(35, score + delta)) }

        return SpeechAnalysis(
            fillerWords: fillerUsage(in: text),
            totalWords: Int(wpm * 71 / 60),
            wordsPerMinute: wpm,
            pauseCount: 9,
            averagePauseLength: 0.62,
            strategicPauseCount: 6,
            hesitationPauseCount: 3,
            clarity: Double(near(4)),
            speechScore: SpeechScore(
                overall: score,
                subscores: SpeechSubscores(
                    clarity: near(6),
                    pace: near(-3),
                    fillerUsage: near(-9),
                    pauseQuality: near(2),
                    vocalVariety: near(-6),
                    delivery: near(3),
                    vocabulary: near(8),
                    structure: near(-1),
                    relevance: near(5)
                ),
                trend: .improving
            ),
            vocabWordsUsed: vocabUsage(in: text),
            volumeMetrics: VolumeMetrics(
                averageLevel: 0.42,
                peakLevel: 0.81,
                dynamicRange: 0.39,
                monotoneScore: near(-6),
                energyScore: near(1)
            ),
            promptRelevanceScore: near(5),
            wpmTimeSeries: wpmSeries(around: wpm)
        )
    }

    /// A visible arc rather than a flat line — a pace chart with no shape sells
    /// nothing, which is the whole point of the slide it appears on.
    private static func wpmSeries(around wpm: Double) -> [WPMDataPoint] {
        let shape: [Double] = [-14, 9, 21, 4, -11, -19, 6, 17, 2, -8]
        return shape.enumerated().map { index, offset in
            WPMDataPoint(
                timestamp: Double(index) * 7 + 3.5,
                wpm: wpm + offset,
                wordCount: Int((wpm + offset) * 7 / 60)
            )
        }
    }

    // MARK: - Transcript

    private static let interviewTranscript = """
    So, um, the honest answer is that I did not start out wanting to run the \
    team. I was, like, perfectly happy shipping features. What changed was a \
    project that went sideways — we missed the date by six weeks, and, you \
    know, nobody could say exactly when it had gone wrong. That was the part \
    that bothered me. So I started writing the decisions down, um, every week, \
    and sharing them. Six months later that habit was the reason we caught the \
    next slip in four days instead of six weeks.
    """

    private static let toastTranscript = """
    I have known the groom since we were fifteen, which means, um, I have \
    watched him talk his way into and out of basically everything. But the \
    first time he mentioned her, he just, like, stopped. He grinned at the \
    floor and could not finish the sentence. That is, you know, when I knew. \
    He has never once been lost for words until her. So here is to the two of \
    them, and to a lifetime of interrupting each other.
    """

    /// The one place a word is classified. The inline highlights, the filler
    /// tally, and the vocab footer all read from this, so a word cannot be
    /// green in the transcript and missing from the summary underneath it.
    private static let fillers: Set<String> = ["um", "like", "you", "know"]
    private static let vocab: Set<String> = ["sideways", "habit", "deliberate", "interrupting"]

    private static func bareWords(in text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
    }

    /// Counted from the same marked words the transcript highlights.
    private static func vocabUsage(in text: String) -> [VocabWordUsage] {
        var counts: [String: Int] = [:]
        for word in bareWords(in: text) where vocab.contains(word) {
            counts[word, default: 0] += 1
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { VocabWordUsage(word: $0.key, count: $0.value) }
    }

    /// "you" and "know" are marked separately so both highlight inline, but
    /// they report as the single phrase a user would recognise.
    private static func fillerUsage(in text: String) -> [FillerWord] {
        var counts: [String: Int] = [:]
        for word in bareWords(in: text) where fillers.contains(word) {
            counts[word, default: 0] += 1
        }
        var result: [FillerWord] = []
        for word in ["um", "like"] where counts[word, default: 0] > 0 {
            result.append(FillerWord(word: word, count: counts[word]!, timestamps: [4.2, 19.8]))
        }
        if let phrase = counts["know"], phrase > 0 {
            result.append(FillerWord(word: "you know", count: phrase, timestamps: [27.9]))
        }
        return result
    }

    /// Every session carries word timings so the transcript screen can mark
    /// fillers inline — a transcript with nothing marked demonstrates nothing.
    private static func words(from text: String) -> [TranscriptionWord] {
        return text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .map(String.init)
            .enumerated()
            .map { index, word in
                let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                return TranscriptionWord(
                    word: word,
                    start: Double(index) * 0.42,
                    end: Double(index) * 0.42 + 0.34,
                    confidence: 0.94,
                    isFiller: fillers.contains(bare),
                    isVocabWord: vocab.contains(bare)
                )
            }
    }
}
#endif
