# Speech Analysis Algorithm — Source of Truth

This document is the canonical, code-aligned description of SpeakUp's current speech scoring pipeline.
It is intentionally formula-heavy and implementation-specific, so it can be used for debugging, feature design, and regression reviews.

---

## Scope

Primary scoring logic lives in:

- `SpeakUp/Services/SpeechService.swift`
- `SpeakUp/Services/PromptRelevanceService.swift`
- `SpeakUp/Services/TextAnalysisService.swift`
- `SpeakUp/Models/SpeechAnalysis.swift`

Runtime orchestration and settings inputs:

- `SpeakUp/Views/Detail/RecordingDetailView.swift`
- `SpeakUp/Views/Settings/ScoreWeightsView.swift`
- `SpeakUp/Views/Settings/AnalysisSettingsView.swift`
- `SpeakUp/Models/UserSettings.swift`

Supporting analyzers:

- `SpeakUp/Services/PitchAnalysisService.swift`
- `SpeakUp/Services/FillerDetectionPipeline.swift`

---

## 1) Runtime pipeline order

1. `RecordingDetailView` loads recording and settings.
2. `transcribeIfNeeded()` runs only when both `transcriptionText == nil` and `analysis == nil`.
3. `SpeechService.transcribe(...)` chooses backend:
   - WhisperKit (primary)
   - WhisperKit unload/reload retry
   - Apple Speech fallback (`addsPunctuation = false`)
4. `SpeechService.analyze(...)` computes base metrics + subscores + overall.
5. `enhanceCoherenceIfNeeded()` optionally runs LLM post-processing and updates:
   - relevance/coherence
   - structure
   - vocabulary
   - overall score (recomputed)

Implication: scoring is **two-stage** when LLM is available (base rule-based score, then optional LLM blend pass).

---

## 2) Transcription and filler tagging

### 2.1 Backend selection

- `SpeechService.transcribe(...)` sets `transcriptionEngine` to:
  - `"WhisperKit"`
  - `"WhisperKit (retry)"`
  - `"Apple Speech (fallback)"`

### 2.2 Filler tagging

- Words are tagged through `FillerDetectionPipeline`.
- If custom filler config exists, transcript words are re-tagged with custom config.

---

## 3) Base analysis inputs and metric extraction

`SpeechService.analyze(...)` input set:

- transcript (`text`, `[TranscriptionWord]`)
- `actualDuration`
- user vocab list
- `audioLevelSamples`
- optional `audioURL`
- optional prompt
- target WPM
- booleans for pause/filler tracking
- `ScoreWeights`

### 3.1 Word/time preprocessing

- Words sorted by `start`.
- Pause detected when gap `> 0.4s`.
- Pause duration capped at `10.0s`.
- Pause marked as transition if previous token ends with `.`, `?`, or `!`.

### 3.2 Core derived metrics

- `totalWords`
- filler counts + `totalFillers`
- `wordsPerMinute = totalWords / (actualDuration / 60)`
- pause list
- `averagePauseLength` uses **median**, not mean
- `strategicPauseCount` (transition pauses)
- `hesitationPauseCount` (non-transition pauses with duration `> 1.2s`)

### 3.3 Optional analysis sources

- Volume metrics: only when `audioLevelSamples` exists
- Pitch metrics: only when `audioURL` exists
- Vocabulary complexity and sentence analysis: from transcript words/text
- Rate variation, emphasis, energy arc
- Text quality (`TextAnalysisService`) from transcript text

### 3.4 Prompt relevance / coherence branch

- If prompt exists and `totalWords >= 10`: prompt relevance scoring
- Else if no prompt and `totalWords >= 20`: coherence scoring
- Else relevance is `nil`

### 3.5 Hard gates

- Zero-score gate: if no words or all words are fillers -> overall `0`
- Substance gate: if `<20 words` and `<15s` -> overall capped to `40`
- Gibberish gate: if likely gibberish -> overall capped to `15`

---

## 4) Text quality model (`TextAnalysisService`)

Computed fields:

- hedge counts/ratio
- power word count
- rhetorical device count
- transition variety
- weak phrase count/ratio
- repeated sentence starts
- rhetorical questions
- calls to action
- authority score
- craft score
- conciseness score
- engagement score

Key formulas:

- `authorityScore = clamp(70 - min(30, hedgeCount*3) + min(30, powerCount*5))`
- `craftScore = clamp(35 + deviceBonus + transitionBonus + engagementBonus)`
- `concisenessScore = clamp(85 - weakPhrasePenalty - repeatedStartPenalty - longSentencePenalty)`
- `engagementScore = clamp(35 + bridgeBonus + questionBonus + ctaBonus)`

These quality signals feed multiple subscores (clarity, filler, delivery, structure, vocabulary).

---

## 5) Subscore formulas (`calculateSubscores`)

All formulas below are current implementation behavior.

### 5.1 Shared ceiling for short recordings

`scoreCeiling = min(100, 40 + Int(actualDuration * 6))`

Applied to: clarity, pace, fillerUsage, pauseQuality, vocalVariety.

### 5.2 Clarity

- Articulation:
  - If pitch exists: `clamp(voicedFrameRatio * 120 + 18)`
  - Else fallback to avg word confidence * 100
  - Else fallback 55
- Duration consistency:
  - coefficient of variation over word durations
  - `clamp((1 - cv*0.75)*100)` (fallback 55)
- Hedge penalty: `min(20, hedgeWordRatio * 400)`
- Authority component: `textQuality.authorityScore` (fallback 55)

`rawClarity = articulation*0.50 + durationConsistency*0.25 + (100-hedgePenalty)*0.10 + authority*0.15`

`clarity = min(Int(rawClarity), scoreCeiling)`

### 5.3 Pace

- `base = 100 * exp(-(wpm-target)^2 / (2*45^2))`
- `rateVariationBonus = rateVariationScore * 0.20`
- `rawPace = base*0.80 + rateVariationBonus`

`pace = clamp(rawPace, 0...100)` then capped by `scoreCeiling`.

### 5.4 Filler Usage

- `hedgeAdjustment = min(0.03, hedgeWordRatio * 0.5)`
- `weakPhraseAdjustment = min(0.04, weakPhraseRatio * 0.9)`
- `effectiveFillerRatio = fillerRatio + hedgeAdjustment + weakPhraseAdjustment`
- `rawFiller = 100 * max(0, 1 - log2(1 + effectiveFillerRatio * 20))`

`fillerUsage = clamp(rawFiller, 0...100)` then capped by `scoreCeiling`.

### 5.5 Pause Quality

If pause tracking is disabled: fixed `50`.

Else:

- start base `70`
- reward strategic medium pauses (`1.2-3.0s`): `+4` each
- reward strategic long pauses (`>=3.0s`): `+8` each
- penalize non-transition long pauses: `-15` each
- if filler ratio `<0.02` and enough short/medium pauses: `+10`
- frequency penalty:
  - `<3 pauses/min`: `-10`
  - `>15 pauses/min`: `-(excess*2)`
- if rushing (`wpm > target+10`): extra strategic pause bonus `+2` each
- no pauses:
  - if `wpm > target+20`: `40`
  - else `60`

Final pause score is clamped and capped by `scoreCeiling`.

### 5.6 Delivery (optional)

Only computed when `volumeMetrics` exists:

`rawDelivery = energy*0.25 + monotone*0.25 + contentDensity*0.10 + emphasis*0.15 + arc*0.20 + engagement*0.05`

Then `clamp 0...100`.

If no volume metrics, `delivery = nil`.

### 5.7 Vocal Variety (optional)

Computed when any of pitch/volume/rate variation exists.

Weighted normalized blend of available components:

- pitch variation: 0.40
- volume monotone score: 0.25
- rate variation: 0.15
- pitch-energy correlation: 0.20 (only if both pitch contour and audio samples available)

Then clamped and capped by `scoreCeiling`.

### 5.8 Vocabulary (optional)

Base from `vocabComplexity.complexityScore`.

Bonuses:

- user word-bank usage bonus: `min(8, totalUsed*3)`
- power-word bonus: `min(5, Int(powerRatio*150))`

Then clamp `0...100`.

### 5.9 Structure (optional)

Base from `sentenceAnalysis.structureScore`.

Text-quality adjustments:

- rhetorical bonus: `min(12, rhetoricalDeviceCount*4)`
- transition bonus: `min(8, Int(transitionVariety*0.8))`
- conciseness adjustment: `Int((concisenessScore-50)*0.20)`
- engagement adjustment: `Int((engagementScore-50)*0.15)`

Then clamp `0...100`.

### 5.10 Relevance (optional)

Pass-through of prompt relevance/coherence score from section 3.4.

---

## 6) Overall score and weights

`calculateOverallScore(subscores, weights)`:

- normalize weights first (`weights.normalized`)
- always include required: clarity, pace, filler, pause
- include optional dimensions only when non-`nil`:
  - vocalVariety
  - delivery
  - vocabulary
  - structure
  - relevance
- denominator is the sum of included weights only
- final `overall = clamp(weightedSum / includedWeight, 0...100)`

Default weights (`ScoreWeights.defaults`):

- clarity `0.12`
- pace `0.12`
- filler `0.12`
- pause `0.10`
- vocalVariety `0.14`
- delivery `0.10`
- vocabulary `0.10`
- structure `0.10`
- relevance `0.10`

If weight sum is `<= 0`, normalization falls back to defaults.

---

## 7) Prompt relevance and free-practice coherence

### 7.1 Prompt relevance (`PromptRelevanceService.score`)

Signals:

- keyword overlap
- word-level semantic similarity
- sentence-level alignment (when sentence embedding available)

Blend:

- full model: `0.25 overlap + 0.35 wordSemantic + 0.40 sentenceAlignment`
- fallback without sentence alignment: `0.35 overlap + 0.65 wordSemantic`
- fallback without semantic: overlap only

Coherence-based topic consistency bonus:

- if coherence `>50`: add `0.12`
- if coherence `>70`: add `0.20`

Floor rule:

- if transcript words `>=50`, raw score `<0.30`, and coherence `>65`, floor to `0.30`

Final score is converted to `0...100`.

### 7.2 Free-practice coherence (`coherenceScore(transcript:)`)

5-signal weighted model:

- entity continuity: 25%
- adjacent sentence flow: 20%
- sliding-window drift: 20%
- weighted connectives: 15%
- structural progression: 20%

Includes gibberish-like early caps for fragmented or ultra-short sentence patterns.

---

## 8) LLM post-processing (second pass)

`SpeechService.enhanceWithLLM(...)` runs only when:

- LLM is available
- transcript length is at least 50 characters

Steps:

1. Get LLM-blended coherence (`PromptRelevanceService.coherenceScore(transcript,llm,promptText)`) and overwrite relevance.
2. Get LLM transcript quality and blend into:
   - structure
   - vocabulary
3. Recompute overall score from updated subscores.

Blend weights for step 2:

- Apple Intelligence backend: LLM 40%, rules 60%
- Local LLM backend: LLM 30%, rules 70%

Prompt-relevance LLM blending in `PromptRelevanceService` uses:

- Apple Intelligence: LLM 60%, rules 40%
- Local LLM: LLM 40%, rules 60%

---

## 9) Settings that influence scoring

User-facing settings feed directly into analysis:

- pause tracking toggle
- filler tracking toggle
- target WPM (100...200, step 5)
- all 9 score weights (0.00...0.30 per slider, step 0.01)

Score Weights save guard:

- Save button is blocked unless rounded total equals exactly `100%`.

---

## 10) Data model and persistence caveats

`SpeechSubscores` has 9 dimensions:

- clarity, pace, fillerUsage, pauseQuality, vocalVariety, delivery, vocabulary, structure, relevance

Important decoding behavior:

- `SpeechAnalysis.init(from:)` deliberately sets these fields to `nil` during decode for compatibility:
  - volumeMetrics
  - vocabComplexity
  - sentenceAnalysis
  - promptRelevanceScore
  - wpmTimeSeries
  - pitchMetrics
  - rateVariation
  - emphasisMetrics
  - energyArc
  - textQuality

Recording caveat:

- `Recording.audioLevelSamples` is `@Transient` (not persisted).
- Current recording creation path does not attach sampled levels to the saved `Recording`, so delivery/energy analyses may be unavailable in some post-analysis flows unless samples are present at analysis time.

---

## 11) Downstream consumers (non-scoring core)

After `SpeechAnalysis` is produced:

- `CoachingTipService` generates user guidance from scores and text quality
- score cards, history, comparisons, and weak-area analysis read subscores/overall
- settings and detail screens display score explanation + weighting

These components consume results but do not define core scoring math.

---

## 12) Practical debugging checklist

When score behavior looks wrong, validate in this order:

1. Transcription engine used (`WhisperKit` vs fallback).
2. Word timings sorted and pause detection sane.
3. Presence/absence of optional analyzers:
   - pitch metrics
   - volume metrics
   - text quality
4. Which optional subscores are `nil` (changes overall denominator).
5. Weight normalization and 100% weight configuration.
6. Whether substance/gibberish gates were applied.
7. Whether LLM post-pass ran and changed relevance/structure/vocabulary.

---

## 13) Change policy

Any scoring changes should update:

1. `SpeechService` formulas
2. `PromptRelevanceService` coherence/relevance logic
3. `TextAnalysisService` quality metrics (if used by scoring)
4. this markdown file in the same PR

This keeps product behavior and documentation in sync.
