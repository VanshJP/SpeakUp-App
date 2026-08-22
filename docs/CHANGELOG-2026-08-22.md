# Change log — 2026-08-22

Six user-reported problems, fixed across four parallel work streams plus a follow-up build-fix pass. Feature docs were updated in the same pass (see § Docs at the bottom). No builds were run per project rules — verification handoff is at the end.

---

## 1. Tapping the transcript restarted playback instead of seeking

**Root cause (two stacked defects):**
- `AudioService.play(url:)` unconditionally created a new `AVAudioPlayer` on every call — even mid-playback of the same file. Tearing down and re-priming the decoder lands on the ear as a jump-cut restart.
- WhisperKit word timings can be zero/non-finite (or synthesized by splitting segment text evenly), so tapping such a word seeked to 0.

**Changes:**

| File | Change |
|------|--------|
| `SpeakUp/Services/AudioService.swift` | `play(url:startingAt:)` now reuses the live player when `playerURL == url` (seek + resume) instead of rebuilding it; new absolute-time `seek(toTime:)`; shared clamping core `seekPlayer(to:)`; fraction-based `seek(to:)` clamps to 0…1; `playerURL` tracking cleared in `stop()`. After natural finish, tapping a word replays from that point (player retained). |
| `SpeakUp/Views/Detail/TranscriptViews.swift` | Tap-to-play gesture attaches only when `word.start` is finite and `> 0`. |

## 2. Filler-word timestamps removed from recording detail

Printed clock times were often wrong (same timing root cause as above). The moments stay playable — only the printed numbers are gone.

| File | Change |
|------|--------|
| `SpeakUp/Views/Detail/RecordingDetailView.swift` | Filler chips render count + tappable waveform glyph; no time text; still route through `playFrom`. |
| `SpeakUp/Views/Detail/CoachingTipsView.swift` | "Hear it · 0:38" pill → "Hear it" (accessibility label drops the time too). |

Transport elapsed/total clocks in `PlaybackDrawer` and WPM chart axis labels are not stamps and were kept.

## 3. Word swaps: filler-only → context-aware suggestions

Previously swap suggestions existed only for filler categories via a static alternatives map.

**Decision:** heuristic-first, deterministic, on-device — no LLM dependency for the base path.

| File | Change |
|------|--------|
| `SpeakUp/Services/WordSwapSuggester.swift` **(new)** | Pure `nonisolated` engine: per-occurrence disambiguation by neighbors/sentence position ("like three weeks" → **about**, "platforms like Figma" → **such as**, "feels like we rushed" → **as if**, sentence-final "right?" → silence + one check-in, "really good" → **excellent**, "just want" → **I want**, "things like planning" → name them); ranking by dominant pattern (ties: earliest use, then alphabetical); ±6-word fragment builder with target tinting. |
| `SpeakUp/Services/LexiconInsightsEngine.swift` | `SessionWordHit` carries typed `occurrences` (token ranges + fragments + ranked options); `sessionHits` wires the suggester; `"a lot"` added to hedge phrases (vague quantity now counts toward softeners). Legacy hand-built hits keep the static-map fallback. |
| `SpeakUp/Views/Detail/CrutchSwapsCard.swift` | Each habit row shows ONE primary swap (bolded chip + when/why cue) plus up to two alternates, and an "In context" line quoting the actual transcript around the strongest occurrence. Call-site signature unchanged (`CrutchSwapsCard(hits:onPlayStamp:)`). |
| `SpeakUpTests/WordSwapTests.swift` **(new)** | 21 cases: disambiguation, ranking/tie-breaks, determinism, fragments, degenerate input, legacy compat. |

## 4. AI Coach insight stated bare scores ("44/100") without naming the metric

| File | Change |
|------|--------|
| `SpeakUp/Services/CoachingPrompt.swift` | System prompt hard-requires metric names before every score, listing verbatim `CoachDimension` titles (both Apple Intelligence and local-model paths share this builder). New pure sanitizer post-pass `CoachingInsightSanitizer.namingBareScores(_:subscores:)` prefixes any remaining bare score pattern with the dimension whose subscore matches; named scores and unmatched numbers are left untouched. |
| `SpeakUp/Services/LLMService.swift` | `sanitizeCoachingInsight` runs the naming pass on extracted tips before the specificity gate. |
| `SpeakUpTests/CoachingTests.swift` | 8 new tests (bare-score prefixing, "out of 100", named-score protection, ties, look-back window, prompt-rule presence). |

Example: "44/100" → "Vocal Variety 44/100".

## 5. Progress page redesigned start to finish

Old shape: one ambiguous "Interview Readiness" composite leading a chart page with weak hierarchy.

**New hierarchy: conclusion → evidence → reference.**

| File | Change |
|------|--------|
| `SpeakUp/Views/History/ProgressChartsView.swift` | Trajectory hero band first (score direction + momentum verdict), then scenario readiness family, then words profile, then metric charts/journal entry points as reference material. |
| `SpeakUp/Services/ScenarioReadinessEngine.swift` **(new)** | Pure `nonisolated` engine. `PracticeScenario` taxonomy — Interviews / Public Speaking / Storytelling / Everyday Conversation (+ "Everything Else" only for unrecognized categories), exhaustively mapped from every prompt category. Per-scenario readiness reuses/adapts the composite-weight math per bucket (trend + weak rate + consistency), thin-data honesty (<4 sessions capped below "Ready", labeled early read), weakest-habit "what's holding it back" line. |
| `SpeakUp/Views/History/ScenarioReadinessSection.swift` **(new)** | Scenario cards; unpracticed core scenarios render as compact invitation rows with blurbs, not full cards; aggregate readiness survives only as a header chip. |
| `SpeakUp/Views/History/LanguageInsightsView.swift` | Adjusted to sit in the new hierarchy order. |
| `SpeakUpTests/ScenarioReadinessTests.swift` **(new)** | Bucketing (every category case), thin-data thresholds, monotonicity, empty states. |

Zero-session scenarios point at their practice surface instead of showing empty cards.

## 6. Word Workout judged old recordings against today's words

**Root cause:** `resolveVocabWorkoutIfNeeded` called `todaysChallenge` for every recording regardless of date.

**Fix:** snapshot the day's spotlight words onto the recording at processing time; judge each take by its own day's list.

| File | Change |
|------|--------|
| `SpeakUp/Models/Recording.swift` | ⚠️ ADDITIVE schema fields (both optional, nil-defaulting): `var vocabChallengeDayStamp: String?`, `var vocabChallengeWords: [VocabChallengeWord]?`. No renames/removals; legacy recordings simply have none. |
| `SpeakUp/Services/RecordingProcessingCoordinator.swift` | One `todaysChallenge` pick at job start feeds detection + FSRS grading + snapshot; snapshot written on the success path right after `recordUsage`, before save (after the mandatory re-fetch-by-id). Failure paths return earlier, so no snapshot outlives a failed analysis. |
| `SpeakUp/Services/VocabChallengeService.swift` | Pure resolver `workout(forRecordingAt:snapshotDayStamp:snapshotWords:preferences:)` + `challenge(dayStamp:words:)`. Behavior matrix: snapshot present → authoritative (even if day cache later skipped/refilled); empty snapshot → hide; no snapshot but recorded today → fall back to today's challenge (pre-update takes processed same day keep scoring); older without snapshot → hide card (silently correct beats loudly wrong); workout disabled → hide. |
| `SpeakUp/Views/Detail/RecordingDetailView.swift` | `resolveVocabWorkoutIfNeeded` rewritten to call the resolver. Still runs once in ready-state setup, never in `body`. |
| `SpeakUpTests/VocabChallengeTests.swift` | 6 new resolver tests covering the full matrix. |

---

## Follow-up build-fix pass

First Xcode pass surfaced one error and several isolation warnings (module default is MainActor). All fixed:

| File | Issue → Fix |
|------|-------------|
| `SpeakUp/Services/LexiconInsightsEngine.swift` | **Error:** `WordSwapOption.alternates` didn't exist → winner's fallbacks now read from the source occurrence's remaining ranked options (`options.dropFirst()`). |
| `SpeakUp/Models/FillerWordList.swift` | Whole type marked `nonisolated` (pure word lists) — fixes both `isFillerWord` cross-isolation warnings from lexicon passes. |
| `SpeakUp/Models/PromptMix.swift` | Whole struct marked `nonisolated` (pure Sendable value type); `OnboardingGoal.promptCategories` marked `nonisolated` — callable from the nonisolated init/background passes. |
| `SpeakUp/Services/CoachEvidenceService.swift` | `String.hasSuffixIn` marked `nonisolated` (pure helper called from nonisolated gap analysis). |
| `SpeakUp/Services/WhisperService.swift` | `decodeStallTimeout` static let marked `nonisolated` (read from detached watchdog task). |
| `SpeakUp/Models/SharedPromptLink.swift` | `droppingText` computed var marked `nonisolated` (pure copy used in URL building). |
| `SpeakUp/Services/LiveTranscriptionService.swift` | `interruptionObserver`: plain `nonisolated` is illegal on @Observable-tracked mutable storage → final form `@ObservationIgnored nonisolated(unsafe)` (token out of change tracking; unsafe remains the legal deinit-access path for a non-Sendable NSObjectProtocol token). |
| `SpeakUp/Services/ScenarioReadinessEngine.swift` | `PracticeScenario` gained `Identifiable` (had `id`, missing conformance — broke `ForEach`). |
| `SpeakUp/Views/Detail/CoachingTipsView.swift` | Point-free `AppColors.tint(for:)` reference can't carry actor isolation into `map` → explicit closure `{ AppColors.tint(for: $0) }`. |

Not ours, flagged only: StoreKit scheme warning references a stale path (`project.xcworkspace/Products`) — re-select `Products.storekit` in Scheme → Run → Options.

## Docs updated in the same pass

- `docs/features/recording-detail.md` — invariants 17–19 (stamped surfaces stay playable without printing times; tap-to-play only for usable timestamps; playback seeks never restarts), new "Insight scores are never bare numbers" section, § Word swaps rewritten for the suggester.
- `docs/features/history-progress.md` — rewritten for the scenario readiness family, new hierarchy, engine/test rows.
- `docs/features/vocab-challenge.md` — invariants 12–14 (snapshot at processing time; view never substitutes today's pick; snapshot authoritative over day cache).
- `docs/features/README.md` — index row updates.

## Verification handoff

Nothing was built or run (project rule). Suggested:

```bash
xcodebuild -scheme SpeakUp -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme SpeakUp -destination 'platform=iOS Simulator,name=iPhone 16' test
```

New files are picked up automatically (synchronized folders — no pbxproj edit needed). Pre-existing uncommitted WIP in the working tree was left untouched throughout.
