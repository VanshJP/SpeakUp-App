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
    var isPrimarySpeaker: Bool
    var speakerConfidence: Double?

    init(
        word: String,
        start: TimeInterval,
        end: TimeInterval,
        confidence: Double? = nil,
        isFiller: Bool = false,
        isVocabWord: Bool = false,
        isPrimarySpeaker: Bool = true,
        speakerConfidence: Double? = nil
    ) {
        self.word = word
        self.start = start
        self.end = end
        self.confidence = confidence
        self.isFiller = isFiller
        self.isVocabWord = isVocabWord
        self.isPrimarySpeaker = isPrimarySpeaker
        self.speakerConfidence = speakerConfidence
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
        isPrimarySpeaker = try container.decodeIfPresent(Bool.self, forKey: .isPrimarySpeaker) ?? true
        speakerConfidence = try container.decodeIfPresent(Double.self, forKey: .speakerConfidence)
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

// MARK: - Pitch / Prosody Metrics

struct PitchMetrics: Codable {
    var f0Mean: Float
    var f0StdDev: Float
    var f0Min: Float
    var f0Max: Float
    var f0RangeSemitones: Float
    var pitchVariationScore: Int // 0-100
    var declinationRate: Float
    var f0Contour: [Float]?
    var voicedFrameRatio: Float // Ratio of voiced frames to total frames (articulation quality)

    init(
        f0Mean: Float = 0, f0StdDev: Float = 0,
        f0Min: Float = 0, f0Max: Float = 0,
        f0RangeSemitones: Float = 0, pitchVariationScore: Int = 0,
        declinationRate: Float = 0, f0Contour: [Float]? = nil,
        voicedFrameRatio: Float = 0
    ) {
        self.f0Mean = f0Mean; self.f0StdDev = f0StdDev
        self.f0Min = f0Min; self.f0Max = f0Max
        self.f0RangeSemitones = f0RangeSemitones
        self.pitchVariationScore = pitchVariationScore
        self.declinationRate = declinationRate
        self.f0Contour = f0Contour
        self.voicedFrameRatio = voicedFrameRatio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        f0Mean = try container.decode(Float.self, forKey: .f0Mean)
        f0StdDev = try container.decode(Float.self, forKey: .f0StdDev)
        f0Min = try container.decode(Float.self, forKey: .f0Min)
        f0Max = try container.decode(Float.self, forKey: .f0Max)
        f0RangeSemitones = try container.decode(Float.self, forKey: .f0RangeSemitones)
        pitchVariationScore = try container.decode(Int.self, forKey: .pitchVariationScore)
        declinationRate = try container.decode(Float.self, forKey: .declinationRate)
        f0Contour = (try? container.decodeIfPresent([Float].self, forKey: .f0Contour))
        voicedFrameRatio = (try? container.decodeIfPresent(Float.self, forKey: .voicedFrameRatio)) ?? 0
    }
}

// MARK: - Rate Variation Metrics

struct RateVariationMetrics: Codable {
    var rateCV: Double
    var articulationRate: Double
    var rateRange: Double
    var windowedWPMs: [Double]?
    var rateVariationScore: Int // 0-100

    init(
        rateCV: Double = 0, articulationRate: Double = 0,
        rateRange: Double = 0, windowedWPMs: [Double]? = nil,
        rateVariationScore: Int = 50
    ) {
        self.rateCV = rateCV; self.articulationRate = articulationRate
        self.rateRange = rateRange; self.windowedWPMs = windowedWPMs
        self.rateVariationScore = rateVariationScore
    }
}

// MARK: - Emphasis Metrics

struct EmphasisMetrics: Codable {
    var emphasisCount: Int
    var emphasisPerMinute: Double
    var distributionScore: Int // 0-100

    init(emphasisCount: Int = 0, emphasisPerMinute: Double = 0, distributionScore: Int = 50) {
        self.emphasisCount = emphasisCount
        self.emphasisPerMinute = emphasisPerMinute
        self.distributionScore = distributionScore
    }
}

// MARK: - Energy Arc Metrics

struct EnergyArcMetrics: Codable {
    var openingEnergy: Double
    var bodyEnergy: Double
    var closingEnergy: Double
    var hasClimax: Bool
    var arcScore: Int // 0-100

    init(
        openingEnergy: Double = 0, bodyEnergy: Double = 0,
        closingEnergy: Double = 0, hasClimax: Bool = false, arcScore: Int = 50
    ) {
        self.openingEnergy = openingEnergy; self.bodyEnergy = bodyEnergy
        self.closingEnergy = closingEnergy; self.hasClimax = hasClimax
        self.arcScore = arcScore
    }
}

// MARK: - Text Quality Metrics

struct TextQualityMetrics: Codable {
    var hedgeWordCount: Int
    var hedgeWordRatio: Double
    var powerWordCount: Int
    var rhetoricalDeviceCount: Int
    var transitionVariety: Int
    var weakPhraseCount: Int
    var weakPhraseRatio: Double
    var repeatedSentenceStartCount: Int
    var rhetoricalQuestionCount: Int
    var callToActionCount: Int
    var authorityScore: Int // 0-100
    var craftScore: Int // 0-100
    var concisenessScore: Int // 0-100
    var engagementScore: Int // 0-100

    init(
        hedgeWordCount: Int = 0, hedgeWordRatio: Double = 0,
        powerWordCount: Int = 0, rhetoricalDeviceCount: Int = 0,
        transitionVariety: Int = 0,
        weakPhraseCount: Int = 0,
        weakPhraseRatio: Double = 0,
        repeatedSentenceStartCount: Int = 0,
        rhetoricalQuestionCount: Int = 0,
        callToActionCount: Int = 0,
        authorityScore: Int = 50,
        craftScore: Int = 50,
        concisenessScore: Int = 50,
        engagementScore: Int = 50
    ) {
        self.hedgeWordCount = hedgeWordCount; self.hedgeWordRatio = hedgeWordRatio
        self.powerWordCount = powerWordCount
        self.rhetoricalDeviceCount = rhetoricalDeviceCount
        self.transitionVariety = transitionVariety
        self.weakPhraseCount = weakPhraseCount
        self.weakPhraseRatio = weakPhraseRatio
        self.repeatedSentenceStartCount = repeatedSentenceStartCount
        self.rhetoricalQuestionCount = rhetoricalQuestionCount
        self.callToActionCount = callToActionCount
        self.authorityScore = authorityScore
        self.craftScore = craftScore
        self.concisenessScore = concisenessScore
        self.engagementScore = engagementScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hedgeWordCount = (try? container.decodeIfPresent(Int.self, forKey: .hedgeWordCount)) ?? 0
        hedgeWordRatio = (try? container.decodeIfPresent(Double.self, forKey: .hedgeWordRatio)) ?? 0
        powerWordCount = (try? container.decodeIfPresent(Int.self, forKey: .powerWordCount)) ?? 0
        rhetoricalDeviceCount = (try? container.decodeIfPresent(Int.self, forKey: .rhetoricalDeviceCount)) ?? 0
        transitionVariety = (try? container.decodeIfPresent(Int.self, forKey: .transitionVariety)) ?? 0
        weakPhraseCount = (try? container.decodeIfPresent(Int.self, forKey: .weakPhraseCount)) ?? 0
        weakPhraseRatio = (try? container.decodeIfPresent(Double.self, forKey: .weakPhraseRatio)) ?? 0
        repeatedSentenceStartCount = (try? container.decodeIfPresent(Int.self, forKey: .repeatedSentenceStartCount)) ?? 0
        rhetoricalQuestionCount = (try? container.decodeIfPresent(Int.self, forKey: .rhetoricalQuestionCount)) ?? 0
        callToActionCount = (try? container.decodeIfPresent(Int.self, forKey: .callToActionCount)) ?? 0
        authorityScore = (try? container.decodeIfPresent(Int.self, forKey: .authorityScore)) ?? 50
        craftScore = (try? container.decodeIfPresent(Int.self, forKey: .craftScore)) ?? 50
        concisenessScore = (try? container.decodeIfPresent(Int.self, forKey: .concisenessScore)) ?? 50
        engagementScore = (try? container.decodeIfPresent(Int.self, forKey: .engagementScore)) ?? 50
    }
}

// MARK: - Audio / Speaker Isolation Metrics

struct AudioIsolationMetrics: Codable {
    var estimatedInputSNRDb: Double
    var estimatedOutputSNRDb: Double
    var suppressionDeltaDb: Double
    var suppressionScore: Int // 0-100, higher = cleaner speech after preprocessing
    var residualNoiseScore: Int // 0-100, higher = lower residual noise

    init(
        estimatedInputSNRDb: Double = 0,
        estimatedOutputSNRDb: Double = 0,
        suppressionDeltaDb: Double = 0,
        suppressionScore: Int = 50,
        residualNoiseScore: Int = 50
    ) {
        self.estimatedInputSNRDb = estimatedInputSNRDb
        self.estimatedOutputSNRDb = estimatedOutputSNRDb
        self.suppressionDeltaDb = suppressionDeltaDb
        self.suppressionScore = suppressionScore
        self.residualNoiseScore = residualNoiseScore
    }
}

struct SpeakerIsolationMetrics: Codable {
    var primarySpeakerWordRatio: Double // 0.0 - 1.0
    var filteredOutWordCount: Int
    var speakerSwitchCount: Int
    var separationConfidence: Int // 0-100
    var conversationDetected: Bool

    init(
        primarySpeakerWordRatio: Double = 1.0,
        filteredOutWordCount: Int = 0,
        speakerSwitchCount: Int = 0,
        separationConfidence: Int = 50,
        conversationDetected: Bool = false
    ) {
        self.primarySpeakerWordRatio = primarySpeakerWordRatio
        self.filteredOutWordCount = filteredOutWordCount
        self.speakerSwitchCount = speakerSwitchCount
        self.separationConfidence = separationConfidence
        self.conversationDetected = conversationDetected
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
    // Advanced metrics (populated when audio/text data available)
    var pitchMetrics: PitchMetrics?
    var rateVariation: RateVariationMetrics?
    var emphasisMetrics: EmphasisMetrics?
    var energyArc: EnergyArcMetrics?
    var textQuality: TextQualityMetrics?
    var audioIsolationMetrics: AudioIsolationMetrics?
    var speakerIsolationMetrics: SpeakerIsolationMetrics?

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
        wpmTimeSeries: [WPMDataPoint]? = nil,
        pitchMetrics: PitchMetrics? = nil,
        rateVariation: RateVariationMetrics? = nil,
        emphasisMetrics: EmphasisMetrics? = nil,
        energyArc: EnergyArcMetrics? = nil,
        textQuality: TextQualityMetrics? = nil,
        audioIsolationMetrics: AudioIsolationMetrics? = nil,
        speakerIsolationMetrics: SpeakerIsolationMetrics? = nil
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
        self.pitchMetrics = pitchMetrics
        self.rateVariation = rateVariation
        self.emphasisMetrics = emphasisMetrics
        self.energyArc = energyArc
        self.textQuality = textQuality
        self.audioIsolationMetrics = audioIsolationMetrics
        self.speakerIsolationMetrics = speakerIsolationMetrics
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
        // New recordings will have these fields populated fresh by SpeechService.
        volumeMetrics = nil
        vocabComplexity = nil
        sentenceAnalysis = nil
        promptRelevanceScore = nil
        wpmTimeSeries = nil
        pitchMetrics = nil
        rateVariation = nil
        emphasisMetrics = nil
        energyArc = nil
        textQuality = nil
        audioIsolationMetrics = nil
        speakerIsolationMetrics = nil
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
    var clarity: Int      // 0-100: Transcription confidence + articulation + hedge word penalty
    var pace: Int         // 0-100: WPM + rate variation
    var fillerUsage: Int  // 0-100: Inverse of filler + hedge word ratio
    var pauseQuality: Int // 0-100: Natural vs awkward pauses
    var vocalVariety: Int? // 0-100: Pitch variation + volume dynamics + rate variation
    var delivery: Int?    // 0-100: Energy + emphasis + arc + content density
    var vocabulary: Int?  // 0-100: Complexity + power words
    var structure: Int?   // 0-100: Sentence structure + rhetorical devices + transitions
    var relevance: Int?   // 0-100: Prompt relevance or coherence (nil when unavailable)

    init(
        clarity: Int = 0,
        pace: Int = 0,
        fillerUsage: Int = 0,
        pauseQuality: Int = 0,
        vocalVariety: Int? = nil,
        delivery: Int? = nil,
        vocabulary: Int? = nil,
        structure: Int? = nil,
        relevance: Int? = nil
    ) {
        self.clarity = clarity
        self.pace = pace
        self.fillerUsage = fillerUsage
        self.pauseQuality = pauseQuality
        self.vocalVariety = vocalVariety
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
        vocalVariety = try? container.decodeIfPresent(Int.self, forKey: .vocalVariety)
        delivery = try? container.decodeIfPresent(Int.self, forKey: .delivery)
        vocabulary = try? container.decodeIfPresent(Int.self, forKey: .vocabulary)
        structure = try? container.decodeIfPresent(Int.self, forKey: .structure)
        relevance = try? container.decodeIfPresent(Int.self, forKey: .relevance)
    }
}

// MARK: - Score Weights

struct ScoreWeights {
    var clarity: Double = 0.18
    var pace: Double = 0.12
    var filler: Double = 0.14
    var pause: Double = 0.12
    var vocalVariety: Double = 0.12
    var delivery: Double = 0.10
    var vocabulary: Double = 0.08
    var structure: Double = 0.08
    var relevance: Double = 0.06

    nonisolated static let defaults = ScoreWeights()

    /// Returns a copy with all weights normalized to sum to exactly 1.0
    var normalized: ScoreWeights {
        let total = clarity + pace + filler + pause + vocalVariety + delivery + vocabulary + structure + relevance
        guard total > 0 else { return .defaults }
        return ScoreWeights(
            clarity: clarity / total,
            pace: pace / total,
            filler: filler / total,
            pause: pause / total,
            vocalVariety: vocalVariety / total,
            delivery: delivery / total,
            vocabulary: vocabulary / total,
            structure: structure / total,
            relevance: relevance / total
        )
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

