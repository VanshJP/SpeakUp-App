# Speech Analysis Algorithm Contract (Claude-Optimized)

Purpose: compact, high-signal reference for LLM context injection.
Status: source-of-truth for current behavior.

## Canonical files
- `SpeakUp/Services/SpeechService.swift`
- `SpeakUp/Services/PromptRelevanceService.swift`
- `SpeakUp/Services/TextAnalysisService.swift`
- `SpeakUp/Models/SpeechAnalysis.swift`
- Runtime wiring: `SpeakUp/Views/Detail/RecordingDetailView.swift`

## Runtime sequence (actual order)
1. `RecordingDetailView.task`: load recording/settings.
2. `transcribeIfNeeded()` only if `transcriptionText == nil && analysis == nil`.
3. Transcription backend order:
   - WhisperKit
   - WhisperKit unload/reload retry
   - Apple Speech fallback (`addsPunctuation = false`)
4. `SpeechService.analyze(...)` computes base analysis + subscores + overall.
5. `enhanceCoherenceIfNeeded()` optionally runs LLM post-pass and recalculates overall.

## Inputs to `SpeechService.analyze(...)`
- Transcript (`text`, `[TranscriptionWord]`)
- `actualDuration`
- User vocab words
- `audioLevelSamples`
- Optional `audioURL`
- Optional prompt
- `targetWPM`
- `trackFillerWords`, `trackPauses`
- `ScoreWeights`

## Preprocessing and core derived metrics
- Words sorted by `start`.
- Pause detection: gap `> 0.4s`; pause duration cap `10.0s`.
- Transition pause: previous token ends with `.`, `?`, or `!`.
- `wordsPerMinute = totalWords / (actualDuration / 60)`.
- `averagePauseLength` uses median.
- Optional analyzers:
  - volume metrics (requires `audioLevelSamples`)
  - pitch metrics (requires `audioURL`)
  - vocab complexity, sentence analysis, rate variation, emphasis, energy arc, text quality

## Relevance branch
- Prompt mode: if `prompt != nil && totalWords >= 10` -> `PromptRelevanceService.score`.
- Free-practice mode: if `prompt == nil && totalWords >= 20` -> `PromptRelevanceService.coherenceScore`.
- Else relevance is `nil`.

## Hard gates and caps
- Zero-score gate: if `totalWords == 0 || nonFillerWordCount == 0` -> overall `0`.
- Substance gate: if `totalWords < 20 && actualDuration < 15` -> overall `min(overall, 40)`.
- Gibberish gate: if likely gibberish -> overall `min(overall, 15)`.
- Subscore ceiling for short recordings:
  - `scoreCeiling = min(100, 40 + Int(actualDuration * 6))`
  - Applied to clarity, pace, fillerUsage, pauseQuality, vocalVariety.

## Text quality model (used by multiple subscores)
`TextAnalysisService.analyze(text,totalWords)` outputs:
- hedge/power words
- rhetorical devices
- transition variety
- weak phrases
- repeated sentence starts
- rhetorical questions
- calls to action
- `authorityScore`, `craftScore`, `concisenessScore`, `engagementScore`

Key formulas:
- `authorityScore = clamp(70 - min(30, hedgeCount*3) + min(30, powerCount*5))`
- `craftScore = clamp(35 + deviceBonus + transitionBonus + engagementBonus)`
- `concisenessScore = clamp(85 - weakPhrasePenalty - repeatedStartPenalty - longSentencePenalty)`
- `engagementScore = clamp(35 + bridgeBonus + questionBonus + ctaBonus)`

## Subscore formulas (`calculateSubscores`)

### 1) Clarity
- Articulation:
  - pitch path: `clamp(voicedFrameRatio*120 + 18)`
  - fallback: avg confidence * 100
  - fallback: 55
- Duration consistency:
  - `cv = stdev(wordDurations) / mean(wordDurations)`
  - `durationComponent = clamp((1 - cv*0.75)*100)` (fallback 55)
- Hedge penalty: `min(20, hedgeWordRatio*400)`
- Authority component: `textQuality.authorityScore` (fallback 55)
- Formula:
  - `rawClarity = articulation*0.50 + duration*0.25 + (100-hedgePenalty)*0.10 + authority*0.15`
  - `clarity = min(Int(rawClarity), scoreCeiling)`

### 2) Pace
- `base = 100 * exp(-(wpm-target)^2 / (2*45^2))`
- `rawPace = base*0.80 + rateVariationScore*0.20`
- `pace = clamp(rawPace, 0...100)` then cap by `scoreCeiling`

### 3) Filler Usage
- `hedgeAdjustment = min(0.03, hedgeWordRatio*0.5)`
- `weakPhraseAdjustment = min(0.04, weakPhraseRatio*0.9)`
- `effectiveFillerRatio = fillerRatio + hedgeAdjustment + weakPhraseAdjustment`
- `rawFiller = 100 * max(0, 1 - log2(1 + effectiveFillerRatio*20))`
- `fillerUsage = clamp(rawFiller, 0...100)` then cap by `scoreCeiling`

### 4) Pause Quality
- If pause tracking off: `50`.
- Else base `70` with adjustments:
  - `+4` per strategic medium pause (`1.2-3.0s`)
  - `+8` per strategic long pause (`>=3.0s`)
  - `-15` per non-transition long pause
  - `+10` if `fillerRatio < 0.02` and enough short/medium pauses
  - frequency penalties: `<3/min -> -10`, `>15/min -> -(excess*2)`
  - rushing bonus if `wpm > target+10`: `+2` per strategic medium/long pause
  - no-pause fallback: `40` if `wpm > target+20`, else `60`
- Final clamp + `scoreCeiling`

### 5) Delivery (optional)
- Only if volume metrics exist.
- `rawDelivery = energy*0.25 + monotone*0.25 + contentDensity*0.10 + emphasis*0.15 + arc*0.20 + engagement*0.05`
- Final clamp `0...100`
- Else `delivery = nil`

### 6) Vocal Variety (optional)
- If any of pitch/volume/rate variation exists:
  - pitch variation: 0.40
  - volume monotone score: 0.25
  - rate variation: 0.15
  - pitch-energy correlation: 0.20 (when available)
- Weighted normalized blend, then clamp and cap by `scoreCeiling`
- Else `vocalVariety = nil`

### 7) Vocabulary (optional)
- Base: `vocabComplexity.complexityScore`
- Bonuses:
  - vocab bank: `min(8, totalUsed*3)`
  - power words: `min(5, Int(powerRatio*150))`
- Clamp `0...100`

### 8) Structure (optional)
- Base: `sentenceAnalysis.structureScore`
- Adjustments:
  - `+min(12, rhetoricalDeviceCount*4)`
  - `+min(8, Int(transitionVariety*0.8))`
  - `+Int((concisenessScore-50)*0.20)`
  - `+Int((engagementScore-50)*0.15)`
- Clamp `0...100`

### 9) Relevance (optional)
- Pass-through from relevance branch above.

## Overall score (`calculateOverallScore`)
- Normalize weights (`weights.normalized`).
- Always include required dimensions:
  - clarity, pace, filler, pause
- Include optional only when non-nil:
  - vocalVariety, delivery, vocabulary, structure, relevance
- `overall = clamp(weightedSum / sum(includedWeights), 0...100)`

## Default weights (`ScoreWeights.defaults`)
- clarity 0.12
- pace 0.12
- filler 0.12
- pause 0.10
- vocalVariety 0.14
- delivery 0.10
- vocabulary 0.10
- structure 0.10
- relevance 0.10
- If total weight `<= 0`: normalization falls back to defaults.

## Prompt relevance and coherence

### Prompt relevance (`PromptRelevanceService.score`)
- Signals:
  - keyword overlap
  - word semantic similarity
  - sentence alignment (if available)
- Blend:
  - full: `0.25 overlap + 0.35 wordSemantic + 0.40 sentenceAlignment`
  - no sentence alignment: `0.35 overlap + 0.65 wordSemantic`
  - no semantics: overlap only
- Coherence bonus:
  - `+0.12` if coherence `>50`
  - `+0.20` if coherence `>70`
- Floor rule:
  - if transcript words `>=50`, raw `<0.30`, coherence `>65` -> floor to `0.30`
- Output: `0...100`

### Free-practice coherence (`coherenceScore(transcript:)`)
Weighted 5-signal model:
- entity continuity 25%
- adjacent sentence flow 20%
- sliding-window topic drift 20%
- weighted connectives 15%
- structural progression 20%
Includes early gibberish-like caps for fragmented text.

## LLM post-pass (`enhanceWithLLM`)
Runs only when:
- LLM available
- transcript length >= 50 chars

Steps:
1. Replace relevance with LLM-blended coherence.
2. Blend structure and vocabulary with LLM transcript quality.
3. Recompute overall score.

Blend ratios for structure/vocabulary blend:
- Apple Intelligence: LLM 40%, rule-based 60%
- Local LLM: LLM 30%, rule-based 70%

Prompt coherence blend inside `PromptRelevanceService`:
- Apple Intelligence: LLM 60%, rules 40%
- Local LLM: LLM 40%, rules 60%

## Settings constraints affecting score behavior
- Target WPM slider: 100...200, step 5.
- Weight sliders: each 0.00...0.30, step 0.01.
- Save guard: rounded sum must equal exactly 100%.
- Pause/filler tracking toggles can disable corresponding signal effects.

## Data and decode caveats
- `SpeechSubscores` has 9 dimensions: clarity, pace, fillerUsage, pauseQuality, vocalVariety, delivery, vocabulary, structure, relevance.
- `SpeechAnalysis.init(from:)` intentionally nulls advanced fields for compatibility:
  - `volumeMetrics`, `vocabComplexity`, `sentenceAnalysis`, `promptRelevanceScore`, `wpmTimeSeries`, `pitchMetrics`, `rateVariation`, `emphasisMetrics`, `energyArc`, `textQuality`
- `Recording.audioLevelSamples` is `@Transient` (not persisted).
- Current recording save path does not persist sampled audio levels into saved `Recording`, so delivery/energy metrics may be absent post-hoc.

## Claude usage notes
- Treat this file as implementation contract, not product copy.
- If code and doc differ, code wins and doc must be updated in same PR.
- For score debugging, inspect in order:
  1. transcription backend
  2. timing/pause extraction
  3. optional analyzer availability
  4. nil optional subscores (changes denominator)
  5. weight normalization
  6. gates/caps
  7. LLM post-pass mutations
