# Recording detail — analyze & reveal UI

## Purpose

After a take: staged analyzing, score reveal, transcript / playback / coaching, next steps. Marks first completed result (unlocks auto-paywall + review eligibility).

## Key files

| Role | Path |
|------|------|
| Root | `SpeakUp/Views/Detail/RecordingDetailView.swift` |
| Stages | `AnalyzingView`, `ScoreHeroCard`, `ScoreRevealView` |
| Playback | `PlaybackDrawer`, `RecordingDetailPlaybackViewModel` |
| Transcript | `TranscriptViews`, `TranscriptExcerptCard`, `WPMChartView` |
| Coaching / next | `CoachPlanService`, `CoachEvidenceService`, `CoachingTipService`, `CoachingPrompt`, `CoachingTipsView`, `NextStepCard`, `TakeComparisonCard`, `ListenBackEncouragementView` |
| Coach note | `CoachMomentService.evaluateAfterSession` → `CoachMomentCard` above next step (axis mark); a soft landing replaces the next-step card so retry is never duplicated. See [coach-moments.md](./coach-moments.md). |
| Word workout result | `VocabChallengeResultCard` on the breakdown tab when today's spotlight words exist |
| Word swaps | `CrutchSwapsCard` (transcript tab) — per-session crutch words from `LexiconInsightsEngine.sessionHits`, each occurrence a playable stamp, each habit carrying swap suggestions |
| First-run setup | `FirstRecordingSetupSheet` (post-onboarding, after first score) |
| Share cards | `ShareCardSheet` (picker + preview), `ScoreCardRenderer`, `ProgressCardRenderer`, `SharePresenter`, `SharedPromptLink`, `SharedPromptResolver` |
| Inbound challenge | `SharedChallengeStore`, `FriendChallengeCard` (Today), countdown chrome in `CountdownOverlayView` |

> Note: older docs mentioned `DetailAnalysisTab` — layout evolved into hero / reveal / transcript / playback pieces. Prefer current files above.

## Invariants

1. Resolve `resolvedAudioURL` / file existence **once** into `@State` — not in `body`.
1a. Same discipline for every blob-backed input: `resolveSessionDataIfNeeded(for:)` decodes `fullAnalysis` plus timed words into state exactly once (speaker turns, crutch hits, and coach evidence derive in that same pass) and `body` reads only the caches. Transcripts past 600 words page through chunked `LazyVStack`s instead of building one eager FlowLayout over every word. Retries clear the transcript caches before re-enqueueing so they rebuild from the fresh words; WPM backfill and the LLM coherence pass both read/write through `fullAnalysis`/`setAnalysis`, so neither strips the other's advanced metrics; deleting here calls `cancelProcessing(recordingID:)` before the row goes.
2. `ReviewRequestService.markFirstResultSeen()` only when analysis completed — gates the review prompt.
3. Deferred-by-allowance UI offers Try Again only — no unlock path exists during the beta, and `AllowanceGate` never defers while `BetaAccess.allFeaturesFree` is true.
4. Processing: prefer `RecordingProcessingCoordinator` over ad-hoc parallel jobs.
4a. Coach moments are fresh-result-only (`ContentView.freshResultRecordingId` → `RecordingDetailView.allowsCoachMoments`). Browsing an old History/Story recording never evaluates or shows a new note.
4b. The full-screen post-recording analyzing state always offers **Save & close**. The saved recording remains in History and the coordinator keeps scoring in the background; a model download must never trap the user. `ContentView` waits for that existing job, then evaluates achievements silently — unlock state stays correct without replacing the user's chosen exit with an overlay.
4c. Recovery copy protects the work: "Couldn't score this take" + "Your recording is safe." Raw backend errors never appear on the result screen, and playback failures never interpolate `localizedDescription`.
5. After long transcribe/analyze: coordinator re-fetches by id before write (deleted object trap).
6. Share score / progress cards via `SharePresenter` only (completed-share analytics). Score-card shares that include the prompt also attach a caption with a try-this-prompt URL (`SharedPromptLink`); do not invent a second activity sheet.
7. Prompt text on a share card and in the share URL is opt-in. Scores-only shares must not put the prompt (or `beat`) on the link. Story sessions may show the title on the card but never encode story body into the URL.
8. `ShareCardSheet` is the one share surface: variant tabs (Scores / Challenge) over a live preview, a `ScoreCardTheme` filter strip, then Save / Copy / Share. `.scores` **must** stay the default selection — the default card carries no prompt. Themes change only the card backdrop (all stay dark, so the hero body needs no per-theme colors) and persist to `UserSettings.shareCardTheme`; the render cache is keyed by variant **and** theme. Save and Copy log `share_complete` too; they are the same intent by another route.
9. Share captions are three lines at most (headline, prompt quote, URL). Explanation belongs on the card or in the sheet's subtitle, not in text the recipient reads.

## Coaching layer

Four pure pieces feed one screen. All are `nonisolated` and take PODs, so all are testable without a container (`SpeakUpTests/CoachingTests.swift`).

| Piece | Answers | Input |
|-------|---------|-------|
| `CoachPlanService` → `CoachPlan` | *What am I working on, and is it moving?* | rolling window of `SpeechAnalysis` + `ScoreWeights` |
| `CoachEvidenceService` → `CoachEvidence` | *Which moment do I point at?* | this session's analysis + `transcriptionWords` |
| `CoachingTipService` → `[CoachingTip]` | *What do I say about this session?* | analysis + `CoachingContext` |
| `CoachingPrompt` | *What does the LLM get told?* | the same `CoachingContext` |

`CoachingContext` bundles target WPM, user weights, plan, and evidence. It defaults to empty, so callers with only an analysis (onboarding's first take, the LLM fallback) still work.

### How the focus is chosen

`CoachDimension` has one case per subscore. The focus is the largest **weighted deficit** — `(85 − windowMean) × userWeight` — not the lowest subscore: a 68 in a dimension worth 18% of the score costs more than a 60 in one worth 6%.

Stickiness comes from averaging the window, not from stored state. There is no persisted "current focus" field, and none is wanted: an average moves slowly by construction, so the focus survives one good day without anyone having to remember it was picked. Trend is newest half vs. oldest half over ≥ 4 sessions; anything inside ±3 points reads as flat.

### Invariants

10. Tips are ranked by weighted deficit, then by dimension name. The tiebreak is load-bearing — `sort` is not stable and `generateTips` runs in `body`, so equal deficits would otherwise reorder between redraws.
11. Signal-quality notes (noise, overlapping speakers) are `.signal` kind and only fill leftover slots. They are caveats about the recording, never coaching, and must never displace a real tip.
12. Pace copy reads `UserSettings.resolvedTargetWPM`, never a hardcoded band. Auto-calibration moves the target, and fixed "130-170" copy contradicts the pace subscore whenever it does.
13. `CoachDimension.analyticsSlug` is frozen — those strings predate the enum and feed the `next_action_taken` funnel. `rawValue` is not a substitute.
13a. The focus card is `CoachFocusCard` in `Views/Components/`, shared with Today. It is hidden when `Snapshot.currentIsInPlanWindow` is false — the plan is always built from the newest sessions, so showing it on a three-month-old recording would imply that focus was what the session was about. The focus *tip* still appears; it is derived from that session's own numbers.
13b. `CoachDimension.practiceRoute` is the only dimension → tool mapping. Clarity goes to Read Aloud, delivery and vocal variety to the warm-up; forcing those into the nearest drill printed "Try Pause Practice" under a tip about pitch range. `NextStepCard` and the tip rows both read it — they used to carry separate copies.
14. The coaching plan loads *before* the LLM coherence pass fires (`runReadySetupIfNeeded`), so the generated insight has a focus to lead with.
15. Coaching reads `Recording.fullAnalysis`, not `analysis` — see gotcha "SwiftData drops the advanced analysis metrics".
16. Every play request goes through `startPlayback(of:at:)`. The drawer, the transcript, the filler chips, and the tips all need the same media checks and the same first-listen gate; a second path would drift from it. The gate holds the requested timestamp in `pendingPlaybackTime` rather than dropping it.
17. Stamped surfaces stay **playable** but no longer print the clock time. Whisper word stamps drift enough that a visible "0:38" was often wrong — a wrong number reads as a broken app while a wrong seek just plays nearby audio. Filler chips render waveform glyphs (one per occurrence) and the tip pill says "Hear it"; both still route through `startPlayback(of:at:)`. Never reintroduce a printed stamp without also fixing stamp accuracy end-to-end.
18. Word tap-to-play attaches only when the timestamp is usable (`start > 0`, finite). Whisper's alignment heads emit zero starts often enough that tapping such a word jumped to the top of the take; the drawer play button still covers "from the top".
19. Playback seeks, it does not restart. `AudioService.play(url:startingAt:)` reuses the live `AVAudioPlayer` when the URL matches (`playerURL`) — recreating it mid-playback landed as an audible jump-cut. Fresh URLs still take the full load path. Absolute-time requests go through `seek(toTime:)`; the fraction-based `seek(to:)` remains the drawer scrubber's API. Both clamp into `[0, duration − 0.1]`.

### Insight scores are never bare numbers

The coaching prompt (`CoachingPrompt.system`) instructs every backend to prefix a score with its metric name using the verbatim `CoachDimension` titles ("Vocal variety 44/100", never "44/100") — in compact mode too. Small local models drop the label anyway, so `CoachingInsightSanitizer.namingBareScores(_:subscores:)` post-passes the tips: a `\d{1,3}/100` (or "out of 100") match is relabelled only when its number equals one of this session's subscores **and** no metric word sits within the 40-character look-back ("overall" counts as named). Unmatched numbers stay as written rather than guessing a label.

## Word swaps

`CrutchSwapsCard.hits(for:)` runs `LexiconInsightsEngine.sessionHits(from:)` over the take's timed transcription words. Pipeline-tagged fillers (`isFiller`) are authoritative; hedge phrases match longest-first and consume their tokens so "not really sure" never double-counts its "really". Rows are habits only — two-plus occurrences, capped at six — each with category badge, playable stamps, a context fragment, and contextual swaps. Swaps come from `WordSwapSuggester` (pure, deterministic, on-device — no LLM): each occurrence is disambiguated by neighbors and sentence position — "like three weeks" → "about", "platforms like Figma" → "such as", "feels like we rushed" → "as if", sentence-final "right" → silence plus one real check-in, "really good" → "excellent", "just want" → "I want", "things like planning" → name them. Each row surfaces ONE primary swap (bolded, bordered chip) with its when/why cue plus up to two alternates, ranked by dominant pattern across occurrences (ties: earliest use). The strongest occurrence renders ±6 words of the actual transcript under "In context", crutch word tinted. `"a lot"` joined the hedge-phrase list, so vague quantity now counts toward softeners. Hand-built hits without occurrences keep the legacy alternatives-map behavior, and fragment/swaps blocks collapse into single accessibility elements.

## Repeat takes

`PersonalAverage.PreviousTake` finds the last attempt at the same prompt or story (`storyId ?? prompt?.id`, matching how relevance picks its source text) inside a `repeatScanLimit` tail, and `TakeComparisonCard` renders it directly under the hero.

This is the one surface that answers "did the coaching work". The scan filters on the relationship *before* unwrapping `analysis`, so the extra rows cost a fault each rather than a blob decode each. `NextStepCard`'s retry passes `recording.prompt`, so a practice-again always lands back here with a comparison; story re-runs only match when re-practiced through the Stories flow.

Deltas inside ±3 are reported as noise, not progress — same threshold as `CoachPlan.Trend`.

## Cross-links

[speech-pipeline.md](./speech-pipeline.md) · `/SPEECH.md` · [monetization.md](./monetization.md) · [analytics-review.md](./analytics-review.md) · [achievements-goals.md](./achievements-goals.md) · `/docs/AGENT_GOTCHAS.md`
