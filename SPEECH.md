# Speech Analysis Algorithm Contract

Purpose: compact, authoritative reference for LLM context injection. Source-of-truth for the SpeakUp scoring pipeline. Also aliased in docs as `SPEECH_ANALYSIS_DEEP_DIVE.md` — this file (`SPEECH.md`) is canonical.
Last refresh: April 2026. Aligned with `SpeechService.swift`, `SpeechScoringEngine.swift`, `RecordingProcessingCoordinator.swift`.

## Design philosophy

Scores are progressive and achievable. A beginner's natural 15–20 s answer lands 50–65, not 20–35. A solid 60 s talk routinely sees 75–90. Only gibberish, silence, or near-empty speech drops below 20.

## Canonical files
- `SpeakUp/Services/SpeechService.swift` — orchestrator + `analyze(...)` entry point
- `SpeakUp/Services/SpeechScoringEngine.swift` — enhanced metrics, substance multiplier, gibberish gate, subscore helpers
- `SpeakUp/Services/RecordingProcessingCoordinator.swift` — singleton job queue wrapping transcription + analysis + LLM pass
- `SpeakUp/Services/FillerDetectionPipeline.swift` — shared pause-aware filler tagging
- `SpeakUp/Services/WhisperService.swift`, `DictationService.swift` — transcription backends
- `SpeakUp/Services/SpeechIsolationService.swift` — audio preprocessing (high-pass + noise gate)
- `SpeakUp/Services/ConversationIsolationService.swift` — primary-speaker labeling
- `SpeakUp/Services/TextAnalysisService.swift` — authority / hedges / power words / rhetoric
- `SpeakUp/Services/PromptRelevanceService.swift` — keyword + semantic + coherence scoring
- `SpeakUp/Services/PitchAnalysisService.swift` — vDSP F0 autocorrelation
- `SpeakUp/Services/LLMService.swift`, `LocalLLMService.swift` — Apple Intelligence / llama.cpp backends
- `SpeakUp/Models/SpeechAnalysis.swift` — `SpeechAnalysis`, `SpeechSubscores`, `SpeechScore`, `EnhancedSpeechMetrics`, `ScoreWeights`, `TranscriptionWord`, `PauseInfo`
- Runtime wiring: `SpeakUp/Views/Detail/RecordingDetailView.swift`

## Runtime sequence

Entry: `RecordingDetailView.task` (main actor).

1. **Configure** — `settingsViewModel.configure(with:)`; `await loadRecording()` fetches `Recording` from SwiftData.
2. **Prepare detail assets** — waveform, playback state.
3. **Enqueue** — `enqueueProcessingIfNeeded(recording)` delegates to `RecordingProcessingCoordinator.shared.enqueue(recordingID:modelContext:speechService:llmService:)` when `recording.analysis == nil`. No-op if analysis already exists. Sets `recording.isProcessing = true` only on `force: true`.
4. **Background tasks after ready** — `populateWPMTimeSeriesIfNeeded()` fills missing series; `enhanceCoherenceIfNeeded()` kicks off non-blocking LLM coherence enhancement (see §7).

`RecordingProcessingCoordinator` (`@MainActor`, singleton) owns job state:
- `activeRecordingIDs: Set<UUID>` dedupes concurrent `enqueue` calls (`guard !activeRecordingIDs.contains(recordingID) else { return }`).
- Work runs in `Task(priority: .userInitiated)` with a `defer` that always removes the id.
- `process(...)`:
  1. Fetch `Recording` by `#Predicate { $0.id == recordingID }`. Bail if missing or media file absent (`resolvedAudioURL ?? resolvedVideoURL`).
  2. Short-circuit when `recording.analysis != nil` — clear `isProcessing`, save, return.
  3. Load `UserSettings` (vocab words, filler config, voice profile) and `ScoreWeights` (fallback `ScoreWeights.defaults`).
  4. **Cached path** — if `transcriptionText` + `transcriptionWords` both present, call `analyzeTranscript(...)` directly.
  5. **Fresh path** — unload local LLM (frees memory), then race two tasks in `withThrowingTaskGroup`:
     - `speechService.transcribe(audioURL:fillerConfig:preferredTerms:voiceProfile:)` — runs the fallback chain `SpeechIsolationService.preprocessIfBeneficial` → `WhisperService.transcribe` (bias prompt toward fillers, `DecodingOptions.temperature = 0.0`, `noSpeechThreshold = 0.4`, `compressionRatioThreshold = 2.4`) → **WhisperService reload + single retry** → `DictationService` (`SFSpeechRecognizer`, `taskHint = .dictation`, `addsPunctuation = false`).
     - `Task.sleep(for: .seconds(90))` throws a timeout. First to finish wins, other is cancelled.
     Result carries `words`, `transcriptionText`, `audioIsolationMetrics`, `speakerIsolationMetrics`, and optional `voiceProfileUpdate` produced by `ConversationIsolationService.labelPrimarySpeaker(...)`.
  6. `analyzeTranscript(...)` dispatches to `DispatchQueue.global(qos: .userInitiated)`, invokes `SpeechService.analyze(...)`, then marks vocab words via `markVocabWordsInTranscription(...)`.
  7. **Voice profile update** — if `conversationDetected || (filteredOutWordCount ≥ 4 && speakerSwitchCount ≥ 3)`: EMA with `α = 0.3` on `UserSettings.voiceProfileF0Hz` / `voiceProfileEnergyDb`; increment `voiceProfileSampleCount`.
  8. Persist `transcriptionText`, `transcriptionWords`, `analysis`, clear `isProcessing`, `try modelContext.save()`. On error, still clear `isProcessing` + save.

`SpeechService.analyze(...)` signature:

```swift
func analyze(
    transcription: SpeechTranscriptionResult,
    actualDuration: TimeInterval,
    vocabWords: [String] = [],
    audioLevelSamples: [Float] = [],
    audioURL: URL? = nil,
    promptText: String? = nil,
    targetWPM: Int = 150,
    trackFillerWords: Bool = true,
    trackPauses: Bool = true,
    scoreWeights: ScoreWeights = .defaults,
    audioIsolationMetrics: AudioIsolationMetrics? = nil,
    speakerIsolationMetrics: SpeakerIsolationMetrics? = nil
) -> SpeechAnalysis
```

Order inside `analyze`:
1. Sort words by `start` (Whisper/Apple Speech can emit out-of-order segments).
2. `shouldScoreUsingPrimarySpeakerWords(...)` gates speaker-isolated scoring on `totalWords ≥ 12`, primary-speaker ratio in `[0.55, 0.90]`, `separationConfidence ≥ 62`, and conversation evidence.
3. `scoringWords` = primary-speaker words when gated, else sorted words. `scoringText = scoringWords.map(\.word).joined(separator: " ")`.
4. Single pass builds `fillerCounts` and `pauseMetadata: [PauseInfo]` — gap threshold **0.4 s**, gaps > 10 s capped, `isTransition = previous word ends with .?!`.
5. WPM = `totalWords / (max(actualDuration, 1) / 60)` — uses **full recording duration**, not voiced window (prevents inflated WPM when there's dead time).
6. Guarded sub-analyses: `analyzeVolume(samples:)`, `analyzeVocabComplexity(words:)`, `analyzeSentenceStructure(words:)`, `PitchAnalysisService.analyze(audioURL:)`, `analyzeRateVariation(...)`, `analyzeEmphasis(...)`, `analyzeEnergyArc(...)`, `TextAnalysisService.analyze(text:totalWords:)`.
7. **Zero-score gate.**
8. Prompt relevance: if `promptText != nil && totalWords ≥ 10` → `PromptRelevanceService.score(promptText:transcript:)`; else if `totalWords ≥ 20` → `PromptRelevanceService.coherenceScore(transcript:)` free-practice path; else `nil`.
9. Content density + vocab word detection.
10. `SpeechScoringEngine.computeEnhancedMetrics(words:text:actualDuration:pauseMetadata:)` → `EnhancedSpeechMetrics`.
11. `calculateSubscores(...)` → `SpeechSubscores`.
12. `calculateOverallScore(subscores:weights:)` — weighted average over normalized `ScoreWeights`.
13. `SpeechScoringEngine.applySubstanceMultiplier(score:substanceScore:)` → `applyGibberishGate(score:gibberishConfidence:)`.
14. `computeWPMTimeSeries(words:actualDuration:)`.
15. Return fully-populated `SpeechAnalysis`.

## Hard gates and caps (applied in order)

1. **Zero-score gate** — in `SpeechService.analyze`: if `totalWords == 0 || nonFillerWordCount == 0`, return `SpeechAnalysis` with `speechScore.overall = 0` and zeroed subscores. No further computation.
2. **Substance multiplier** — `SpeechScoringEngine.applySubstanceMultiplier(score:substanceScore:)`. Graduated 0.10× – 1.0× piecewise-linear curve over `EnhancedSpeechMetrics.substanceScore`. Result = `Int((score × multiplier).rounded())` clamped to 0–100.
3. **Gibberish gate** — `SpeechScoringEngine.applyGibberishGate(score:gibberishConfidence:)`:
   - `confidence ≥ 0.85` → `min(score, 8)`
   - `confidence ≥ 0.65` → `min(score, 15)`
   - `confidence ≥ 0.45` → `min(score, 30)`
   - else → unchanged

Gibberish confidence comes from the 5-signal check in `computeGibberishConfidence(...)`. Each signal contributes 0–2 failed checks, summed as `failedChecks`; `confidence = min(1.0, failedChecks / 6.0)`; `isDefinitelyGibberish` flips when `failedChecks ≥ 4`:

| # | Signal | Fails when |
|---|--------|-----------|
| 1 | ASR confidence | avg < 0.25 (+2) or < 0.40 (+1); stddev > 0.35 & mean < 0.50 (+1) |
| 2 | `NLTagger` lexical recognition | recognized ratio < 0.35 (+2) or < 0.55 (+1) |
| 3 | Sentence-length distribution | max sentence ≤ 3 words & count > 3 (+1); avg sentence < 2.5 words (+1) |
| 4 | Repetition density | top-word freq / total > 0.45 (+2) or > 0.30 (+1) |
| 5 | Unique content words | < 3 unique (+2) or < 6 (+1) |

## Substance multiplier curve

Piecewise-linear over `EnhancedSpeechMetrics.substanceScore` (0–100):

| Substance `s` | Multiplier expression | Range |
|---------------|-----------------------|-------|
| 0 ≤ s ≤ 10 | `0.10 + (s / 10) × 0.15` | 0.10 → 0.25 |
| 10 < s ≤ 30 | `0.25 + ((s − 10) / 20) × 0.40` | 0.25 → 0.65 |
| 30 < s ≤ 50 | `0.65 + ((s − 30) / 20) × 0.23` | 0.65 → 0.88 |
| 50 < s ≤ 75 | `0.88 + ((s − 50) / 25) × 0.09` | 0.88 → 0.97 |
| 75 < s ≤ 100 | `0.97 + ((s − 75) / 25) × 0.03` | 0.97 → 1.00 |

## Enhanced metrics (`SpeechScoringEngine.computeEnhancedMetrics`)

Returns `EnhancedSpeechMetrics`. All helpers live in `SpeechScoringEngine.swift`.

- **PTR (Phonation Time Ratio)** — `PTR = totalVoicedTime / actualDuration`, `totalVoicedTime = Σ max(0, word.duration)`. Ideal band **0.45–0.80**.
- **Articulation Rate** — `nonFillerCount / (totalVoicedTime / 60)` (WPM during voiced frames only). Ideal band **100–200 WPM**.
- **MLR (Mean Length of Run)** — `computeMeanLengthOfRun(words:pauseMetadata:)`. Avg consecutive non-filler words between pauses > 0.4 s. `MLR ≥ 8` = fluent, `< 4` = disfluent.
- **MATTR** — `computeMATTR(words:windowSize: 50)` (Covington & McFall 2010). Full marks **≥ 0.72**.
- **Content Word Density** — `computeContentWordDensity(text:duration:)`. Unique nouns/verbs/adjectives/adverbs (stop verbs excluded) per minute.
- **Substance Score** (0–100) — additive of 5 components (see table).
- **Fluency Score** (0–100) — `PTR(35) + MLR(35) + articulationRate(30)` piecewise zones.
- **Lexical Sophistication** (0–100) — `MATTR(50) + avgWordLength(25) + NLEmbedding rarity(25)`.
- **Gibberish Confidence** (0–1) + `gibberishReason: String?` + `isDefinitelyGibberish: Bool`.

### Substance score components

| Component | Max | Key thresholds |
|-----------|-----|----------------|
| Word count (nonFillerCount) | 25 | 5 → 0, 15 → 10, 35 → 18, 70+ → 25 |
| Duration | 20 | 3 s → 0, 10 s → 8, 20 s → 14, 40 s+ → 20 |
| MATTR | 20 | 0.45 → 5, 0.58 → 12, 0.72+ → 20 |
| Content density | 20 | 4/min → 5, 10/min → 12, 22+/min → 20 |
| MLR | 15 | < 2 → 0, 5 → 8, 10+ → 15 |

Gate inside substance: fewer than 5 non-filler words or < 3 s duration collapses components; the multiplier then caps the overall score near ≤ 10.

## Subscore formulas (`SpeechScoringEngine.calculateSubscores`)

Four required subscores (clarity, pace, filler, pause) plus up to five optional (vocalVariety, delivery, vocabulary, structure, relevance). Each returns `Int` clamped to `[0, 100]`. Reliability stabilization (below) is applied to clarity, pace, filler, pause.

### 1) Clarity
Blends five signals so no single source can dominate. Calibrated so typical conversational speech (VFR ~0.30, avgConf ~0.78, duration CV ~0.70, authority 70) lands low-80s.

- **VFR articulation** = `clamp(voicedFrameRatio × 140 + 55, 0, 100)`. VFR 0.30 → 97, 0.20 → 83. Fallback 70 when pitch metrics absent.
- **ASR confidence** = `clamp(avgConfidence × 120 − 10, 0, 100)`. 0.80 → 86, 0.70 → 74. Fallback 70.
- **Duration steadiness** — `cv = sqrt(variance) / meanDuration`; score = `clamp((1 − cv × 0.35) × 100, 0, 100)`. Fallback 70.
- **Authority** = `textQuality.authorityScore` else 70. Hedge penalty = `min(12, hedgeWordRatio × 180)`.
- **Pace alignment bonus** = `max(0, 5 − |wpm − targetWPM| / 20)`.

Weights (both VFR + ASR available): `VFR × 0.30 + ASR × 0.25 + duration × 0.15 + authority × 0.15 + (100 − hedge) × 0.05 + paceBonus`. When only one articulation signal exists, it absorbs the other's weight (total 0.55). Reliability stabilization uses `neutralAnchor = 65` (other subscores use 55) so degraded-reliability sessions aren't pulled toward a punitive center.

### 2) Pace
Gaussian over target with optional-metric reweighting.

- `optimalWPM = Double(targetWPM)` (default 150).
- `sigma = 55` (widened from 45 to give ±30 WPM tolerance).
- `basePaceScore = 100 × exp(−((wpm − optimalWPM)² / (2 × sigma²)))`.
- **Adaptive weighting.** Start `paceBaseWeight = 1.0`, `bonusComponents = 0`:
  - If `rateVariation` available: `bonusComponents += rateVariationScore × 0.18`; `paceBaseWeight −= 0.18`.
  - If `enhancedMetrics` available: `bonusComponents += fluencyScore × 0.14`; `paceBaseWeight −= 0.14`.
- Final = `clamp(Int(basePaceScore × paceBaseWeight + bonusComponents), 0, 100)`. No artificial cap when optional metrics are absent.

### 3) Filler Usage
Gentler logarithmic curve (multiplier reduced from 20 → 8).

- `hedgeAdjustment = min(0.02, hedgeWordRatio × 0.35)`
- `weakPhraseAdjustment = min(0.02, weakPhraseRatio × 0.50)`
- `effectiveRatio = fillerRatio + hedgeAdjustment + weakPhraseAdjustment`
- `score = 100 × max(0, 1 − log₂(1 + effectiveRatio × 8))`

Impact: 1% fillers → ~91, 3% → ~72, 5% → ~52, 10% → ~24.

### 4) Pause Quality
Base 72. Pause buckets: **medium** = `[1.2, 3.0) s`, **long** = `≥ 3.0 s`. Split each by `isTransition` flag (previous word ends with `.?!`).

- `+4` per strategic medium pause.
- `+6` per strategic long pause.
- `−8` per hesitation long pause, capped at 4 occurrences.
- `+8` when `fillerRatio < 0.03 && pauseCount > 2`.
- `pausesPerMinute = pauseCount / max(1, duration / 60)`. `< 3/min` → `−6`. `> 18/min` → `−(excess × 1.5)`.
- Fast-speech bonus: if `wpm > targetWPM + 10`, add `(strategicMedium + strategicLong) × 2`.
- No-pause fallbacks: empty `pauseMetadata` && `wpm > targetWPM + 20` → return **50**; else → **65**.

Final = `clamp(Int(score), 0, 100)`.

### 5) Delivery *(optional)*
Weighted composition with fallbacks to 50 for missing optional inputs.

`energy × 0.25 + monotone × 0.25 + contentDensity × 0.10 + emphasisRate × 0.15 + arcScore × 0.20 + engagement × 0.05`
- `emphasisRate = min(1, emphasisPerMinute / 5) × 100`.
- `arcScore` from `EnergyArcMetrics`.
- `engagement` from `TextQualityMetrics.engagementScore`.

### 6) Vocal Variety *(optional)*
Weighted combination over whichever inputs are present (weights renormalize):

`pitchVariationScore × 0.40 + volumeDynamics × 0.25 + rateVariation × 0.15 + pitchEnergyCorrelation × 0.20`

`pitchEnergyCorrelation` via `PitchAnalysisService.pitchEnergyCorrelation(...)` — Pearson r on downsampled pitch contour vs energy samples, mapped `r ∈ [−1, +1]` → score `clamp(50 + r × 50, 0, 100)`.

### 7) Vocabulary *(optional)*
- Base = `vocabComplexity.complexityScore`.
- Vocab bank bonus = `min(8, totalVocabUses × 3)`.
- Power word bonus = `min(5, Int((powerWordCount / totalWords) × 150))`.
- MATTR blend (when `enhancedMetrics` present) = `Int(base × 0.60 + lexicalSophisticationScore × 0.40)` applied after the bonuses.

### 8) Structure *(optional)*
Base = `sentenceAnalysis.structureScore`. Adjustments from `TextQualityMetrics`:

- `rhetoricBonus = min(12, rhetoricalDeviceCount × 4)`
- `transitionBonus = min(8, Int(transitionVariety × 0.8))`
- `concisenessAdjustment = Int((concisenessScore − 50) × 0.20)`
- `engagementAdjustment = Int((engagementScore − 50) × 0.15)`

### 9) Relevance *(optional)*
See §6 "Context-aware relevance" below.

### Reliability stabilization
Applied to clarity, pace, filler, pause before final aggregation.

```swift
func applyReliabilityStabilization(score: Int, reliability: Double, neutralAnchor: Int) -> Int {
    guard reliability < 0.95 else { return clamp(score) }
    let r = clamp(reliability, 0.55, 0.95)
    return clamp(Int((Double(score) × r + Double(neutralAnchor) × (1 − r)).rounded()))
}
```

Reliability is derived from `audioIsolationMetrics.residualNoiseScore` and `speakerIsolationMetrics.separationConfidence`. When both present: `reliability = max(0.35, min(1.0, audio × 0.6 + speaker × 0.4))`. Clarity uses `neutralAnchor = 65`; other three use `55`.

## Data processing services

### `FillerDetectionPipeline` (pause-aware tagging)
Shared across WhisperService, SpeechService, LiveTranscriptionService — removes ~300 lines of duplicated logic.

- Constants: `pauseThreshold = 0.3 s`, `sentenceBoundaryThreshold = 0.8 s`.
- Input: `[RawWordTiming(word, start, end, confidence)]`. Output: `[TranscriptionWord]` with `isFiller` set.
- Pass 1: per-word context (`pauseBefore`, `pauseAfter`, `isStartOfSentence`) feeds `FillerWordList.isFillerWord(word, pauseBefore, pauseAfter, isStartOfSentence, config:)`. The context lets the filter distinguish "well" (filler after pause) from "well" (adverb mid-sentence).
- Pass 2: multi-word phrase detection via `FillerWordList.isFillerPhrase(word[i], word[i+1])`. Both words are then marked `isFiller`.
- Public API: `tagFillers(in:)`, `tagFillers(in:config:)`, plus `countFillers(words:timestamps:durations:)` overloads for legacy callers.

### `PitchAnalysisService` (F0 autocorrelation via vDSP)
Zero dependencies beyond AVFoundation + Accelerate. Public API: `static func analyze(audioURL:) -> PitchMetrics?` and `static func pitchEnergyCorrelation(pitchContour:audioLevelSamples:) -> Int`.

Configuration:

| Parameter | Value |
|-----------|-------|
| Window duration | 0.03 s (30 ms) |
| Hop duration | 0.01 s (10 ms → 100 frames/s) |
| `f0Min` | 75 Hz |
| `f0Max` | 500 Hz |
| Voiced threshold | 0.45 (autocorrelation peak) |

Pipeline:
1. Load mono PCM via `AVAudioFile`.
2. Per frame: Hann window → normalized autocorrelation in lag range `[sr/f0Max, sr/f0Min]` → select peak ≥ 0.45 → `F0 = sr / bestLag`.
3. Octave-error correction: consecutive ratio in `[1.8, 2.2]` → halve; in `[0.45, 0.55]` → double.
4. 5-frame median filter smooths outliers.
5. Compute `f0Mean`, `f0StdDev`, `f0Min`, `f0Max`, `f0RangeSemitones`, `declinationRate`, `voicedFrameRatio`, and `pitchVariationScore` via a piecewise mapping of stdDev-in-semitones to 0–100.

`PitchMetrics` feeds clarity (VFR), vocal variety (variation score), delivery (indirectly through emphasis + energy arc).

### `TextAnalysisService`
Public API: `static func analyze(text:totalWords:) -> TextQualityMetrics`.

Returns `TextQualityMetrics { hedgeWordCount, powerWordCount, rhetoricalDeviceCount, transitionVariety, weakPhraseCount, repeatedSentenceStartCount, rhetoricalQuestionCount, callToActionCount, hedgeWordRatio, weakPhraseRatio, authorityScore, craftScore, concisenessScore, engagementScore }`.

Derived scores (all clamped 0–100):

```
authorityScore = 70 − min(30, hedgeCount × 3) + min(30, powerCount × 5)
craftScore     = 35 + min(30, rhetorical × 10)
                    + min(30, transitionVariety × 5)
                    + min(20, rhetoricalQ × 6) + min(12, callToAction × 4)
concisenessScore = 85 − min(35, weakPhrase × 4)
                       − min(25, repeatedStarts × 6)
                       − min(15, longSentences × 3)     // sentence ≥ 28 words
engagementScore  = 35 + min(20, transitionVariety × 2)
                      + min(25, rhetoricalQ × 8)
                      + min(20, callToAction × 10)
```

Fixed word lists: ~12 hedge words + hedge phrases, ~45 power words, 10 weak phrases, ~35 transitions, 8 call-to-action patterns. Rhetorical device detection looks for tricolon (`\b\w+,\s+\w+,?\s+and\s+\w+`), anaphora (≥3 consecutive sentences with same first 3 words), contrast (NOT/BUT, INSTEAD OF, RATHER THAN).

## Context-aware relevance (`PromptRelevanceService`)

Two entry points:

```swift
static func score(promptText: String, transcript: String) -> Int?
static func coherenceScore(transcript: String) -> Int?
```

Optional async variant `coherenceScore(transcript:llmService:promptText:)` blends an LLM coherence result when available (§7).

### Prompt-mode relevance — `score(promptText:transcript:)`
Invoked when `promptText != nil && totalWords ≥ 10`. Three-signal weighted blend:

1. **Keyword overlap (25%)** — `|promptKeywords ∩ transcriptKeywords| / |promptKeywords|` after stopword removal.
2. **Word-level semantic (35%)** — max NLEmbedding similarity between each prompt keyword and any transcript word.
3. **Sentence alignment (40%)** — average NLEmbedding distance prompt ↔ each transcript sentence.

`raw = overlap × 0.25 + semantic × 0.35 + alignment × 0.40`. Fallback without sentence embeddings: `overlap × 0.35 + semantic × 0.65`.

Coherence bonus: `coherenceScore > 50` adds `+0.20` (or `+0.12` for 50–70). Long-transcript floor: `transcriptWords ≥ 50 && raw < 0.30 && coherenceScore > 65` → `raw = max(raw, 0.30)`. Final = `clamp(Int(raw × 100), 0, 100)`.

### Story-linked recordings
- `Recording.storyId` is set when the user practices against a `Story`. `RecordingDetailView.effectivePromptText(for:)` resolves the source text right before `analyze` / `enhanceCoherenceIfNeeded` calls.
- Rule: **Story wins over Prompt.** If both are attached, `Story.content` (plain-text mirror of the rich-text body) is substituted for `Prompt.text` and passed as `promptText` into `SpeechService.analyze(...)`.
- `PromptRelevanceService.score(promptText:transcript:)` runs the same keyword + semantic + sentence-alignment pipeline; the relevance subscore now measures script fidelity, not generic prompt match.
- No new subscore, no formula change — only a substituted input source.

### Free-practice coherence — `coherenceScore(transcript:)`
Invoked when no prompt (or story) is available and `totalWords ≥ 20`. Five rule-based signals, weighted:

| # | Signal | Weight | Summary |
|---|--------|--------|---------|
| 1 | Entity continuity | 0.25 | Fraction of sentences sharing a noun/pronoun with the prior sentence, mapped `min(1.0, ratio × 1.15 + 0.1)` |
| 2 | Sentence flow | 0.20 | Adjacent-sentence NLEmbedding distance → non-linear similarity curve |
| 3 | Sliding-window topic drift | 0.20 | 3-sentence windows; violation when no pairwise keyword overlap |
| 4 | Weighted discourse markers | 0.15 | Categories (logical / contrast / additive / sequence / common); target 8 markers, variety bonus for 3+ categories |
| 5 | Structural progression | 0.20 | Opening + closing substantial, body > opening, sentence-length CV ∈ [0.3, 1.0], last ↔ first reference |

`raw = 0.25·s1 + 0.20·s2 + 0.20·s3 + 0.15·s4 + 0.20·s5`. Final = `clamp(Int(raw × 100), 0, 100)`.

## Overall score and LLM coherence pass

### Weighted aggregation (`calculateOverallScore`)
Normalized weights (sum to 1.0 over included dimensions). Clamped to 0–100:

```
weighted = clarity × w.clarity + pace × w.pace + fillerUsage × w.filler + pauseQuality × w.pause
         + (optional subscores × their weights, when present)
totalWeight = sum of included weights
overall     = clamp(Int(weighted / totalWeight), 0, 100)
```

Then: substance multiplier → gibberish gate → optional LLM post-pass writeback.

### Default weights (`ScoreWeights.defaults`)
clarity 0.18, pace 0.12, filler 0.14, pause 0.12, vocalVariety 0.12, delivery 0.10, vocabulary 0.08, structure 0.08, relevance 0.06. User-tunable in `Settings → ScoreWeightsView`; persisted on `UserSettings`.

### LLM coherence pass (`LLMService`)

Backend selection (`LLMService.activeBackend`):

```swift
var activeBackend: LLMBackend {
    if SystemLanguageModel.default.isAvailable { return .appleIntelligence }
    if localLLM.isModelReady { return .localLLM }
    return .none
}
```

- **Apple Intelligence** (`FoundationModels`, iOS 18.2+) preferred.
- **LocalLLMService** (`LlamaSwift` + Qwen 2.5 GGUF — compact 0.5B / balanced 1.5B / quality 3B) is the fallback; auto-loads at app launch via `loadLocalModelIfNeeded()` when Apple Intelligence is unavailable.
- **None** — coherence enhancement is skipped; rule-based relevance stands alone.

Memory pressure: `LLMService` installs a `DispatchSourceMemoryPressure` monitor on `[.warning, .critical]` that unloads the local LLM and cancels in-flight generation. `RecordingProcessingCoordinator` also unloads the LLM before long Whisper transcriptions to avoid OOM.

Output shape:

```swift
struct CoherenceResult: Sendable {
    let score: Int          // 0-100
    let topicFocus: String
    let logicalFlow: String
    let reason: String
}
```

The coherence enhancement is invoked from `RecordingDetailView.enhanceCoherenceIfNeeded()` after analysis is saved — it does **not** block the first render. Blend inside `PromptRelevanceService.coherenceScore(transcript:llmService:promptText:)`:

- Apple Intelligence backend → `llmWeight = 0.60`, rule-based weight `0.40`.
- Local LLM backend → `llmWeight = 0.40`, rule-based weight `0.60` (compensates for smaller model).
- `blended = clamp(Int(llmScore × llmWeight + ruleScore × (1 − llmWeight)), 0, 100)`.

The blended value replaces the stored `SpeechAnalysis.speechScore.subscores.relevance`; `calculateOverallScore` is recomputed with the updated relevance, and substance multiplier + gibberish gate are re-applied before the persisted `overall` is updated.

## Score behavior examples

| Input | Expected | Driver |
|-------|----------|--------|
| "um yeah I don't know" (3 s) | 3–8 | Zero/substance gate + gibberish cap |
| Gibberish syllables (2 s) | 1–5 | Gibberish confidence ≥ 0.85 |
| 15 s casual answer, some fillers | 45–60 | Moderate substance, filler penalty softened |
| 30 s clear speech, decent vocab | 65–80 | Strong substance, solid subscores |
| 60 s polished, structured talk | 78–92 | Full substance × near-1.0 multiplier |
| 90 s profound, well-structured | 85–96 | Full substance + rhetoric + relevance |

## Data and decode caveats
- `SpeechAnalysis.init(from:)` nulls advanced fields for older recordings; forward compatibility via `decodeIfPresent`.
- `Recording.audioLevelSamples` is `@Transient` — not persisted; regenerated from the audio file when needed.
- `EnhancedSpeechMetrics`, `TextQualityMetrics`, `PitchMetrics`, `AudioIsolationMetrics`, `SpeakerIsolationMetrics` all use `decodeIfPresent` so new fields don't break historical decoding.
- `ScoreWeights` is `nonisolated`; `ScoreWeights.defaults` is the canonical default value. The `normalized` accessor divides by total to guarantee `Σ weights == 1` at aggregation time.
- `Recording.transcriptionWords` stores `[TranscriptionWord]` Codable-encoded; older rows predating speaker isolation decode with `isPrimarySpeaker = true` and `speakerConfidence = nil`.
