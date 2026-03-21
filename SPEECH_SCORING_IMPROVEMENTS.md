# Speech Scoring Improvements — Research-Backed Algorithm Upgrade

**Date:** March 2026  
**Status:** Implemented  
**Files Changed:** `SpeechService.swift`, `SpeechAnalysis.swift`, `PromptRelevanceService.swift`  
**Files Added:** `SpeechScoringEngine.swift`

---

## Executive Summary

The previous scoring algorithm used a simple weighted average of rule-based subscores with a binary gibberish gate and a word-count ceiling. This upgrade introduces a research-backed, multi-signal scoring engine that:

1. **Collapses scores for gibberish and near-empty speech to near-zero** (≤8) using a 5-signal detection system and a multiplicative substance gate.
2. **Rewards profound, lengthy, substantive speech** with scores in the 80–100 range through a composite substance score that captures word count, duration, lexical diversity, content density, and fluency.
3. **Adds three gold-standard fluency metrics** from academic speech research: Phonation Time Ratio (PTR), Mean Length of Run (MLR), and Articulation Rate.
4. **Replaces simple Type-Token Ratio with MATTR** (Moving Average Type-Token Ratio), the length-invariant lexical diversity measure used in ETS SpeechRater and academic research.
5. **Adds NLEmbedding-based word rarity scoring** to reward sophisticated vocabulary choices.

All processing is **100% on-device** using Apple's NaturalLanguage framework and existing WhisperKit infrastructure.

---

## Research Foundation

The improvements are grounded in the following systems and research:

| System | Organization | Key Contribution |
|--------|-------------|-----------------|
| SpeechRater v5 | ETS (TOEFL) | Fluency features: PTR, MLR, articulation rate; MATTR for lexical diversity |
| Versant | Pearson | Phonation time ratio as primary fluency predictor |
| PRAAT | Boersma & Weenink | Articulation rate, voiced/unvoiced segmentation |
| Toastmasters Evaluation | Toastmasters International | Substance, structure, and delivery rubric |
| Covington & McFall (2010) | University of Georgia | MATTR window size of 50 as optimal for speech |
| PMC Review (2021) | NIH | Automated speech/language features for clinical assessment |

---

## New File: `SpeechScoringEngine.swift`

A standalone, testable scoring engine that computes `EnhancedSpeechMetrics` from transcript and timing data.

### Computed Metrics

| Metric | Description | Research Benchmark |
|--------|-------------|-------------------|
| **Phonation Time Ratio (PTR)** | Fraction of recording time spent speaking | 0.55–0.75 is natural conversational speech |
| **Articulation Rate** | Words per minute during voiced time only (excludes pauses) | 120–180 WPM during voiced time |
| **Mean Length of Run (MLR)** | Average words between pauses (>0.4s gaps) | MLR > 8 = fluent; MLR < 4 = disfluent |
| **MATTR** | Moving Average Type-Token Ratio (50-word sliding window) | 0.70+ = rich vocabulary; 0.50 = repetitive |
| **Content Word Density** | Unique content words (nouns, verbs, adj, adv) per minute | 15–30 unique content words/min = substantive |
| **Substance Score** | Composite 0–100 score rewarding meaningful speech | 0–15 = gibberish/empty; 80+ = substantive |
| **Fluency Score** | Composite 0–100 from PTR + MLR + articulation rate | Replaces WPM as primary fluency signal |
| **Lexical Sophistication Score** | MATTR + word length + NLEmbedding rarity | Replaces simple complexity score |
| **Gibberish Confidence** | 0–1 graduated confidence (0 = real speech, 1 = gibberish) | Replaces binary isLikelyGibberish |

---

## Substance Score: The Primary Gate

The substance score is the most important new addition. It acts as a **multiplicative gate** on the final overall score, not just a ceiling cap.

### Substance Score Components (0–100 total)

| Component | Max Points | Threshold |
|-----------|-----------|-----------|
| Word count adequacy | 25 | 8 words = 0pts; 50 words = 18pts; 100+ words = 25pts |
| Duration adequacy | 20 | 5s = 0pts; 30s = 14pts; 60s+ = 20pts |
| Lexical diversity (MATTR) | 20 | MATTR 0.50 = 5pts; 0.65 = 12pts; 0.80+ = 20pts |
| Content word density | 20 | 5/min = 5pts; 15/min = 12pts; 30+/min = 20pts |
| Mean Length of Run | 15 | MLR < 3 = 0pts; MLR 6 = 8pts; MLR 12+ = 15pts |

### Substance Multiplier Curve

The substance score is applied as a multiplier on the overall score:

| Substance Score | Multiplier | Effect |
|----------------|-----------|--------|
| 0–15 | 0.05–0.15 | Score collapses to near-zero (≤8) |
| 15–40 | 0.15–0.55 | Score heavily penalized (≤55% of raw) |
| 40–65 | 0.55–0.85 | Moderate penalty |
| 65–85 | 0.85–0.97 | Slight penalty |
| 85–100 | 0.97–1.00 | Near-full score |

**Example:** A user says "um, yeah, I don't know" (5 words, 3 seconds). Raw subscores might average 45 (pace is fine, no fillers). Substance score ≈ 5. Multiplier ≈ 0.08. Final score: 45 × 0.08 = **3/100**. ✓

**Example:** A user delivers a 90-second speech with rich vocabulary, clear structure, and good pace. Raw subscores average 82. Substance score ≈ 90. Multiplier ≈ 0.98. Final score: 82 × 0.98 = **80/100**. ✓

---

## Enhanced Gibberish Detection: 5-Signal System

The previous `isLikelyGibberish` used 3 binary checks. The new system uses 5 signals with graduated weighting:

| Signal | Weight | Threshold |
|--------|--------|-----------|
| ASR confidence mean | 1–2 pts | < 0.25 = +2pts; < 0.40 = +1pt |
| ASR confidence variance | 1 pt | High variance + low mean = +1pt |
| NL lexical recognition ratio | 1–2 pts | < 35% recognized = +2pts; < 55% = +1pt |
| Sentence length distribution | 1–2 pts | All sentences ≤3 words = +1pt; avg < 2.5 = +1pt |
| Word repetition density | 1–2 pts | One word > 45% of transcript = +2pts; > 30% = +1pt |
| Unique content words | 1–2 pts | < 3 unique content words = +2pts; < 6 = +1pt |

**Graduated capping:**
- Confidence ≥ 0.85 → cap score at 8
- Confidence ≥ 0.65 → cap score at 15
- Confidence ≥ 0.45 → cap score at 30

The old binary `isLikelyGibberish` is kept as a final safety net (now with stricter thresholds: 5 checks instead of 3, threshold raised to 3+ failures).

---

## MATTR: Replacing Simple Type-Token Ratio

The previous vocabulary scoring used `VocabComplexity.complexityScore` which was based on simple word frequency analysis. This has been augmented with MATTR.

**Why MATTR is better than simple TTR:**
- Simple TTR decreases as speech length increases (longer speeches always score lower)
- MATTR uses a 50-word sliding window, making it length-invariant
- MATTR 0.70+ indicates rich vocabulary regardless of speech length
- MATTR is the standard in ETS SpeechRater, PRAAT, and academic research

**Integration:** The new `lexicalSophisticationScore` blends MATTR (50%), average word length (25%), and NLEmbedding-based word rarity (25%). This is then blended 40% into the existing vocabulary subscore (60% existing, 40% new).

---

## Fluency Score: PTR + MLR + Articulation Rate

The previous pace score was purely WPM-based (Gaussian curve around target WPM). This misses the key distinction between **pace** (how fast you speak) and **fluency** (how smoothly you speak).

**New pace score formula:**
```
rawPaceScore = basePaceScore × 0.65 + rateVariationBonus + fluencyBlend × 0.15
```

Where `fluencyBlend` is the new fluency score (0–100) based on:
- **PTR** (35%): Ideal 0.55–0.75; below 0.40 = too hesitant
- **MLR** (35%): Ideal > 8; below 4 = disfluent
- **Articulation Rate** (30%): Ideal 120–180 WPM during voiced time

**Example:** A speaker who pauses strategically (PTR 0.65, MLR 10) but speaks at 130 WPM (slightly slow) will now score higher on pace than before, because their fluency is excellent.

---

## Changes to `isLikelyGibberish` in `PromptRelevanceService`

The legacy function has been significantly strengthened:

1. **Absolute minimum gate:** Fewer than 4 words → always gibberish
2. **Stricter confidence threshold:** < 0.25 (was < 0.30), with weighted scoring (2pts for very low)
3. **Stricter lexical recognition:** < 0.35 (was < 0.40), with weighted scoring
4. **New check 4:** Extreme word repetition (one word > 40% of transcript)
5. **New check 5:** Fewer than 3 unique content words
6. **Raised threshold:** 3+ failed checks (was 2) to reduce false positives on short but real speech

---

## Score Behavior Examples

| Input | Old Score | New Score | Reason |
|-------|-----------|-----------|--------|
| "um yeah I don't know" (3s) | 15–25 | 2–5 | Substance gate + gibberish detection |
| "asdfgh blorp zxcvbn" (2s) | 10–15 | 1–3 | Gibberish confidence 0.9+, substance 0 |
| 30-second rambling, repetitive | 35–45 | 12–20 | Low MATTR, low MLR, substance gate |
| 60-second clear speech, good vocab | 65–75 | 70–82 | Full substance multiplier, MATTR bonus |
| 90-second profound, structured speech | 75–85 | 82–95 | High substance, high MATTR, good fluency |

---

## Architecture: How It Fits Together

```
SpeechService.analyze(...)
    │
    ├── SpeechScoringEngine.computeEnhancedMetrics(...)
    │       ├── computeMATTR(windowSize: 50)
    │       ├── computeMeanLengthOfRun(...)
    │       ├── computeContentWordDensity(...)
    │       ├── computeSubstanceScore(...)
    │       ├── computeFluencyScore(PTR + MLR + articulationRate)
    │       ├── computeLexicalSophisticationScore(MATTR + length + rarity)
    │       └── detectGibberish(5-signal system)
    │
    ├── calculateSubscores(... enhancedMetrics: enhancedMetrics)
    │       ├── pace += fluencyBlend × 0.15
    │       └── vocabulary = blend(existing × 0.60, lexicalSophistication × 0.40)
    │
    ├── calculateOverallScore(subscores, weights)
    │
    ├── SpeechScoringEngine.applySubstanceMultiplier(overall, substanceScore)
    │
    ├── SpeechScoringEngine.applyGibberishGate(score, gibberishConfidence)
    │
    └── PromptRelevanceService.isLikelyGibberish(...) [legacy safety net]
```

---

## Future Improvements (Next Phase)

1. **CoreML pronunciation model:** Integrate a lightweight CoreML model (e.g., wav2vec2-base quantized to INT8) for phoneme-level pronunciation assessment. This would provide a true pronunciation score rather than using ASR confidence as a proxy.

2. **Sentence embedding coherence:** Use `NLEmbedding.sentenceEmbedding` to compute semantic coherence between consecutive sentences, replacing the entity-continuity heuristic.

3. **Calibration dataset:** Build a labeled dataset of 200+ recordings (clean/noisy, short/long, gibberish/real) and tune MATTR thresholds, substance score weights, and gibberish confidence thresholds against human ratings.

4. **Expose enhanced metrics in UI:** Surface PTR, MLR, MATTR, and substance score in the recording detail view so users can understand what specific aspects to improve.

5. **Disfluency detection:** Use WhisperKit word-level timestamps to detect specific disfluency patterns (false starts, revisions, prolongations) beyond simple filler word detection.
