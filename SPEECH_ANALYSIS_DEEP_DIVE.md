# Speech Analysis Algorithm — Deep Dive

Comprehensive documentation of every file, function, and algorithm involved in SpeakUp's speech analysis pipeline.

---

## Table of Contents

1. [Pipeline Overview](#1-pipeline-overview)
2. [File Map](#2-file-map)
3. [Transcription Layer](#3-transcription-layer)
4. [Filler Word Detection](#4-filler-word-detection)
5. [Core Analysis (`SpeechService.analyze`)](#5-core-analysis)
6. [Subscore Algorithms](#6-subscore-algorithms)
7. [Overall Score Calculation](#7-overall-score-calculation)
8. [Prompt Relevance & Coherence](#8-prompt-relevance--coherence)
9. [WPM Time Series](#9-wpm-time-series)
10. [Coaching Tips Generation](#10-coaching-tips-generation)
11. [Weak Area Detection](#11-weak-area-detection)
12. [Data Models](#12-data-models)
13. [Redundancy & Bloat Audit](#13-redundancy--bloat-audit)
14. [Magic Numbers Inventory](#14-magic-numbers-inventory)

---

## 1. Pipeline Overview

```
Audio File
    |
    v
[WhisperService.transcribe()]          <-- Primary: WhisperKit on-device STT
    |  (fails?)
    v
[SpeechService.transcribeWithAppleSpeech()]  <-- Fallback: Apple SFSpeechRecognizer
    |
    v
SpeechTranscriptionResult { text, words: [TranscriptionWord], duration }
    |
    v
[SpeechService.analyze()]              <-- Main analysis entry point
    |
    |-- Filler word counting (from pre-tagged words)
    |-- Pause detection (gap > 0.4s between words)
    |-- Volume analysis (from audio level samples)
    |-- Vocabulary complexity analysis
    |-- Sentence structure analysis
    |-- Prompt relevance / coherence scoring
    |-- Content density scoring
    |-- Vocab word bank detection
    |-- Subscore calculation (8 dimensions)
    |-- Overall score calculation (weighted average)
    |-- Gibberish gate / substance gate
    |-- WPM time series computation
    |
    v
SpeechAnalysis { scores, metrics, fillers, pauses, wpmTimeSeries, ... }
    |
    |-- [CoachingTipService.generateTips()]  <-- 2-3 actionable coaching tips
    |-- [WeakAreaService.analyze()]          <-- Identifies weakest metrics across recordings
```

### Parallel: Live Transcription (during recording)
```
Microphone Audio
    |
    v
[LiveTranscriptionService.start()]     <-- Apple SFSpeechRecognizer, real-time
    |
    v
liveFillerCount, liveWordCount         <-- Displayed on recording screen overlay
```

---

## 2. File Map

| File | Lines | Role |
|------|-------|------|
| `SpeechService.swift` | ~970 | **Main orchestrator** — transcription, analysis, all sub-analyses, scoring |
| `SpeechAnalysis.swift` | ~355 | **Data models** — core analysis structs (TranscriptionWord, SpeechAnalysis, SpeechScore, etc.) |
| `FillerWordList.swift` | ~300 | **Filler detection engine** — unconditional/contextual filler word classification |
| `FillerDetectionPipeline.swift` | ~175 | **Shared filler pipeline** — unified pause/context computation + tagging used by all 3 transcription paths |
| `UserModels.swift` | ~105 | **User/session types** — FeedbackQuestion, SessionFeedback, UserStats, WeeklyActivity, ScoreHistoryEntry |
| `PromptRelevanceService.swift` | ~418 | **Relevance/coherence scoring** — NLEmbedding-based semantic analysis |
| `CoachingTipService.swift` | ~223 | **Tip generation** — threshold-based coaching tips from analysis |
| `WhisperService.swift` | ~230 | **WhisperKit wrapper** — on-device transcription with filler prompting |
| `LiveTranscriptionService.swift` | ~120 | **Real-time filler counter** — Apple Speech during recording |
| `WeakAreaService.swift` | ~105 | **Weak area identification** — averages subscores across recordings |

**Total: ~3,000 lines** across 10 files. Refactored from 7 files / ~3,074 lines — net reduction of ~300 duplicated lines while improving modularity.

---

## 3. Transcription Layer

### 3a. WhisperService (Primary)

**File:** `WhisperService.swift`

**How it works:**
1. Loads WhisperKit model (`openai_whisper-base`, ~140MB) on app launch via `preloadModel()`
2. Uses a **filler prompt** to bias the model toward transcribing hesitation sounds:
   ```
   "Um, uh, er, ah, hmm, mm, mhm, uh-huh, like, you know, I mean, so, basically.
    The speaker says um and uh frequently..."
   ```
3. Decoding options: `temperature: 0.0`, `wordTimestamps: true`, `suppressBlank: false`, `noSpeechThreshold: 0.4`
4. Processes result into `SpeechTranscriptionResult` with per-word timestamps, confidence, and filler flags

**Key processing in `processWhisperResult()`:**
- Flattens all segments' word timings into `[RawWordTiming]` (shared input format)
- Delegates to `FillerDetectionPipeline.tagFillers()` for unified filler detection
- Pipeline handles pause/context computation, `FillerWordList` calls, and phrase detection

### 3b. Apple Speech Fallback

**File:** `SpeechService.swift`

**When used:** Only when WhisperKit fails twice (initial + retry after model reload).

**How it works:**
- Uses `SFSpeechURLRecognitionRequest` with `addsPunctuation = false`
- Converts `SFSpeechRecognitionResult` segments to `[RawWordTiming]`
- Delegates to same `FillerDetectionPipeline.tagFillers()` as WhisperService

### 3c. Live Transcription

**File:** `LiveTranscriptionService.swift`

**How it works:**
- Runs Apple `SFSpeechRecognizer` in real-time during recording via audio engine tap
- Extracts words/timestamps/durations from partial results
- Delegates to `FillerDetectionPipeline.countFillers()` (lightweight count-only version)
- Tracks `liveFillerCount`, `liveWordCount`, `lastSegmentEndTime`
- Does NOT produce a final transcript — only live counts for the recording UI overlay

### 3d. Shared Filler Detection Pipeline (NEW)

**File:** `FillerDetectionPipeline.swift`

All three transcription paths now share a single filler detection pipeline, eliminating ~300 lines of duplicated pause computation and filler tagging logic.

**`RawWordTiming`** — common input struct (word, start, end, confidence) abstracting WhisperKit/Apple Speech differences.

**`tagFillers(in:)`** — full pipeline returning `[TranscriptionWord]`:
1. For each word, computes `pauseBefore`, `pauseAfter`, `isStartOfSentence` using shared thresholds
2. Calls `FillerWordList.isFillerWord()` with full context
3. Second pass: detects multi-word filler phrases

**`countFillers(words:timestamps:durations:)`** — lightweight version for LiveTranscriptionService:
- Same logic but returns count only (no `TranscriptionWord` creation)
- Uses parallel arrays instead of structs for efficiency with `SFSpeechRecognitionResult`

**Constants:** `pauseThreshold = 0.3s`, `sentenceBoundaryThreshold = 0.8s`

---

## 4. Filler Word Detection

**File:** `FillerWordList.swift` (~300 lines)

### 4a. Unconditional Fillers (always tagged)
```
um, umm, ummm, uh, uhh, er, err, ah, ahh, eh, oh, mm, mmm, hmm, hmmm,
huh, erm, yeah, yea, mhmm, uh-huh, uhuh, mhm, mmhmm, mm-hmm
```
Also matches collapsed repeated characters (e.g., "ummmmmm" → "um").

### 4b. Context-Dependent Fillers (require surrounding analysis)
```
like, so, just, well, right, okay, actually, basically, literally, honestly, seriously
```

Each has a dedicated detection function:

- **"like"**: Filler if sentence-initial + pause after, after linking verb ("was like"), surrounded by pauses, or before filler-typical words ("like totally"). NOT filler after modals ("would like") or without any pauses.
- **"so"**: Filler if sentence-initial + pause after. NOT filler after "not" or before adjective without pause (intensifier: "so good").
- **"just"**: Only filler when surrounded by pauses on both sides.
- **"well"**: Filler if sentence-initial + pause after. NOT filler after intensifiers ("very well") or before past participles ("well done").
- **"right"/"okay"**: NOT filler after articles ("the right answer"). Filler if any adjacent pause exists.
- **Adverbs** ("actually", etc.): Filler if sentence-initial + pause after, or surrounded by pauses.

### 4c. Multi-Word Phrases
```
"you know", "i mean", "sort of", "kind of"
```
Detected in a second pass over the word array.

---

## 5. Core Analysis

**File:** `SpeechService.swift` lines 227-413 (`analyze()`)

### Input Parameters
| Parameter | Type | Purpose |
|-----------|------|---------|
| `transcription` | `SpeechTranscriptionResult` | Text + word-level timestamps |
| `actualDuration` | `TimeInterval` | Total recording length |
| `vocabWords` | `[String]` | User's word bank for bonus scoring |
| `audioLevelSamples` | `[Float]` | dB samples from AudioService |
| `prompt` | `Prompt?` | If present, enables relevance scoring |
| `targetWPM` | `Int` | User's pace target (default: 150) |
| `trackFillerWords` | `Bool` | Whether to count fillers |
| `trackPauses` | `Bool` | Whether to analyze pauses |

### Processing Steps

1. **Sort words** by start time (safety measure)
2. **Count fillers** from pre-tagged `isFiller` flags
3. **Detect pauses** — gaps > 0.4s between consecutive words
   - Each pause capped at 10s (longer = recording artifact)
   - Classified as "transition" if preceded by sentence-ending punctuation
4. **Compute basic metrics:**
   - `wordsPerMinute = totalWords / (duration / 60)`
   - `averagePauseLength` = **median** of pause durations (resists outlier skew)
   - `strategicPauseCount` = pauses at transitions
   - `hesitationPauseCount` = non-transition pauses > 1.2s
5. **Run sub-analyses** (all independent, could parallelize):
   - `analyzeVolume()` → `VolumeMetrics`
   - `analyzeVocabComplexity()` → `VocabComplexity`
   - `analyzeSentenceStructure()` → `SentenceAnalysis`
6. **Zero-score gate:** If `totalWords == 0` or `nonFillerWordCount == 0`, return score 0
7. **Confidence dampening:** For recordings < 10s, blend scores toward 50 (neutral)
8. **Relevance/coherence:** Delegate to `PromptRelevanceService`
9. **Content density:** Ratio of unique non-filler, non-stopword content
10. **Vocab word detection:** Regex-match user's word bank in transcript
11. **Calculate subscores** (8 dimensions) → `calculateSubscores()`
12. **Calculate overall** → `calculateOverallScore()`
13. **Substance gate:** Short recordings (< 20 words, < 15s) capped at 40
14. **Gibberish gate:** If `isLikelyGibberish()`, cap at 15
15. **Compute WPM time series** for chart visualization

---

## 6. Subscore Algorithms

### 6a. Clarity (0-100)

**File:** `SpeechService.swift` lines 462-488

**Two modes:**

*With confidence data (typical):*
```
clarityScore = (avgWordConfidence * 100) * 0.65 + durationConsistency * 0.35
```
- `avgWordConfidence`: Average of WhisperKit per-word probabilities
- `durationConsistency`: `(1.0 - coefficientOfVariation) * 100` where CV = stddev/mean of word durations. Lower CV = more consistent articulation.

*Without confidence data (fallback):*
```
clarityScore = 100 - (fillerRatio * 300)
```

Both modes apply **confidence dampening** for short recordings:
```
finalScore = rawScore * confidenceWeight + 50 * (1 - confidenceWeight)
```
where `confidenceWeight = min(1.0, duration / 10.0)`

### 6b. Pace (0-100)

**File:** `SpeechService.swift` lines 490-495

**Gaussian curve** centered on user's `targetWPM` (default 150):
```
paceScore = 100 * exp(-(wpm - targetWPM)^2 / (2 * 45^2))
```
- sigma = 45 WPM
- At target: 100
- At target +/- 45: ~61
- At target +/- 90: ~13

Also applies confidence dampening for short recordings.

### 6c. Filler Usage (0-100)

**File:** `SpeechService.swift` lines 497-499

```
fillerScore = (1 - fillerRatio * 5) * 100
```
- 0% fillers → 100
- 5% fillers → 75
- 10% fillers → 50
- 20% fillers → 0

Also applies confidence dampening.

### 6d. Pause Quality (0-100)

**File:** `SpeechService.swift` lines 501-601

**Sophisticated scoring** starting from base 70:

| Factor | Effect |
|--------|--------|
| No pauses at all | 40 (rushing) or 60 (normal pace) |
| Strategic medium pause (1.2-3s at transition) | +4 each |
| Strategic long pause (3s+ at transition) | +8 each |
| Hesitation long pause (3s+ not at transition) | -15 each |
| Low filler ratio + has pauses | +10 bonus |
| Too few pauses (< 3/min) | -10 |
| Too many pauses (> 15/min) | -(excess * 2) |
| Rushing + strategic pauses | Extra +2 each |

Also applies confidence dampening.

### 6e. Delivery (0-100)

**File:** `SpeechService.swift` lines 516-525

Only computed when volume data exists:
```
deliveryScore = energyScore * 0.35 + monotoneScore * 0.35 + contentDensity * 0.30
```

**Volume analysis** (`analyzeVolume()`, lines 703-735):
- `energyScore`: Normalized average dB level relative to -40dB baseline
- `monotoneScore`: Standard deviation of dB samples * 10. Higher stddev = more vocal variation = higher score.
- `dynamicRange`: 95th percentile - 5th percentile of samples

### 6f. Vocabulary (0-100)

**File:** `SpeechService.swift` lines 739-793

Four components:
```
uniqueComponent   = min(1.0, uniqueRatio / 0.55) * 35    // 55% unique words = full
longComponent     = min(1.0, longWordRatio / 0.12) * 20   // 12% words >= 8 chars = full
repeatComponent   = (1.0 - repeatPenalty) * 20             // 7+ repeated 2-3 grams = full penalty
diversityScore    = min(1.0, lengthBuckets / 6.0) * 25     // 6+ word-length buckets = full
```

**Bonus:** If user's word bank words are detected, +5 per use up to +15.

**Repeated phrases:** Finds 2-3 word n-grams appearing 3+ times.

### 6g. Structure (0-100)

**File:** `SpeechService.swift` lines 797-898

Splits transcript into sentences (by punctuation or pauses > 1.0s).

**Base: 60** (neutral starting point)

*Penalties (up to -40):*
| Penalty | Formula |
|---------|---------|
| Incomplete sentences (< 3 words) | `-incompleteRatio * 20` |
| Restarts ("i mean", "let me", etc.) | `-restartRatio * 20` |
| Run-on sentences (> 40 words) | `-min(20, count * 10)` |

*Rewards (up to +40):*
| Reward | Condition | Points |
|--------|-----------|--------|
| Sentence length variety | stddev 3-12 | +10 |
| Good average length | 8-25 words | +10 |
| Acceptable average length | 5-30 words | +5 |
| Transition words | per word found | +2 each, max +10 |
| Opening + closing sentences | both >= 5 words | +10 |

**Transition word list:** Now uses the shared `PromptRelevanceService.connectives` list (31 items), which is the comprehensive version covering all transition words used across the app.

### 6h. Relevance (0-100)

See [Section 8](#8-prompt-relevance--coherence) for full algorithm.

---

## 7. Overall Score Calculation

**File:** `SpeechService.swift` lines 603-632

Weighted average with dynamic weights based on which subscores are available:

| Subscore | Weight | Always present? |
|----------|--------|-----------------|
| Clarity | 0.15 | Yes |
| Pace | 0.18 | Yes |
| Filler Usage | 0.15 | Yes |
| Pause Quality | 0.13 | Yes |
| Delivery | 0.13 | Only with volume data |
| Vocabulary | 0.09 | Only with words |
| Structure | 0.05 | Only with words |
| Relevance | 0.10 | Only with prompt or 20+ words |

**Base total weight:** 0.61 (always-present subscores)
**Max total weight:** 0.98 (all subscores present)

Formula: `overall = weightedSum / actualTotalWeight`

**Post-scoring gates:**
- **Substance gate:** `totalWords < 20 && duration < 15` → cap at 40
- **Gibberish gate:** if `isLikelyGibberish()` → cap at 15

---

## 8. Prompt Relevance & Coherence

**File:** `PromptRelevanceService.swift` (418 lines)

### 8a. Relevance Score (prompt-based recordings)

**Entry:** `score(promptText:transcript:)` → `Int?` (0-100)

**Requires:** prompt >= 2 content words, transcript >= 3 content words.

**Three signals:**

1. **Keyword Overlap (weight: 0.25)**
   - Extract content words (nouns, verbs, adjectives, adverbs) using NLTagger with lemmatization
   - Filter: >= 3 chars, not in stop verbs list
   - Score = |prompt ∩ transcript| / |prompt|

2. **Word-Level Semantic Similarity (weight: 0.35)**
   - Uses `NLEmbedding.wordEmbedding(for: .english)`
   - For each prompt keyword, find best-matching transcript keyword
   - Distance mapping: `sim = max(0, 1.0 - distance * 0.55)`
   - Average across all prompt keywords

3. **Sentence-Level Alignment (weight: 0.40)**
   - Uses `NLEmbedding.sentenceEmbedding(for: .english)`
   - Compare each transcript sentence against the full prompt text
   - Same distance mapping: `sim = max(0, 1.0 - distance * 0.55)`
   - Average similarity * 2.5 (boosted), capped at 1.0

**Fallback cascading:** If sentence embedding unavailable, uses 2-signal (keyword + word semantic). If word embedding also unavailable, keyword overlap only.

**Post-processing:**
- **Coherence bonus:** If coherence > 50, add +0.12 (or +0.20 if coherence > 70)
- **Floor:** If transcript >= 30 words and raw < 0.40 and coherence > 40, floor at 0.40

### 8b. Coherence Score (free-practice, no prompt)

**Entry:** `coherenceScore(transcript:)` → `Int?` (0-100)

**Requires:** >= 2 sentences.

**Gibberish early exit:**
- If avg sentence < 3 words and > 3 sentences → cap at 20
- If no sentence > 5 words → cap at 30

**Three signals:**

1. **Sentence Flow (weight: 0.50)** — adjacent sentence similarity
   - Primary: `NLEmbedding.sentenceEmbedding` cosine similarity between consecutive sentences, * 1.8 boost
   - Fallback: Word-level topic consistency using `NLEmbedding.wordEmbedding`
   - Fallback of fallback: Jaccard overlap of content words between consecutive sentences, * 3.0 boost

2. **Topic Drift (weight: 0.30)** — how much topic changes from start to end
   - Compare first sentence to last and middle sentences using sentence embedding
   - Score: `1.0 - maxDrift * 0.8`
   - Fallback: Jaccard between first and last sentence content words, * 3.0

3. **Structural Connectives (weight: 0.20)** — presence of transition words
   - 31 connectives searched via regex with word boundaries
   - Variety score: unique connectives found / 6
   - Frequency score: total matches / 8
   - Final: variety * 0.7 + frequency * 0.3

### 8c. Gibberish Detection

**Entry:** `isLikelyGibberish(transcript:words:)` → `Bool`

**Three checks (need 2+ failures to be gibberish):**
1. Average word confidence < 0.3
2. Ratio of NLTagger-recognized English words < 0.4
3. No sentence > 4 words (when > 2 sentences exist)

---

## 9. WPM Time Series

**File:** `SpeechService.swift` lines 636-698

**Purpose:** Generates data points for a WPM-over-time chart.

**Algorithm:**
1. Divide recording into 5-second buckets
2. Count words whose `start` falls in each bucket
3. Compute WPM per bucket: `wordCount / (bucketDuration / 60)`
4. **Trailing bucket merge:** If last bucket < 2.5s, merge into previous (prevents extreme spikes like 360 WPM from 3 words in 0.5s)
5. **3-point moving average smoothing:** For each interior point, average with its neighbors

---

## 10. Coaching Tips Generation

**File:** `CoachingTipService.swift` (223 lines)

**Entry:** `generateTips(from:)` → `[CoachingTip]` (1-3 tips)

Pure threshold-based rules, no ML. Checks metrics in order and appends tips:

| Condition | Tip |
|-----------|-----|
| WPM > 185 | "Slow Down" |
| WPM 170-185 | "Slightly Fast" |
| WPM < 115 | "Pick Up the Pace" |
| WPM 115-130 | "A Bit More Energy" |
| Filler % > 10 | "High Filler Usage" |
| Filler % 5-10 | "Reduce Fillers" |
| Pause count = 0 | "Add Strategic Pauses" |
| Avg pause > 3s | "Shorten Pauses" |
| Pause quality < 50 | "Improve Pause Quality" |
| Clarity < 60 | "Work on Articulation" |
| Delivery < 50 | "Add Vocal Energy" |
| Relevance < 40 (with prompt) | "Stay on Topic" |
| Relevance < 40 (no prompt) | "Improve Coherence" |
| Overall >= 80 | "Great Session!" |
| Overall < 40 | "One Step at a Time" |

Each tip includes: icon, title, message, category, teachingPoint, optional suggestedDrillMode.

Returns max 3 tips. If none triggered, returns "Keep Practicing" fallback.

---

## 11. Weak Area Detection

**File:** `WeakAreaService.swift` (105 lines)

**Entry:** `analyze(recordings:)` — takes last 10 recordings

**Algorithm:**
1. Average each subscore (clarity, pace, fillerUsage, pauseQuality, delivery, vocabulary) across analyzed recordings
2. Sort by average (ascending)
3. Return top 2 weakest areas
4. Generate suggestion for weakest: link to relevant drill or generic practice session

---

## 12. Data Models

**File:** `SpeechAnalysis.swift`

### Core Analysis Types

| Type | Fields | Purpose |
|------|--------|---------|
| `TranscriptionWord` | word, start, end, confidence, isFiller, isVocabWord | Per-word metadata |
| `FillerWord` | word, count, timestamps | Aggregated filler counts |
| `VolumeMetrics` | averageLevel, peakLevel, dynamicRange, monotoneScore, energyScore, levelSamples | Audio volume analysis |
| `VocabComplexity` | uniqueWordCount/Ratio, avgWordLength, longWordCount/Ratio, repeatedPhrases, complexityScore | Vocabulary richness |
| `SentenceAnalysis` | totalSentences, incompleteSentences, restartCount, avgSentenceLength, longestSentence, structureScore, restartExamples | Sentence structure |
| `WPMDataPoint` | timestamp, wpm, wordCount | Chart data point |
| `SpeechAnalysis` | All metrics + subscores + overall score | Master result object |
| `SpeechScore` | overall, subscores, trend | Score container |
| `SpeechSubscores` | clarity, pace, fillerUsage, pauseQuality, delivery?, vocabulary?, structure?, relevance? | 8-dimension subscores |

### Extracted Types (previously in SpeechAnalysis.swift, now in dedicated files)

| Type | New File | Purpose |
|------|----------|---------|
| `FillerWordList` | `FillerWordList.swift` | Filler detection engine with context-aware analysis |
| `RawWordTiming` | `FillerDetectionPipeline.swift` | Common input format for filler pipeline |
| `UserStats` | `UserModels.swift` | Aggregate user statistics |
| `WeeklyActivity` | `UserModels.swift` | Weekly activity tracking |
| `ScoreHistoryEntry` | `UserModels.swift` | Historical score entry |
| `FeedbackQuestion` | `UserModels.swift` | Session journal question |
| `FeedbackAnswer` | `UserModels.swift` | Session journal answer |
| `SessionFeedback` | `UserModels.swift` | Session journal submission |

---

## 13. Redundancy & Bloat Audit

### ~~CRITICAL: Triplicated Filler Detection Pipeline~~ RESOLVED

~~The exact same pattern appeared in three places.~~

**Resolution:** Created `FillerDetectionPipeline.swift` with `RawWordTiming` input format. All three transcription paths (WhisperService, SpeechService Apple fallback, LiveTranscriptionService) now delegate to the shared pipeline. ~300 lines of duplicated logic removed.

### ~~CRITICAL: `detectFillerPhrases()` Duplicated~~ RESOLVED

~~Identical method in both SpeechService and WhisperService.~~

**Resolution:** Moved into `FillerDetectionPipeline.detectFillerPhrases()`. Both callers removed.

### ~~HIGH: Duplicate Transition/Connective Word Lists~~ RESOLVED

~~Two overlapping but different lists (14 vs 31 items) for the same concept.~~

**Resolution:** Made `PromptRelevanceService.connectives` internal. `SpeechService.countTransitions()` now uses the comprehensive 31-item shared list, ensuring consistent transition detection across structure scoring and coherence scoring.

### HIGH: Duplicate Stop Word Lists

**`SpeechService.stopWords` (48 items)** — used in `contentDensityScore()`
**`PromptRelevanceService.stopVerbs` (28 items)** — used in `extractContentWords()`

Different lists, different purposes, but significant overlap. The PromptRelevance one only filters verbs; the SpeechService one filters all function words. Not unified because they serve genuinely different roles.

### ~~MEDIUM: `coherenceScore()` Called Multiple Times~~ RESOLVED

~~Called twice on the same transcript in `PromptRelevanceService.score()`.~~

**Resolution:** Now computed once and stored in a `let coherence` variable, used for both the bonus check and floor check.

### MEDIUM: `SpeechAnalysis` Custom Decoder Discards Data

Lines 236-257 of `SpeechAnalysis.swift`: The custom `Decodable` init **always sets five fields to nil**:
```swift
volumeMetrics = nil
vocabComplexity = nil
sentenceAnalysis = nil
promptRelevanceScore = nil
wpmTimeSeries = nil
```

This means these expensive analysis results are **never recovered from persistence**. They must be recomputed every time the app loads a recording detail view. This is a SwiftData decoder bug workaround, but it means significant compute is wasted on repeat views.

### MEDIUM: `VolumeMetrics.levelSamples` Stores Raw Audio Samples

`levelSamples: [Float]?` stores the entire array of audio level samples in the analysis result, which gets persisted to SwiftData. For a 5-minute recording sampled at 10Hz, that's 3,000 floats (~12KB). This data is only used for waveform visualization and could be stored separately or recomputed from the audio file.

### MEDIUM: `inflectedPattern()` Over-Engineered for Word Bank

Lines 940-981: A 40-line morphological pattern builder handles plurals, past tense, progressive, comparative, CVC consonant doubling, and more. This sophistication is only used for matching the user's personal word bank (typically 5-20 simple words). A simpler stemming approach or even `String.hasPrefix()` would cover 95% of cases.

### ~~LOW: `FillerWordList` in Wrong File~~ RESOLVED

~~300+ line filler detection engine living inside SpeechAnalysis.swift.~~

**Resolution:** Moved to `SpeakUp/Models/FillerWordList.swift`.

### ~~LOW: Non-Analysis Types in SpeechAnalysis.swift~~ RESOLVED

~~UserStats, WeeklyActivity, ScoreHistoryEntry, FeedbackQuestion, FeedbackAnswer, SessionFeedback bloated the file to 776 lines.~~

**Resolution:** Moved to `SpeakUp/Models/UserModels.swift`. SpeechAnalysis.swift is now ~355 lines containing only analysis-related types.

### LOW: UUIDs on Computed Data Points

`WPMDataPoint`, `FillerWord`, `VocabWordUsage`, `RepeatedPhrase`, `VocabWordUsage` all have `id: UUID = UUID()`. These are computed values that don't need stable identity — they're regenerated each time. The UUIDs add overhead to serialization and memory.

### LOW: `VocabWordUsage` Defined Twice

`VocabWordUsage` appears in the data models file (as a struct) and is also referenced in vocab detection. Not a duplication of code, but the naming and placement are confusing since it's a transient detection result stored alongside persistent analysis data.

---

## 14. Magic Numbers Inventory

Every hardcoded threshold and constant in the analysis pipeline:

### Pause Detection
| Value | Location | Purpose |
|-------|----------|---------|
| 0.4s | SpeechService:265 | Minimum gap to count as a pause |
| 0.3s | FillerDetectionPipeline.pauseThreshold | Minimum gap for filler context "pause before/after" (centralized) |
| 10.0s | SpeechService:266 | Cap on individual pause duration |
| 0.8s | FillerDetectionPipeline.sentenceBoundaryThreshold | Gap threshold for "start of sentence" (centralized) |
| 1.0s | SpeechService:812 | Gap threshold for sentence boundary in structure analysis |
| 1.2s | SpeechService:307 | Threshold for "hesitation pause" classification |

### Scoring Thresholds
| Value | Location | Purpose |
|-------|----------|---------|
| 10.0s | SpeechService:335 | Confidence dampening duration threshold |
| 150 WPM | SpeechService:233 | Default target WPM |
| 45.0 sigma | SpeechService:492 | Pace score Gaussian width |
| 5x multiplier | SpeechService:498 | Filler ratio → score multiplier |
| 70 base | SpeechService:564 | Pause quality base score |
| 60 base | SpeechService:860 | Structure base score |
| 40 cap | SpeechService:379 | Substance gate cap |
| 15 cap | SpeechService:384 | Gibberish gate cap |

### Vocabulary Scoring
| Value | Location | Purpose |
|-------|----------|---------|
| 8 chars | SpeechService:754 | "Long word" threshold |
| 0.55 | SpeechService:773 | Unique ratio for full score |
| 0.12 | SpeechService:774 | Long word ratio for full score |
| 7 phrases | SpeechService:775 | Repeated phrases for full penalty |
| 6 buckets | SpeechService:780 | Word length diversity for full score |
| 35/20/20/25 | SpeechService:773-780 | Component weights (sum = 100) |

### Relevance/Coherence
| Value | Location | Purpose |
|-------|----------|---------|
| 0.55 factor | PromptRelevance:180,207 | Distance → similarity scaling |
| 0.25/0.35/0.40 | PromptRelevance:25 | 3-signal weights |
| 2.5 multiplier | PromptRelevance:213 | Sentence alignment boost |
| 0.50/0.30/0.20 | PromptRelevance:73 | Coherence signal weights |
| 1.8 boost | PromptRelevance:240 | Sentence flow score boost |
| 0.8 factor | PromptRelevance:275 | Topic drift penalty scaling |
| 3.0 boost | PromptRelevance:287,353 | Jaccard fallback boost |
| 50/70 thresholds | PromptRelevance:35-36 | Coherence bonus tiers |
| 0.12/0.20 bonus | PromptRelevance:36 | Coherence bonus values |
| 30 words | PromptRelevance:43 | Floor activation minimum |
| 0.40 floor | PromptRelevance:43 | Minimum relevance score floor |

### Overall Score Weights
| Subscore | Weight |
|----------|--------|
| Clarity | 0.15 |
| Pace | 0.18 |
| Filler Usage | 0.15 |
| Pause Quality | 0.13 |
| Delivery | 0.13 |
| Vocabulary | 0.09 |
| Structure | 0.05 |
| Relevance | 0.10 |

### WPM Chart
| Value | Location | Purpose |
|-------|----------|---------|
| 5.0s | SpeechService:639 | Bucket window size |
| 2.5s | SpeechService:651 | Minimum trailing bucket before merge |

### Gibberish Detection
| Value | Location | Purpose |
|-------|----------|---------|
| 0.3 | PromptRelevance:87 | Word confidence threshold |
| 0.4 | PromptRelevance:111 | Recognized word ratio threshold |
| 4 words | PromptRelevance:119 | Max sentence length for gibberish |
| 2 checks | PromptRelevance:123 | Failed checks needed to flag gibberish |

### Coaching Tip Thresholds
| Value | Location | Purpose |
|-------|----------|---------|
| 185/170/115/130 WPM | CoachingTip:57-93 | Pace tip bands |
| 10%/5% | CoachingTip:96-114 | Filler percentage bands |
| 3s | CoachingTip:126 | Long pause tip threshold |
| 50 | CoachingTip:135 | Pause quality tip threshold |
| 60 | CoachingTip:147 | Clarity tip threshold |
| 50 | CoachingTip:158 | Delivery tip threshold |
| 40 | CoachingTip:169 | Relevance tip threshold |
| 80/40 | CoachingTip:192-200 | Overall score encouragement bands |

---

## Summary of Key Issues

### Resolved
1. ~~**~400 lines of triplicated filler detection**~~ — Extracted to `FillerDetectionPipeline.swift` with shared `RawWordTiming` input format
2. ~~**Duplicate transition/connective word lists**~~ — Unified on `PromptRelevanceService.connectives` (31 items)
3. ~~**Double-computation of coherence score**~~ — Computed once, stored in `let`
4. ~~**SpeechAnalysis.swift is a dumping ground (776 lines)**~~ — Split into 3 focused files (~355 + ~300 + ~105 lines)
5. ~~**`detectFillerPhrases()` duplicated**~~ — Moved to shared pipeline

### Remaining
6. **Analysis results discarded on decode** — expensive recomputation every app launch due to SwiftData workaround (not safe to change — risk of crashes on existing user data)
7. **Duplicate stop word lists** — different purposes, not worth unifying
8. **100+ magic numbers** spread across files with no centralized configuration (low ROI for the churn)
9. **Over-engineered inflected pattern matching** for word bank (works correctly, low priority)
