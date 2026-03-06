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

// MARK: - Pitch / Prosody Metrics

struct PitchMetrics: Codable {
    var f0Mean: Float        // Mean fundamental frequency (Hz)
    var f0StdDev: Float      // Standard deviation of F0 (Hz)
    var f0Min: Float         // Minimum voiced F0 (Hz)
    var f0Max: Float         // Maximum voiced F0 (Hz)
    var f0RangeSemitones: Float // Range in semitones (perceptually uniform)
    var pitchVariationScore: Int // 0-100, higher = more expressive variety
    var declinationRate: Float // Semitones per second of overall pitch trend
    var f0Contour: [Float]?  // Sampled F0 values for visualization (nil when stripped)

    init(
        f0Mean: Float = 0, f0StdDev: Float = 0,
        f0Min: Float = 0, f0Max: Float = 0,
        f0RangeSemitones: Float = 0, pitchVariationScore: Int = 0,
        declinationRate: Float = 0, f0Contour: [Float]? = nil
    ) {
        self.f0Mean = f0Mean; self.f0StdDev = f0StdDev
        self.f0Min = f0Min; self.f0Max = f0Max
        self.f0RangeSemitones = f0RangeSemitones
        self.pitchVariationScore = pitchVariationScore
        self.declinationRate = declinationRate
        self.f0Contour = f0Contour
    }
}

// MARK: - Rate Variation Metrics

struct RateVariationMetrics: Codable {
    var rateCV: Double              // Coefficient of variation of windowed WPM
    var articulationRate: Double    // WPM excluding pauses
    var rateRange: Double           // Max windowed WPM minus min
    var windowedWPMs: [Double]?     // Per-window WPM values (nil when stripped)
    var rateVariationScore: Int     // 0-100, higher = healthier dynamic variation

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
    var emphasisCount: Int          // Number of detected emphasized words
    var emphasisPerMinute: Double   // Emphasis frequency
    var distributionScore: Int      // 0-100, higher = well-distributed emphasis

    init(emphasisCount: Int = 0, emphasisPerMinute: Double = 0, distributionScore: Int = 50) {
        self.emphasisCount = emphasisCount
        self.emphasisPerMinute = emphasisPerMinute
        self.distributionScore = distributionScore
    }
}

// MARK: - Energy Arc Metrics

struct EnergyArcMetrics: Codable {
    var openingEnergy: Double   // Normalized energy in first third (0-1)
    var bodyEnergy: Double      // Normalized energy in middle third (0-1)
    var closingEnergy: Double   // Normalized energy in final third (0-1)
    var hasClimax: Bool         // Whether a clear energy peak was detected
    var arcScore: Int           // 0-100, rewards dynamic energy structure

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
    var hedgeWordRatio: Double      // Hedge words / total words
    var powerWordCount: Int
    var rhetoricalDeviceCount: Int  // Tricolon + anaphora + contrast
    var transitionVariety: Int      // Unique transition/connective words used
    var authorityScore: Int         // 0-100, penalizes hedges, rewards power words
    var craftScore: Int             // 0-100, rewards rhetorical devices + transitions

    init(
        hedgeWordCount: Int = 0, hedgeWordRatio: Double = 0,
        powerWordCount: Int = 0, rhetoricalDeviceCount: Int = 0,
        transitionVariety: Int = 0, authorityScore: Int = 50,
        craftScore: Int = 50
    ) {
        self.hedgeWordCount = hedgeWordCount; self.hedgeWordRatio = hedgeWordRatio
        self.powerWordCount = powerWordCount
        self.rhetoricalDeviceCount = rhetoricalDeviceCount
        self.transitionVariety = transitionVariety
        self.authorityScore = authorityScore; self.craftScore = craftScore
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
    // New advanced metrics
    var pitchMetrics: PitchMetrics?
    var rateVariation: RateVariationMetrics?
    var emphasisMetrics: EmphasisMetrics?
    var energyArc: EnergyArcMetrics?
    var textQuality: TextQualityMetrics?

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
        pitchMetrics: PitchMetrics? = nil,
        rateVariation: RateVariationMetrics? = nil,
        emphasisMetrics: EmphasisMetrics? = nil,
        energyArc: EnergyArcMetrics? = nil,
        textQuality: TextQualityMetrics? = nil
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
        self.pitchMetrics = pitchMetrics
        self.rateVariation = rateVariation
        self.emphasisMetrics = emphasisMetrics
        self.energyArc = energyArc
        self.textQuality = textQuality
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
        pitchMetrics = nil
        rateVariation = nil
        emphasisMetrics = nil
        energyArc = nil
        textQuality = nil
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
    var clarity: Int      // 0-100: Based on transcription confidence + articulation
    var pace: Int         // 0-100: Based on WPM + rate variation
    var fillerUsage: Int  // 0-100: Inverse of filler + hedge word ratio
    var pauseQuality: Int // 0-100: Natural vs awkward pauses
    var vocalVariety: Int? // 0-100: Pitch (F0) variation + volume variation (NEW)
    var delivery: Int?    // 0-100: Energy arc + emphasis + volume energy
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

// MARK: - Session Feedback Types

enum FeedbackQuestionType: String, Codable {
    case scale // 1-5
    case yesNo
}

struct FeedbackQuestion: Codable, Identifiable {
    var id: UUID
    var text: String
    var type: FeedbackQuestionType

    init(id: UUID = UUID(), text: String, type: FeedbackQuestionType) {
        self.id = id
        self.text = text
        self.type = type
    }
}

struct FeedbackAnswer: Codable, Identifiable {
    var id: UUID = UUID()
    var questionId: UUID
    var questionText: String
    var type: FeedbackQuestionType
    var scaleValue: Int?
    var boolValue: Bool?

    init(questionId: UUID, questionText: String, type: FeedbackQuestionType, scaleValue: Int? = nil, boolValue: Bool? = nil) {
        self.questionId = questionId
        self.questionText = questionText
        self.type = type
        self.scaleValue = scaleValue
        self.boolValue = boolValue
    }
}

struct SessionFeedback: Codable {
    var answers: [FeedbackAnswer]
    var submittedAt: Date

    init(answers: [FeedbackAnswer], submittedAt: Date = Date()) {
        self.answers = answers
        self.submittedAt = submittedAt
    }
}

// MARK: - Filler Words List

struct FillerWordList {
    // Words that are ALWAYS fillers (hesitation sounds)
    // Includes variations that Whisper might transcribe
    static let unconditionalFillers: Set<String> = [
        "um", "umm", "ummm", "ummmm", "hum",
        "uh", "uhh", "uhhh", "uhhhh",
        "er", "err", "errr",
        "ah", "ahh", "ahhh",
        "eh", "ehh",
        "oh", "ohh",  // when used as hesitation
        "mm", "mmm", "mhm", "mmhmm", "mm-hmm",
        "hmm", "hmmm", "hmmmm",
        "huh",
        "erm",
        "yeah", "yea",
        "mhmm", "uh-huh", "uhuh"
    ]

    // Words that require context to determine if they're fillers
    static let contextDependentFillers: Set<String> = [
        "like", "so", "just", "well", "right", "okay",
        "actually", "basically", "literally", "honestly", "seriously"
    ]

    // Multi-word filler phrases
    static let fillerPhrases: Set<String> = [
        "you know", "i mean", "sort of", "kind of"
    ]

    // Words that typically precede verbs (non-filler context for "like")
    private static let verbPreceders: Set<String> = [
        "would", "do", "does", "did", "don't", "doesn't", "didn't",
        "i", "you", "we", "they", "he", "she", "it",
        "really", "actually", "also", "always", "never"
    ]

    // Linking verbs that often precede quotative "like"
    private static let linkingVerbs: Set<String> = [
        "was", "is", "are", "were", "be", "been", "being",
        "felt", "looked", "seemed", "acted"
    ]

    // Common adjectives/adverbs that follow filler "like"
    private static let fillerFollowers: Set<String> = [
        "really", "totally", "super", "very", "so", "pretty",
        "kind", "sort", "completely", "absolutely", "honestly"
    ]

    /// Simple check - use for backward compatibility or when context isn't available
    static func isFillerWord(_ word: String) -> Bool {
        let lowercased = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Unconditional fillers always match
        if unconditionalFillers.contains(lowercased) {
            return true
        }

        // Check for repeated characters (e.g., "ummmmm" -> "um")
        let collapsed = collapseRepeatedChars(lowercased)
        if unconditionalFillers.contains(collapsed) {
            return true
        }

        // Context-dependent words default to false without context
        return false
    }

    /// Context-aware filler detection - preferred method
    static func isFillerWord(
        _ word: String,
        previousWord: String?,
        nextWord: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool = false
    ) -> Bool {
        let w = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Unconditional fillers always match
        if unconditionalFillers.contains(w) || unconditionalFillers.contains(collapseRepeatedChars(w)) {
            return true
        }

        // Context-dependent words need analysis
        if contextDependentFillers.contains(w) {
            return isContextualFiller(
                word: w,
                prev: previousWord?.lowercased().trimmingCharacters(in: .punctuationCharacters),
                next: nextWord?.lowercased().trimmingCharacters(in: .punctuationCharacters),
                pauseBefore: pauseBefore,
                pauseAfter: pauseAfter,
                isStartOfSentence: isStartOfSentence
            )
        }

        return false
    }

    /// Check if two consecutive words form a filler phrase
    static func isFillerPhrase(_ word1: String, _ word2: String) -> Bool {
        let phrase = "\(word1.lowercased()) \(word2.lowercased())"
        return fillerPhrases.contains(phrase)
    }

    // MARK: - Private Helpers

    private static func isContextualFiller(
        word: String,
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        switch word {
        case "like":
            return isLikeFiller(prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter, isStartOfSentence: isStartOfSentence)
        case "so":
            return isSoFiller(prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter, isStartOfSentence: isStartOfSentence)
        case "just":
            return isJustFiller(prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter)
        case "well":
            return isWellFiller(prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter, isStartOfSentence: isStartOfSentence)
        case "right", "okay":
            return isRightOkayFiller(prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter)
        case "actually", "basically", "literally", "honestly", "seriously":
            return isAdverbFiller(word: word, prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter, isStartOfSentence: isStartOfSentence)
        default:
            // Default: surrounded by pauses = likely filler
            return pauseBefore && pauseAfter
        }
    }

    /// Detect "like" as filler vs verb/preposition
    private static func isLikeFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Pattern 1: Sentence-initial "Like, ..." is almost always filler
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Pattern 2: "was/is like" (quotative) - "She was like, 'no way'"
        if let p = prev, linkingVerbs.contains(p) {
            return true
        }

        // Pattern 3: Surrounded by pauses - "I was, like, confused"
        if pauseBefore && pauseAfter {
            return true
        }

        // Pattern 4: Before filler-typical words - "like totally", "like really"
        if let n = next, fillerFollowers.contains(n) {
            return true
        }

        // Anti-pattern 1: After modal/auxiliary - "would like", "do like"
        if let p = prev, verbPreceders.contains(p) {
            return false
        }

        // Anti-pattern 2: Comparative "like" - typically no pauses
        // "runs like the wind", "looks like rain"
        if !pauseBefore && !pauseAfter {
            return false
        }

        // Default: single pause suggests possible filler
        return pauseBefore || pauseAfter
    }

    /// Detect "so" as filler vs intensifier/conjunction
    private static func isSoFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Pattern 1: Sentence-initial with pause - "So, anyway..."
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Anti-pattern 1: Intensifier - "so good", "so much", "not so"
        if let p = prev, p == "not" {
            return false
        }

        // Anti-pattern 2: Before adjective without pause (intensifier)
        if !pauseAfter && next != nil {
            return false
        }

        // Surrounded by pauses = filler
        return pauseBefore && pauseAfter
    }

    /// Detect "just" as filler vs adverb
    private static func isJustFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool
    ) -> Bool {
        // "just" as filler is typically pause-surrounded and adds no meaning
        // "I, just, don't know" vs "I just arrived" (timing)

        // Surrounded by pauses = likely filler
        if pauseBefore && pauseAfter {
            return true
        }

        // Without pauses, "just" is usually meaningful
        return false
    }

    /// Detect "well" as filler vs adverb
    private static func isWellFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Pattern 1: Sentence-initial "Well, ..." is typically filler
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Anti-pattern: "very well", "quite well", "as well"
        if let p = prev, ["very", "quite", "as", "pretty", "really"].contains(p) {
            return false
        }

        // Anti-pattern: "well done", "well made"
        if let n = next, ["done", "made", "known", "written", "said"].contains(n) {
            return false
        }

        return pauseBefore && pauseAfter
    }

    /// Detect "right"/"okay" as fillers (seeking confirmation vs adjective)
    private static func isRightOkayFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool
    ) -> Bool {
        // "right?" and "okay?" at end of sentences are confirmation-seeking fillers
        // "the right way" is not a filler

        // Anti-pattern: Article before = adjective ("the right answer")
        if let p = prev, ["the", "a", "an", "that", "this"].contains(p) {
            return false
        }

        // Surrounded by pauses or sentence-final = likely filler
        return pauseBefore || pauseAfter
    }

    /// Detect adverbs like "actually", "basically" as fillers
    private static func isAdverbFiller(
        word: String,
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Sentence-initial with pause = filler
        // "Actually, I think..." vs "I actually think..."
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Mid-sentence surrounded by pauses = filler
        if pauseBefore && pauseAfter {
            return true
        }

        // Without pauses, these usually modify the following word meaningfully
        return false
    }

    private static func collapseRepeatedChars(_ word: String) -> String {
        var result = ""
        var prev: Character?
        for char in word {
            if char != prev {
                result.append(char)
                prev = char
            }
        }
        return result
    }
}

// MARK: - User Statistics

struct UserStats {
    var totalRecordings: Int
    var totalPracticeTime: TimeInterval // in seconds
    var currentStreak: Int
    var longestStreak: Int
    var averageScore: Double
    var scoreHistory: [ScoreHistoryEntry]
    var mostUsedFillers: [FillerWord]
    var improvementRate: Double // percentage change over last 7 days
    var weeklySessionCount: Int
    var weeklyGoalSessions: Int
    
    init(
        totalRecordings: Int = 0,
        totalPracticeTime: TimeInterval = 0,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        averageScore: Double = 0,
        scoreHistory: [ScoreHistoryEntry] = [],
        mostUsedFillers: [FillerWord] = [],
        improvementRate: Double = 0,
        weeklySessionCount: Int = 0,
        weeklyGoalSessions: Int = 5
    ) {
        self.totalRecordings = totalRecordings
        self.totalPracticeTime = totalPracticeTime
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.averageScore = averageScore
        self.scoreHistory = scoreHistory
        self.mostUsedFillers = mostUsedFillers
        self.improvementRate = improvementRate
        self.weeklySessionCount = weeklySessionCount
        self.weeklyGoalSessions = weeklyGoalSessions
    }
    
    var formattedPracticeTime: String {
        let hours = Int(totalPracticeTime) / 3600
        let minutes = (Int(totalPracticeTime) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct ScoreHistoryEntry: Codable, Identifiable {
    var id: UUID = UUID()
    let date: Date
    let score: Int
}

// MARK: - Weekly Activity

struct WeeklyActivity: Identifiable {
    var id: Date { weekStart }
    let weekStart: Date
    var sessions: Int
    var totalMinutes: TimeInterval
    var averageScore: Double
    
    var formattedWeek: String {
        weekStart.formatted(.dateTime.month(.abbreviated).day())
    }
}
