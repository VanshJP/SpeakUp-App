import Foundation
import SwiftUI

// MARK: - Transcription Types

struct TranscriptionWord: Codable, Identifiable {
    var id: UUID = UUID()
    let word: String
    let start: TimeInterval
    let end: TimeInterval
    var confidence: Double?
    var isFiller: Bool
    var isVocabWord: Bool

    init(word: String, start: TimeInterval, end: TimeInterval, confidence: Double? = nil, isFiller: Bool = false, isVocabWord: Bool = false) {
        self.word = word
        self.start = start
        self.end = end
        self.confidence = confidence
        self.isFiller = isFiller
        self.isVocabWord = isVocabWord
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        word = try container.decode(String.self, forKey: .word)
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        isFiller = try container.decodeIfPresent(Bool.self, forKey: .isFiller) ?? false
        isVocabWord = try container.decodeIfPresent(Bool.self, forKey: .isVocabWord) ?? false
    }

    var duration: TimeInterval {
        end - start
    }
}

struct FillerWord: Codable, Identifiable {
    var id: UUID = UUID()
    let word: String
    var count: Int
    var timestamps: [TimeInterval]
    
    init(word: String, count: Int = 0, timestamps: [TimeInterval] = []) {
        self.word = word
        self.count = count
        self.timestamps = timestamps
    }
}

// MARK: - Vocab Word Usage

struct VocabWordUsage: Codable, Identifiable {
    var id: UUID = UUID()
    let word: String
    var count: Int

    init(word: String, count: Int = 0) {
        self.word = word
        self.count = count
    }
}

// MARK: - Volume Metrics

struct VolumeMetrics: Codable {
    var averageLevel: Float
    var peakLevel: Float
    var dynamicRange: Float
    var monotoneScore: Int // 0-100, higher = more variation (good)
    var energyScore: Int // 0-100
    var levelSamples: [Float]?

    init(
        averageLevel: Float = 0,
        peakLevel: Float = 0,
        dynamicRange: Float = 0,
        monotoneScore: Int = 0,
        energyScore: Int = 0,
        levelSamples: [Float]? = nil
    ) {
        self.averageLevel = averageLevel
        self.peakLevel = peakLevel
        self.dynamicRange = dynamicRange
        self.monotoneScore = monotoneScore
        self.energyScore = energyScore
        self.levelSamples = levelSamples
    }
}

// MARK: - Vocabulary Complexity

struct VocabComplexity: Codable {
    var uniqueWordCount: Int
    var uniqueWordRatio: Double
    var averageWordLength: Double
    var longWordCount: Int
    var longWordRatio: Double
    var repeatedPhrases: [RepeatedPhrase]
    var complexityScore: Int // 0-100

    init(
        uniqueWordCount: Int = 0,
        uniqueWordRatio: Double = 0,
        averageWordLength: Double = 0,
        longWordCount: Int = 0,
        longWordRatio: Double = 0,
        repeatedPhrases: [RepeatedPhrase] = [],
        complexityScore: Int = 0
    ) {
        self.uniqueWordCount = uniqueWordCount
        self.uniqueWordRatio = uniqueWordRatio
        self.averageWordLength = averageWordLength
        self.longWordCount = longWordCount
        self.longWordRatio = longWordRatio
        self.repeatedPhrases = repeatedPhrases
        self.complexityScore = complexityScore
    }
}

struct RepeatedPhrase: Codable, Identifiable {
    var id: UUID = UUID()
    let phrase: String
    let count: Int
}

// MARK: - Sentence Analysis

struct SentenceAnalysis: Codable {
    var totalSentences: Int
    var incompleteSentences: Int
    var restartCount: Int
    var averageSentenceLength: Double
    var longestSentence: Int
    var structureScore: Int // 0-100
    var restartExamples: [String]

    init(
        totalSentences: Int = 0,
        incompleteSentences: Int = 0,
        restartCount: Int = 0,
        averageSentenceLength: Double = 0,
        longestSentence: Int = 0,
        structureScore: Int = 0,
        restartExamples: [String] = []
    ) {
        self.totalSentences = totalSentences
        self.incompleteSentences = incompleteSentences
        self.restartCount = restartCount
        self.averageSentenceLength = averageSentenceLength
        self.longestSentence = longestSentence
        self.structureScore = structureScore
        self.restartExamples = restartExamples
    }
}

// MARK: - WPM Data Point

struct WPMDataPoint: Codable, Identifiable {
    var id: UUID = UUID()
    let timestamp: TimeInterval  // Seconds into recording (segment midpoint)
    let wpm: Double              // WPM for this segment
    let wordCount: Int           // Words spoken in this segment

    init(timestamp: TimeInterval, wpm: Double, wordCount: Int) {
        self.timestamp = timestamp
        self.wpm = wpm
        self.wordCount = wordCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        wpm = try container.decode(Double.self, forKey: .wpm)
        wordCount = try container.decode(Int.self, forKey: .wordCount)
    }
}

// MARK: - Speech Analysis

struct SpeechAnalysis: Codable {
    var fillerWords: [FillerWord]
    var totalWords: Int
    var wordsPerMinute: Double
    var pauseCount: Int
    var averagePauseLength: TimeInterval
    var strategicPauseCount: Int
    var hesitationPauseCount: Int
    var clarity: Double // 0-100
    var speechScore: SpeechScore
    var vocabWordsUsed: [VocabWordUsage]
    var volumeMetrics: VolumeMetrics?
    var vocabComplexity: VocabComplexity?
    var sentenceAnalysis: SentenceAnalysis?
    var promptRelevanceScore: Int?
    var wpmTimeSeries: [WPMDataPoint]?

    init(
        fillerWords: [FillerWord] = [],
        totalWords: Int = 0,
        wordsPerMinute: Double = 0,
        pauseCount: Int = 0,
        averagePauseLength: TimeInterval = 0,
        strategicPauseCount: Int = 0,
        hesitationPauseCount: Int = 0,
        clarity: Double = 0,
        speechScore: SpeechScore = SpeechScore(),
        vocabWordsUsed: [VocabWordUsage] = [],
        volumeMetrics: VolumeMetrics? = nil,
        vocabComplexity: VocabComplexity? = nil,
        sentenceAnalysis: SentenceAnalysis? = nil,
        promptRelevanceScore: Int? = nil,
        wpmTimeSeries: [WPMDataPoint]? = nil
    ) {
        self.fillerWords = fillerWords
        self.totalWords = totalWords
        self.wordsPerMinute = wordsPerMinute
        self.pauseCount = pauseCount
        self.averagePauseLength = averagePauseLength
        self.strategicPauseCount = strategicPauseCount
        self.hesitationPauseCount = hesitationPauseCount
        self.clarity = clarity
        self.speechScore = speechScore
        self.vocabWordsUsed = vocabWordsUsed
        self.volumeMetrics = volumeMetrics
        self.vocabComplexity = vocabComplexity
        self.sentenceAnalysis = sentenceAnalysis
        self.promptRelevanceScore = promptRelevanceScore
        self.wpmTimeSeries = wpmTimeSeries
    }

    // Custom Decodable to handle missing fields in existing data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fillerWords = try container.decode([FillerWord].self, forKey: .fillerWords)
        totalWords = try container.decode(Int.self, forKey: .totalWords)
        wordsPerMinute = try container.decode(Double.self, forKey: .wordsPerMinute)
        pauseCount = try container.decode(Int.self, forKey: .pauseCount)
        averagePauseLength = try container.decode(TimeInterval.self, forKey: .averagePauseLength)
        strategicPauseCount = (try? container.decodeIfPresent(Int.self, forKey: .strategicPauseCount)) ?? 0
        hesitationPauseCount = (try? container.decodeIfPresent(Int.self, forKey: .hesitationPauseCount)) ?? 0
        clarity = try container.decode(Double.self, forKey: .clarity)
        speechScore = try container.decode(SpeechScore.self, forKey: .speechScore)
        vocabWordsUsed = (try? container.decodeIfPresent([VocabWordUsage].self, forKey: .vocabWordsUsed)) ?? []

        // SwiftData's internal decoder throws EXC_BREAKPOINT (uncatchable trap)
        // when decoding these from older data, so we skip decoding entirely.
        // They get populated fresh during analysis and stored with the recording.
        volumeMetrics = nil
        vocabComplexity = nil
        sentenceAnalysis = nil
        promptRelevanceScore = nil
        wpmTimeSeries = nil
    }

    var totalFillerCount: Int {
        fillerWords.reduce(0) { $0 + $1.count }
    }
    
    var fillerPercentage: Double {
        guard totalWords > 0 else { return 0 }
        return (Double(totalFillerCount) / Double(totalWords)) * 100
    }

    var totalVocabWordsUsed: Int {
        vocabWordsUsed.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Speech Score

struct SpeechScore: Codable {
    var overall: Int // 0-100
    var subscores: SpeechSubscores
    var trend: ScoreTrend
    
    init(
        overall: Int = 0,
        subscores: SpeechSubscores = SpeechSubscores(),
        trend: ScoreTrend = .stable
    ) {
        self.overall = overall
        self.subscores = subscores
        self.trend = trend
    }
}

struct SpeechSubscores: Codable {
    var clarity: Int      // 0-100: Based on filler word frequency
    var pace: Int         // 0-100: Based on WPM (optimal ~targetWPM)
    var fillerUsage: Int  // 0-100: Inverse of filler word ratio
    var pauseQuality: Int // 0-100: Natural vs awkward pauses
    var delivery: Int?    // 0-100: Volume energy + vocal variation + content density
    var vocabulary: Int?  // 0-100: From VocabComplexity.complexityScore
    var structure: Int?   // 0-100: From SentenceAnalysis.structureScore
    var relevance: Int?   // 0-100: Prompt relevance or coherence (nil when unavailable)

    init(
        clarity: Int = 0,
        pace: Int = 0,
        fillerUsage: Int = 0,
        pauseQuality: Int = 0,
        delivery: Int? = nil,
        vocabulary: Int? = nil,
        structure: Int? = nil,
        relevance: Int? = nil
    ) {
        self.clarity = clarity
        self.pace = pace
        self.fillerUsage = fillerUsage
        self.pauseQuality = pauseQuality
        self.delivery = delivery
        self.vocabulary = vocabulary
        self.structure = structure
        self.relevance = relevance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clarity = try container.decode(Int.self, forKey: .clarity)
        pace = try container.decode(Int.self, forKey: .pace)
        fillerUsage = try container.decode(Int.self, forKey: .fillerUsage)
        pauseQuality = try container.decode(Int.self, forKey: .pauseQuality)
        delivery = try? container.decodeIfPresent(Int.self, forKey: .delivery)
        vocabulary = try? container.decodeIfPresent(Int.self, forKey: .vocabulary)
        structure = try? container.decodeIfPresent(Int.self, forKey: .structure)
        relevance = try? container.decodeIfPresent(Int.self, forKey: .relevance)
    }
}

enum ScoreTrend: String, Codable {
    case improving
    case stable
    case declining
    
    var iconName: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }
    
    var color: Color {
        switch self {
        case .improving: return .green
        case .stable: return .gray
        case .declining: return .red
        }
    }
}

