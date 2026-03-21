# SPEECH_SCORING_REBUILD_BLUEPRINT.md

> **ARCHIVED** — This document describes the March 2026 isolation-aware rebuild.
> The current authoritative architecture reference is `SPEECH_ANALYSIS_DEEP_DIVE.md`
> and `SPEECH_SCORING_IMPROVEMENTS.md`.

---

# Speech Scoring Rebuild Blueprint

This document captures the rebuild direction for SpeakUp's scoring stack so it can compete with high-end speech coaching apps.

## Why this rebuild

Traditional "single transcript + static weights" scoring fails in noisy and conversational conditions. To be production-grade, the scoring engine must:

1. score the **target speaker**, not everyone in the room,
2. avoid punishing users for **background noise/crosstalk artifacts**,
3. produce **coaching advice that is behaviorally correct** (never encouraging filler habits).

## Benchmark-informed dimensions

Modern speech assessment systems consistently score across:

- delivery (pace, prosody, pause control),
- language quality (clarity, structure, lexical precision),
- coherence/relevance,
- signal confidence (audio quality, diarization confidence).

## Implemented in this iteration

### 1) Speech isolation frontend before ASR

- Added `SpeechIsolationService`.
- Pipeline: high-pass filter + adaptive noise gate.
- Runs before Whisper/Apple fallback transcription when beneficial.
- Produces `AudioIsolationMetrics` (SNR-in, SNR-out, suppression delta, residual noise score).

### 2) Conversation-aware primary speaker labeling

- Added `ConversationIsolationService`.
- Builds an early-session voice profile and scores each word on acoustic similarity (pitch + energy).
- Labels words with:
  - `isPrimarySpeaker`
  - `speakerConfidence`
- Produces `SpeakerIsolationMetrics` (primary ratio, filtered words, switch count, separation confidence, conversationDetected).

### 3) Scoring now uses speaker-focused stream when confidence is adequate

- `SpeechService.analyze(...)` now scores on primary-speaker words when isolation confidence clears thresholds.
- Fallback to full transcript when isolation confidence is insufficient (conservative behavior).
- Added reliability stabilization so noisy/crosstalk sessions are pulled toward neutral rather than over-penalized.

### 4) AI coaching guardrails

- Updated LLM coaching prompt to explicitly forbid recommendations that encourage fillers.
- Added sanitizer rules to remove disallowed advice and fallback to safe tips.
- Added coaching tips that explain low-confidence isolation/noisy conditions.

### 5) Rebalanced default scoring weights

- New defaults prioritize intelligibility and speaking discipline:
  - clarity `0.18`
  - pace `0.12`
  - filler `0.14`
  - pause `0.12`
  - vocal variety `0.12`
  - delivery `0.10`
  - vocabulary `0.08`
  - structure `0.08`
  - relevance `0.06`

## Next phase (recommended)

1. **True diarization model integration** (CoreML/ANE-capable) for explicit speaker IDs.
2. **Live conversation mode UI** with voice-anchor calibration and per-turn score deltas.
3. **Metric calibration set**: build a labeled dataset (clean/noisy, solo/conversation, novice/advanced) and tune thresholds against human ratings.
4. **Score confidence surfaced in UI** so users can see when environment quality reduced certainty.
