# SpeakUp Codebase Cleanup Report

> **Date:** March 21, 2026
> **Scope:** Full audit of all Swift source files and documentation for dead code, legacy patterns, redundancies, and stale UI copy following the SpeechScoringEngine rebuild.

---

## Summary

The audit identified **9 concrete issues** across the codebase. All safe removals and improvements have been implemented and committed. The changes are purely additive or internal — no public API surfaces, SwiftData schema fields, or user-visible feature flags were removed.

---

## Issues Found and Fixed

### 1. Legacy `scoreCeiling` in `calculateSubscores` — REMOVED

**File:** `SpeechService.swift` (line 569, previously)

**Problem:** The old `scoreCeiling = min(100, 40 + Int(actualDuration * 6))` was applied to five separate subscores (Clarity, Pace, Filler, Pauses, Vocal Variety). This was the original short-speech penalty mechanism from before `SpeechScoringEngine` existed. After the rebuild, it created a **double-penalty**: the substance multiplier already collapses the final overall score for short speech, while the ceiling was additionally compressing every individual subscore. This made subscores misleadingly low for short-but-valid speeches (e.g., a 15-second crisp answer would have all subscores capped at ~70 regardless of quality).

**Fix:** Removed the `scoreCeiling` variable and all five usages. Replaced with a comment explaining that short-speech penalty is now handled holistically by `SpeechScoringEngine.applySubstanceMultiplier`. Subscores now reflect true quality; the overall score is what gets penalized for insufficient substance.

---

### 2. Duplicate `NLEmbedding` Word Rarity Computation — DEDUPLICATED

**File:** `SpeechService.swift` → `analyzeVocabComplexity()` (lines 1186-1214, previously)

**Problem:** `analyzeVocabComplexity()` contained a full NLEmbedding word-distance loop (iterating over all unique words × 10 common words) to compute a `rarityComponent`. `SpeechScoringEngine.computeWordRarityScore()` performs an identical computation (with a slightly improved common-word list of 18 words and a cap of 80 words for performance). Both ran on every analysis call, loading the NLEmbedding model twice and doing redundant distance calculations.

**Fix:** `analyzeVocabComplexity()` now delegates to `SpeechScoringEngine.computeWordRarityScore()`. This eliminates the duplicate NLEmbedding load and ensures the rarity signal is consistent between the vocabulary subscore and the lexical sophistication score.

---

### 3. Legacy Binary Gibberish Gate in `analyze()` — REMOVED

**File:** `SpeechService.swift` (lines 406-408, previously)

**Problem:** After the new `SpeechScoringEngine.applyGibberishGate()` was added, the old `PromptRelevanceService.isLikelyGibberish()` call remained as a "safety net" that hard-capped scores at 12. This created an inconsistency: the new gate uses a graduated 5-signal confidence score (0.0–1.0) that smoothly reduces scores, while the old gate was a binary `min(score, 12)` that could fire on legitimate short speech (e.g., a confident 3-second answer). The old gate's threshold of `wordList.count >= 4` was also more aggressive than the new engine's multi-signal approach.

**Fix:** Removed the legacy gate call. `PromptRelevanceService.isLikelyGibberish()` is retained as a utility function for UI pre-flight checks (e.g., showing a warning before scoring) but no longer participates in score calculation.

---

### 4. Stale `ScoreWeightsView` Intro Copy — UPDATED

**File:** `ScoreWeightsView.swift` (line 138)

**Problem:** The intro card said "Your overall speech score is a weighted average of 9 subscores." This was accurate before the rebuild but is now misleading — the score is a weighted average *followed by* a Substance Gate multiplier. Users adjusting weights to try to boost their score on short/empty speech would be confused when the substance gate overrides their weights.

**Fix:** Updated copy to: "Your overall score is built in two stages. First, 9 subscores are combined using your weights. Then a Substance Gate multiplies the result based on speech length and content depth — so short or empty responses always score low regardless of weights."

---

### 5. Stale Subscore Descriptions in `ScoreWeightsView` — UPDATED

**File:** `ScoreWeightsView.swift` (lines 385-432)

**Problem:** Three subscore descriptions were outdated:

- **Pace:** Described as "bell curve comparison to target WPM with a bonus for natural rate variation." Missing the new fluency blend (PTR + MLR + articulation rate) that now contributes 15% of the pace score.
- **Clarity:** Described as "voiced frame ratio, word duration consistency, and hedge word penalty." Missing ASR word confidence and authority score components.
- **Vocabulary:** Described as "unique word ratio, word rarity, repetition penalty, and length diversity." Missing MATTR which is now the primary signal (40% blend weight).

**Fix:** All three descriptions updated to accurately reflect the current algorithm components and their relative weights.

---

### 6. Missing `EnhancedSpeechMetrics` UI Section — ADDED

**File:** `DetailAnalysisTab.swift`

**Problem:** The `EnhancedSpeechMetrics` struct (MATTR, Phonation Time Ratio, Mean Length of Run, Substance Score, Fluency Score, Lexical Sophistication Score) was computed and stored in `SpeechAnalysis.enhancedMetrics` but never surfaced in the UI. Users had no visibility into these research-backed metrics that now drive a significant portion of their score.

**Fix:** Added a new **"Speech Depth"** section to `DetailAnalysisTab` that displays:
- Substance Score, Fluency Score, and Lexical Sophistication Score as `SubscoreRow` bars
- MATTR value, Phonation Time Ratio (%), and Mean Length of Run (words) as a stats row
- An explanatory tooltip describing what each metric means and what the ideal ranges are

---

### 7. Missing Substance/Fluency Coaching Tips — ADDED

**File:** `CoachingTipService.swift`

**Problem:** `CoachingTipService.generateTips()` never read `analysis.enhancedMetrics`. This meant users who scored poorly due to low substance (too short, gibberish) or poor fluency (fragmented speech, excessive dead air) received generic tips about fillers or pace instead of targeted guidance on the actual root cause.

**Fix:** Added a new "Substance & Fluency" tip block that fires on:
- `substanceScore < 35` → "Develop Your Response" tip with PREP framework guidance
- `substanceScore < 60` → "Add More Depth" tip with example-adding technique
- `phonationTimeRatio < 0.45` → "Reduce Dead Air" tip with bridging phrase technique
- `meanLengthOfRun < 4.0` → "Speak in Longer Runs" tip with clause-boundary practice

---

### 8. Stale `SPEECH_SCORING_REBUILD_BLUEPRINT.md` — ARCHIVED

**File:** `SPEECH_SCORING_REBUILD_BLUEPRINT.md`

**Problem:** This document described the March 2026 isolation-aware rebuild but had no indication it was superseded by the newer `SPEECH_ANALYSIS_DEEP_DIVE.md` and `SPEECH_SCORING_IMPROVEMENTS.md`. New contributors reading it would get an incomplete picture of the current architecture.

**Fix:** Prepended an `> ARCHIVED` notice pointing to the authoritative documents. The content is preserved for historical context.

---

### 9. Clarifying Comment on Dual `articulationRate` Computation — ADDED

**File:** `SpeechService.swift` → `analyzeRateVariation()` (line 1472)

**Problem:** `articulationRate` is computed in both `analyzeRateVariation()` (feeds `RateVariationMetrics` for UI display) and `SpeechScoringEngine.computeEnhancedMetrics()` (feeds fluency scoring). Without a comment, this looks like dead/duplicate code and is a maintenance hazard.

**Fix:** Added a comment clarifying that both computations serve different purposes and must remain separate.

---

## What Was Intentionally NOT Removed

The following patterns were audited and determined to be **correct and necessary**:

| Pattern | Reason Retained |
|---|---|
| `VocabComplexity` struct and `analyzeVocabComplexity()` | Still feeds the Vocabulary section UI (`vocabComplexitySection`) and provides `repeatedPhrases` which `SpeechScoringEngine` does not compute |
| `SentenceAnalysis` struct and `analyzeSentenceStructure()` | Still feeds the Sentence Structure UI section and provides `restartExamples` for user-facing coaching |
| `PromptRelevanceService.isLikelyGibberish()` | Retained as a standalone utility; removed only from the scoring pipeline |
| `analysis.clarity: Double` field on `SpeechAnalysis` | Required by the `Decodable` init for backward compatibility with stored recordings |
| `scoreCeiling` comment block | The comment explaining the removal is intentional documentation |
| Dual `articulationRate` computations | Serve different consumers (UI metrics vs. fluency scoring) |

---

## Remaining Improvement Opportunities (Not Yet Implemented)

These are lower-priority items that require more careful migration planning:

1. **`VocabComplexity.uniqueWordRatio`** — Now superseded by MATTR as the primary diversity signal. The field is still displayed in the UI ("Unique words: 47 (68%)"). Consider replacing with MATTR in the next UI refresh cycle.

2. **`analysis.clarity: Double`** — A legacy field (0-100 double) that duplicates `analysis.speechScore.subscores.clarity: Int`. It is only written in `analyze()` and decoded in the custom `Decodable` init for backward compatibility. Safe to remove in a future SwiftData migration.

3. **`ScoreWeightsView` weight customization** — Now that the Substance Gate operates *outside* the weighted average, users who set all weight to a single subscore (e.g., 100% Vocabulary) will still be gated by substance. The UX could be improved by adding a visual indicator showing the substance gate's current multiplier alongside the weight sliders.

4. **`AGENTS.md` / `CLAUDE.md` duplication** — Both files contain identical content. One should be the canonical source with the other pointing to it.
