import SwiftUI
import SwiftData

#Preview("Recording Detail, Mock Data") {
    struct PreviewWrapper: View {
        let recordingId: String
        let container: ModelContainer

        init() {
            let schema = Schema([
                Recording.self,
                Prompt.self,
                UserGoal.self,
                UserSettings.self,
                Achievement.self,
                CurriculumProgress.self,
                RecordingGroup.self,
                Story.self,
                StoryFolder.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: schema, configurations: [config])
            self.container = container

            let context = container.mainContext

            let prompt = Prompt(
                id: UUID().uuidString,
                text: "Tell me about a time you overcame a significant challenge and what you learned from it.",
                category: "Personal Growth",
                difficulty: .medium
            )
            context.insert(prompt)

            let mockId = UUID()
            let recording = Recording(
                id: mockId,
                date: Date().addingTimeInterval(-3600),
                prompt: prompt,
                targetDuration: 120,
                actualDuration: 87.5,
                transcriptionText: "So um I think one of the biggest challenges I faced was when I had to um present our quarterly results to the entire company. I was really nervous because um you know public speaking has always been something I've struggled with. But I prepared extensively, practiced in front of the mirror, and asked colleagues for feedback. The presentation went well and I learned that thorough preparation can really help overcome anxiety. Since then I've volunteered for more speaking opportunities and each time it gets a little easier.",
                transcriptionWords: PreviewWrapper.mockWords(),
                analysis: PreviewWrapper.mockAnalysis(),
                isProcessing: false,
                isFavorite: true
            )
            context.insert(recording)

            let settings = UserSettings()
            context.insert(settings)

            try? context.save()
            self.recordingId = mockId.uuidString
        }

        var body: some View {
            NavigationStack {
                RecordingDetailView(recordingId: recordingId)
            }
            .modelContainer(container)
            .environment(AudioService())
            .environment(SpeechService())
            .environment(LLMService())
            .preferredColorScheme(.dark)
        }

        static func mockWords() -> [TranscriptionWord] {
            let text = "So um I think one of the biggest challenges I faced was when I had to um present our quarterly results to the entire company I was really nervous because um you know public speaking has always been something I've struggled with But I prepared extensively practiced in front of the mirror and asked colleagues for feedback The presentation went well and I learned that thorough preparation can really help overcome anxiety Since then I've volunteered for more speaking opportunities and each time it gets a little easier"
            let words = text.components(separatedBy: " ")
            let fillers: Set<String> = ["um", "uh", "you", "know", "like", "So"]
            var time: TimeInterval = 0.5
            return words.map { word in
                let duration = Double.random(in: 0.15...0.45)
                let w = TranscriptionWord(
                    word: word,
                    start: time,
                    end: time + duration,
                    confidence: Double.random(in: 0.85...0.99),
                    isFiller: fillers.contains(word),
                    isVocabWord: ["extensively", "quarterly", "volunteered", "preparation", "anxiety"].contains(word),
                    isPrimarySpeaker: true
                )
                time += duration + Double.random(in: 0.05...0.25)
                return w
            }
        }

        static func mockAnalysis() -> SpeechAnalysis {
            SpeechAnalysis(
                fillerWords: [
                    FillerWord(word: "um", count: 3, timestamps: [2.1, 8.4, 22.0]),
                    FillerWord(word: "you know", count: 1, timestamps: [25.3]),
                    FillerWord(word: "so", count: 1, timestamps: [0.5])
                ],
                totalWords: 89,
                wordsPerMinute: 142.0,
                pauseCount: 7,
                averagePauseLength: 0.6,
                strategicPauseCount: 4,
                hesitationPauseCount: 3,
                clarity: 72.0,
                speechScore: SpeechScore(
                    overall: 74,
                    subscores: SpeechSubscores(
                        clarity: 78,
                        pace: 82,
                        fillerUsage: 65,
                        pauseQuality: 71,
                        vocalVariety: 68,
                        delivery: 73,
                        vocabulary: 76,
                        structure: 20,
                        relevance: 80
                    ),
                    trend: .improving
                ),
                vocabWordsUsed: [
                    VocabWordUsage(word: "extensively", count: 1),
                    VocabWordUsage(word: "quarterly", count: 1),
                    VocabWordUsage(word: "volunteered", count: 1)
                ],
                volumeMetrics: VolumeMetrics(
                    averageLevel: -18.5,
                    peakLevel: -6.2,
                    dynamicRange: 12.3,
                    monotoneScore: 62,
                    energyScore: 71
                ),
                vocabComplexity: VocabComplexity(
                    uniqueWordCount: 68,
                    uniqueWordRatio: 0.76,
                    averageWordLength: 4.8,
                    longWordCount: 12,
                    longWordRatio: 0.13,
                    complexityScore: 72
                ),
                sentenceAnalysis: SentenceAnalysis(
                    totalSentences: 6,
                    incompleteSentences: 1,
                    restartCount: 0,
                    averageSentenceLength: 14.8,
                    longestSentence: 22,
                    structureScore: 70
                ),
                promptRelevanceScore: 80,
                wpmTimeSeries: [
                    WPMDataPoint(timestamp: 10, wpm: 128, wordCount: 21),
                    WPMDataPoint(timestamp: 20, wpm: 145, wordCount: 24),
                    WPMDataPoint(timestamp: 30, wpm: 155, wordCount: 26),
                    WPMDataPoint(timestamp: 40, wpm: 138, wordCount: 23),
                    WPMDataPoint(timestamp: 50, wpm: 150, wordCount: 25),
                    WPMDataPoint(timestamp: 60, wpm: 142, wordCount: 24),
                    WPMDataPoint(timestamp: 70, wpm: 135, wordCount: 22),
                    WPMDataPoint(timestamp: 80, wpm: 148, wordCount: 25)
                ],
                pitchMetrics: PitchMetrics(
                    f0Mean: 165, f0StdDev: 28,
                    f0Min: 95, f0Max: 280,
                    f0RangeSemitones: 18.7,
                    pitchVariationScore: 68,
                    declinationRate: -0.3,
                    voicedFrameRatio: 0.62
                ),
                rateVariation: RateVariationMetrics(
                    rateCV: 0.18, articulationRate: 168,
                    rateRange: 55, rateVariationScore: 65
                ),
                emphasisMetrics: EmphasisMetrics(
                    emphasisCount: 8, emphasisPerMinute: 5.5, distributionScore: 62
                ),
                energyArc: EnergyArcMetrics(
                    openingEnergy: 0.55, bodyEnergy: 0.72,
                    closingEnergy: 0.65, hasClimax: true, arcScore: 70
                ),
                textQuality: TextQualityMetrics(
                    hedgeWordCount: 3, hedgeWordRatio: 0.034,
                    powerWordCount: 4, rhetoricalDeviceCount: 1,
                    transitionVariety: 3,
                    weakPhraseCount: 2, weakPhraseRatio: 0.022,
                    repeatedSentenceStartCount: 1,
                    rhetoricalQuestionCount: 0, callToActionCount: 0,
                    authorityScore: 65, craftScore: 68,
                    concisenessScore: 72, engagementScore: 66
                )
            )
        }
    }

    return PreviewWrapper()
}
