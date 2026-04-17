# Speech Analysis Algorithm Contract

Purpose: compact, high-signal reference for LLM context injection.
Status: source-of-truth for current behavior (updated April 2026).

## Design philosophy

Scores should feel **achievable and progressive**. A beginner delivering a natural 15-20 second answer should land in the 50-65 range, not the 20-35 range. An experienced speaker giving a solid 60-second talk should routinely see 75-90. Only gibberish, silence, or extremely short/empty speech should score below 20.

## Canonical files
- `SpeakUp/Services/SpeechService.swift`
- `SpeakUp/Services/SpeechScoringEngine.swift`
- `SpeakUp/Services/PromptRelevanceService.swift`
- `SpeakUp/Services/TextAnalysisService.swift`
- `SpeakUp/Services/SpeechIsolationService.swift`
- `SpeakUp/Services/ConversationIsolationService.swift`
- `SpeakUp/Models/SpeechAnalysis.swift`
- Runtime wiring: `SpeakUp/Views/Detail/RecordingDetailView.swift`

## Runtime sequence
1. `RecordingDetailView.task`: load recording/settings.
2. `transcribeIfNeeded()` only if `transcriptionText == nil && analysis == nil`.
3. Transcription backend order: speech isolation → WhisperKit → reload retry → Apple Speech fallback.
4. Conversation isolation labels primary-speaker words.
5. `SpeechService.analyze(...)` computes base analysis + subscores + overall.
6. `enhanceCoherenceIfNeeded()` optionally runs LLM post-pass.

## Hard gates and caps (applied in order)
1. **Zero-score gate:** `totalWords == 0 || nonFillerWordCount == 0` → overall `0`.
2. **Substance multiplier:** graduated 0.10x–1.0x (see curve below).
3. **Gibberish gate:** graduated cap at ≤8 / ≤15 / ≤30 based on 5-signal confidence.

## Enhanced Metrics (`SpeechScoringEngine.computeEnhancedMetrics`)
- **PTR:** voiced time / duration. Ideal 0.45–0.80 (widened from 0.55–0.75).
- **Articulation Rate:** words/min during voiced time. Ideal 100–200 WPM (widened from 120–180).
- **MLR:** avg words between pauses. MLR ≥ 8 = fluent (gentler curve, MLR ≥ 5 scores well).
- **MATTR:** 50-word sliding window. 0.72+ = full marks (lowered from 0.80).
- **Substance Score (0–100):** word count + duration + MATTR + density + MLR. Thresholds lowered so 20s speeches can hit 55-65.
- **Fluency Score (0–100):** PTR + MLR + articulation rate with wider ideal zones.
- **Lexical Sophistication (0–100):** MATTR + word length + NLEmbedding rarity.
- **Gibberish Confidence (0–1):** 5-signal graduated confidence.

## Substance score thresholds

| Component | Max Pts | Key thresholds |
|-----------|---------|----------------|
| Word count | 25 | 15 words → 10pts, 35 → 18pts, 70+ → 25pts |
| Duration | 20 | 10s → 8pts, 20s → 14pts, 40s+ → 20pts |
| MATTR | 20 | 0.45 → 5pts, 0.58 → 12pts, 0.72+ → 20pts |
| Content density | 20 | 4/min → 5pts, 10/min → 12pts, 22+/min → 20pts |
| MLR | 15 | 2 → base, 5 → 8pts, 10+ → 15pts |

Gates: < 5 non-filler words or < 3 seconds → score ≤ 10.

## Substance multiplier curve

| Substance | Multiplier | Effect |
|-----------|-----------|--------|
| 0–10 | 0.10–0.25 | Gibberish/empty collapses |
| 10–30 | 0.25–0.65 | Very short, penalized |
| 30–50 | 0.65–0.88 | Short speech, moderate penalty |
| 50–75 | 0.88–0.97 | Adequate speech, slight penalty |
| 75–100 | 0.97–1.00 | Full-length, near-full score |

## Subscore formulas (`calculateSubscores`)

### 1) Clarity
Two complementary articulation signals (VFR and ASR confidence) are blended so neither alone can cap the score. Calibrated so typical conversational speech (VFR ~0.30, avgConf ~0.78, CV ~0.70, authority 70) lands in the low-80s.
- Articulation from VFR: clamp(voicedFrameRatio × 140 + 55, 0, 100). VFR 0.30 → 97, 0.20 → 83.
- ASR confidence: clamp(avgConfidence × 120 - 10, 0, 100). 0.80 → 86, 0.70 → 74.
- Duration consistency: clamp((1 - CV × 0.35) × 100). CV 0.70 → 75.5, 0.50 → 82.5.
- Authority: textQuality.authorityScore or 70.
- Hedge penalty: min(12, hedgeWordRatio × 180).
- Pace alignment: max(0, 5 - |wpm - target| / 20).
- Weights (both signals present): VFR × 0.30 + ASR × 0.25 + duration × 0.15 + authority × 0.15 + (100 - hedge) × 0.05 + paceBonus. When only one articulation source is available, its weight absorbs the other's (total 0.55).
- Reliability stabilization uses neutralAnchor = 65 (other subscores stay at 55) so degraded-reliability sessions aren't pulled toward a punitive center.

### 2) Pace
- Gaussian: sigma = 55 (widened from 45), giving ±30 WPM good tolerance.
- Adaptive weighting: WPM gets full weight when optional metrics are absent. With rate variation: -18% base → +18% rateVariation. With fluency: -14% base → +14% fluency.
- No artificial cap when optional metrics are missing.

### 3) Filler Usage
- Effective ratio = fillerRatio + hedge adjustment (max 0.02) + weak phrase (max 0.02).
- Curve: `100 × max(0, 1 - log₂(1 + ratio × 8))` — multiplier reduced from 20 to 8.
- Impact: 1% fillers → ~91, 3% → ~72, 5% → ~52, 10% → ~24.

### 4) Pause Quality
- Base 72 (raised from 70), no-pause fallback: 50/65 (raised from 40/60).
- Strategic rewards: +4 per medium transition, +6 per long transition (reduced from +8).
- Hesitation penalty: -8 per long hesitation, capped at 4 occurrences (was -15, uncapped).
- Low-filler bonus: +8 if fillerRatio < 0.03 (was 0.02).
- Frequency: too few < 3/min → -6, choppy > 18/min → -1.5× excess (was 15/min, -2x).

### 5) Delivery (optional)
- energy × 0.25 + monotone × 0.25 + contentDensity × 0.10 + emphasis × 0.15 + arc × 0.20 + engagement × 0.05.

### 6) Vocal Variety (optional)
- Pitch (0.40) + volume (0.25) + rate (0.15) + pitch-energy correlation (0.20 when available).

### 7) Vocabulary (optional)
- Base: vocabComplexity.complexityScore.
- Bonuses: vocab bank min(8), power words min(5).
- MATTR blend: 60% existing + 40% lexicalSophisticationScore.

### 8) Structure (optional)
- Base: sentenceAnalysis.structureScore + rhetoric/transition/conciseness/engagement adjustments.

### 9) Relevance (optional)
- Prompt mode: keyword + semantic + sentence alignment.
- Free practice: 5-signal coherence model.

#### Story-linked recordings
- When `Recording.storyId` is set, the linked `Story.content` (plain-text mirror of the rich-text note) is passed as `promptText` into `SpeechService.analyze(...)` instead of `recording.prompt?.text`.
- This feeds `PromptRelevanceService.score(promptText:transcript:)` so the relevance subscore reflects how closely the delivered speech tracks the user's own written script, not a generic prompt.
- Story wins when both a `Story` and a `Prompt` are attached — the story is treated as the more specific rubric.
- No new subscore and no formula change; only a new input source. Same keyword + semantic + sentence-alignment pipeline applies.
- Resolution happens in `RecordingDetailView.effectivePromptText(for:)` just before `analyze` / `enhanceWithLLM` calls.

## Overall score
- Weighted average of available subscores (4 required + up to 5 optional).
- Weights normalized to sum to 1.0 over included dimensions.
- Then: substance multiplier → gibberish gate → optional LLM post-pass.

## Default weights (`ScoreWeights.defaults`)
clarity 0.18, pace 0.12, filler 0.14, pause 0.12, vocalVariety 0.12, delivery 0.10, vocabulary 0.08, structure 0.08, relevance 0.06.

## Score behavior examples

| Input | Expected Score | Reason |
|-------|---------------|--------|
| "um yeah I don't know" (3s) | 3–8 | Substance gate + gibberish |
| Gibberish (2s) | 1–5 | Gibberish confidence 0.9+ |
| 15s casual answer, some fillers | 45–60 | Moderate substance, decent subscores |
| 30s clear speech, good vocab | 65–80 | Strong substance multiplier, good subscores |
| 60s polished structured speech | 78–92 | Full substance, high subscores |
| 90s profound, well-structured | 85–96 | Maximum substance, high across all dimensions |

## Data and decode caveats
- `SpeechAnalysis.init(from:)` nulls advanced fields for older recordings.
- `Recording.audioLevelSamples` is `@Transient`.
- `EnhancedSpeechMetrics` uses `decodeIfPresent` for forward compatibility.
