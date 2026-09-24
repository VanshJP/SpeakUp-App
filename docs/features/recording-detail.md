# Recording detail — analyze & reveal UI

## Purpose

After a take: staged analyzing, score reveal, transcript / playback / coaching, next steps. Marks first completed result (unlocks auto-paywall + review eligibility).

## Key files

| Role | Path |
|------|------|
| Root | `SpeakUp/Views/Detail/RecordingDetailView.swift` |
| Stages | `AnalyzingView`, `ScoreHeroCard`, `ScoreRevealView` |
| Playback | `PlaybackDrawer`, `RecordingDetailPlaybackViewModel` |
| Transcript | `TranscriptViews`, `TranscriptExcerptCard`, `WPMChartView`, `TakeTimelineView` |
| Coaching / next | `CoachPlanService`, `CoachEvidenceService`, `CoachingTipService`, `CoachingPrompt`, `CoachingTipsView`, `NextStepCard`, `TakeComparisonCard`, `ListenBackEncouragementView` |
| Coach note | `CoachMomentService.evaluateAfterSession` → `CoachMomentCard` above next step (axis mark); a soft landing replaces the next-step card so retry is never duplicated. See [coach-moments.md](./coach-moments.md). |
| Word workout result | `VocabChallengeResultCard` on the breakdown tab when today's spotlight words exist |
| Word swaps | `CrutchSwapsCard` (transcript tab) — per-session crutch words from `LexiconInsightsEngine.sessionHits`, each habit an accordion row of before/after rewrites with playable occurrences. Structural repetition is **not** a swap row: tip + plum transcript highlight own that signal. |
| First-run setup | `FirstRecordingSetupSheet` (post-onboarding, after first score) |
| Share cards | `ShareCardSheet` (picker + preview), `ScoreCardRenderer`, `ProgressCardRenderer`, `SharePresenter`, `SharedPromptLink`, `SharedPromptResolver` |
| Inbound challenge | `SharedChallengeStore`, `FriendChallengeCard` (Today), countdown chrome in `CountdownOverlayView` |

> Note: older docs mentioned `DetailAnalysisTab` — layout evolved into hero / reveal / transcript / playback pieces. Prefer current files above.

## Invariants

1. Resolve `resolvedAudioURL` / file existence **once** into `@State` — not in `body`.
1a. Same discipline for every blob-backed input: `resolveSessionDataIfNeeded(for:)` decodes `fullAnalysis` plus timed words into state exactly once (speaker turns, crutch hits, and coach evidence derive in that same pass) and `body` reads only the caches. The decode runs off the main actor in a detached `ModelContext`; while it is in flight the ready screen shows a loading row instead of an empty breakdown. Transcripts past 600 words page through chunked `LazyVStack`s instead of building one eager FlowLayout over every word. Retries clear the transcript caches before re-enqueueing so they rebuild from the fresh words; WPM backfill and the LLM coherence pass both read/write through `fullAnalysis`/`setAnalysis`, so neither strips the other's advanced metrics; deleting here calls `cancelProcessing(recordingID:)` before the row goes. The hero radar does **not** replay its draw-in / score count-up on every appear — `ScoreHeroCard` keeps `animate: false` (the post-take `ScoreRevealView` already owns that moment).
2. `ReviewRequestService.markFirstResultSeen()` only when analysis completed — gates the review prompt.
3. Deferred-by-allowance UI offers Try Again only — no unlock path exists during the beta, and `AllowanceGate` never defers while `BetaAccess.allFeaturesFree` is true.
4. Processing: prefer `RecordingProcessingCoordinator` over ad-hoc parallel jobs.
4a. Coach moments are fresh-result-only (`ContentView.freshResultRecordingId` → `RecordingDetailView.allowsCoachMoments`). Browsing an old History/Story recording never evaluates or shows a new note.
4b. The full-screen post-recording analyzing state always offers **Save & close**, at the **top leading** corner, where every other full-screen exit in the app lives. It takes no manual safe-area inset, and neither does the skeleton behind it. `AnalyzingView` carried a `systemTopSafeAreaInset` helper that read `keyWindow.safeAreaInsets.top` on the premise that a parent ignored the safe area. Nothing in either host does — `RecordingView`'s cover and the detail screen's `NavigationStack` both inset their content — so the value was counted twice, by a different amount on every device (+20pt on an SE, +59 on a Pro, +62 on a Pro Max). The helper is gone from both call sites; the layout already knows the number. The saved recording remains in History and the coordinator keeps scoring in the background; a model download must never trap the user. `ContentView` waits for that existing job, then evaluates achievements silently — unlock state stays correct without replacing the user's chosen exit with an overlay.
4b1. **The wait shows the take.** The analyzing skeleton's status header draws `TakeWaveform` (`.scan`): this recording's own `audioLevelSamples` as 56 loudness bars with a scan line sweeping them (30 fps `TimelineView`, one `Canvas`, still under Reduce Motion). The samples decode once in a `.task`, never in `body`. The stage line walks Transcribing → Fillers → Pace → Scoring **once and holds on the last** (interval `max(2.5s, take length / 15)`): it used to wrap back to "Transcribing" and read as the analysis restarting. The sweep may loop; stage text may not.
4b2. **`ScoreRevealView` choreography.** The score sits on a 0-100 `ArcDial` crown (display-only, full bleed, ticks filled in the score ramp) that turns from your **average** to this take on `.easeOut(0.9)` while `CountUpText` climbs the same curve in the bowl - no history yet, it turns up from zero - so the turn *is* the delta. The dial's own detent ticks at each ten it passes (not `Haptics.playCountUp`, which assumes a count from zero). Then a landing kick and a bloom in the score color (a background outside the dial, whose clip would square it off), the band haptic, and the verdict. Confetti (`ConfettiView`, launched from behind the dial) only for a **strong** take or a **solid personal best** - a low score met with confetti reads as sarcasm. Badges: personal best, and **streak day** when this take is the day's first (`StreakProtection.dayStarted`, `RecordingView.streakDayEarned` - dates only, fetched beside the baselines): the flame arrives ash-grey and ignites as the day rolls N-1 → N. "Your best yet" requires `Baselines.seenAllHistory` (the window reached the first recording); otherwise it says "Best in 20 sessions". Counting analyzed takes instead let unscored rows fake an all-time claim.
4b3. **The take timeline shows where, the stats grid shows how many.** `TakeTimelineView` sits under the stats grid on the breakdown tab: the take drawn as a hypnogram, one lane each for speaking / pause / filler, built from the cached timed words by the pure `TakeTimeline` (gaps under 0.4 s fold into the run; a gap over 1.2 s after a word with no full stop is a **long pause**, the same thresholds `SpeechService` uses to count pauses and hesitations - change them together). Lanes follow `trackPauses` / `trackFillerWords`; another speaker's words are blank time, not a pause. It prints **no counts** (the grid above already does, invariant 10) and no per-event clock times (invariant 17) - only `0:00` and the take's length. A tap seeks half a second before the moment it lands on through `playFrom`, and the playhead follows `RecordingDetailPlaybackViewModel`, read inside the timeline so ticks do not re-render the page. Chart type is capped at AX1; VoiceOver gets a talk-share summary plus play actions for fillers and long pauses.
4c. Recovery copy protects the work: "Couldn't score this take" + "Your recording is safe." Raw backend errors never appear on the result screen, and playback failures never interpolate `localizedDescription`.
4d. Every production `RecordingDetailView` entry supplies a repeat route and a stable `RecordingDetailSource`. The callback receives the full `Recording`, not only its optional prompt: History preserves Story id and target duration; Story routes to the same Story; Learn preserves target duration and framework. A result must never render a primary “Practice again” action backed by an optional/no-op callback. Repeat dismisses the old detail before launching the new take.
5. After long transcribe/analyze: coordinator re-fetches by id before write (deleted object trap).
6. Share score / progress cards via `SharePresenter` only (completed-share analytics). Score-card shares that include the prompt also attach a caption with a try-this-prompt URL (`SharedPromptLink`); do not invent a second activity sheet.
7. Prompt text on a share card and in the share URL is opt-in. Scores-only shares must not put the prompt (or `beat`) on the link. Story sessions may show the title on the card but never encode story body into the URL.
8. `ShareCardSheet` is the one share surface: variant tabs (Scores / Challenge) over a live preview, a `ScoreCardTheme` filter strip, then Save / Copy / Share. `.scores` **must** stay the default selection — the default card carries no prompt. Themes change only the card backdrop (all stay dark, so the hero body needs no per-theme colors) and persist to `UserSettings.shareCardTheme`; the render cache is keyed by variant **and** theme. Save and Copy log `share_complete` too; they are the same intent by another route.
9. Share captions are three lines at most (headline, prompt quote, URL). Explanation belongs on the card or in the sheet's subtitle, not in text the recipient reads.
10. **Nothing on this screen is said twice.** The page already draws the dimension, the score, the window and the trend as chrome, so prose beside them carries meaning, not a read-back of the pixels above it:
    - `CoachDimension.technique` is `(name, how, why)`. `how` is the instruction a card asks for in the second before you speak; `why` is what earns it and belongs behind a disclosure. `fullTechnique` re-joins them for teaching points and the LLM prompt. `NextStepCard` takes `how` plus the technique's **name**; it never takes the joined form.
    - `CoachFocusCard` prints `CoachPlan.focusNote`, not `headline`. `headline` names the dimension, the number, the window and the direction, and exists for readers that have none of them on screen: `CoachingPrompt`, and `NextStep` on a session where nothing scored low enough to coach. Printing it under a row that already draws all four was the same fact five times.
    - `graduationLine` states the bar, not the dimension: "Three sessions at 85 to move on.", with the target already shown as `/ 85`.
    - `NextStepCard` labels its score **this take**. It is the session's subscore while the Coaching tab prints the rolling average for the same dimension, and two different numbers under one word read as a bug.
    - The share CTA is one row (icon, title, chevron), not a card with a heading, a subtitle restating the heading and a full-width button restating both.

## Coaching layer

Four pure pieces feed one screen. All are `nonisolated` and take PODs, so all are testable without a container (`SpeakUpTests/CoachingTests.swift`).

| Piece | Answers | Input |
|-------|---------|-------|
| `CoachPlanService` → `CoachPlan` | *What am I working on, and is it moving?* | rolling window of `SpeechAnalysis` + `ScoreWeights` |
| `CoachEvidenceService` → `CoachEvidence` | *Which moment do I point at?* | this session's analysis + `transcriptionWords` (includes structural-repetition quote when present) |
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
12a. `AnalyzingView`'s tip carousel is coach-waiting copy (technique while you wait), not therapy reassurance. Keep Save & close; do not soft-pedal into "you were brave for pressing record."
12b. **The self-check is a wait-shortener, and is designed as one.** The full-screen recorder shows it while the take scores (`AnalyzingView(waitsForScore: true)`). The question owns the page - no card around it: story-style step segments (tap to go back), a one-line **Take saved · 1:24** eyebrow so the take is acknowledged before anything is asked, then the question and its control. Yes/No is two large round buttons, selected = white fill + ink, and moves on after `advanceDelay` (450 ms). Scoring status lives in a floating glass dock at the bottom beside the one action: stage copy over the take's own waveform, which **is** the progress bar (`TakeWaveform(mode: .estimate)` - bars light left to right, easing toward 90 % over a duration-scaled guess with a shimmer at the leading edge, and finish only when the score lands; there is no second meter). The last answer saves the check-in and slides to a wrap-up that plays the answer back as the setup for the reveal ("Felt good to you. Let's see if the score agrees.") with a plain-text tip under it. When the score lands (`analysisReady`, or `isStillProcessing` false after a failure) the recorder hands over by itself after `handOverBeat`; "See your score" / "Skip to results" hand over at once and **keep any answers already given** (skipping used to discard them). The detail screen's fallback gate leaves `waitsForScore` false and hands over on the last answer, as before. The page always scrolls.
12c. **The scale answer is `FeelingDial`** (`Views/Components/FeelingDial.swift`, shared with onboarding's level step), on the shared `ArcDial` (`Views/Components/ArcDial.swift`, also the prompt wheel's). The five self-check words live beside the call site as `takeFeelings`; answers stay stored 1...5 while the dial counts from 0. Words on the rim, one `MoodFace` in the bowl that bends from a frown to a grin with the wheel, over the word and its line; ticks from Rough to the answer take the score ramp. The rim tracks the finger 1:1, a flick coasts on the drag's predicted end and lands with a soft spring, and a tap on a word turns straight to it. The disc has a body (lit rim, inner groove), the sides dim as it curves away, and the marker nods at each stop with a selection haptic. **It does not move the page on by itself** - releasing used to advance, which took the second swipe away before anyone could reach Rough or Great. A **Next** / **Save check-in** pill under the wheel commits instead. The in-flight value is local and commits through `onSelect` once per release.
13. `CoachDimension.analyticsSlug` is frozen — those strings predate the enum and feed the `next_action_taken` funnel. `rawValue` is not a substitute.
13a. The focus card is `CoachFocusCard` in `Views/Components/`, shared with Today. It is hidden when `Snapshot.currentIsInPlanWindow` is false — the plan is always built from the newest sessions, so showing it on a three-month-old recording would imply that focus was what the session was about. The focus *tip* still appears; it is derived from that session's own numbers.
13b. `CoachDimension.practiceRoute` is the only dimension → tool mapping. Clarity goes to Read Aloud, delivery and vocal variety to the warm-up; forcing those into the nearest drill printed "Try Pause Practice" under a tip about pitch range. `NextStepCard` and the tip rows both read it — they used to carry separate copies.
14. The coaching plan loads *before* the LLM coherence pass fires (`runReadySetupIfNeeded`), so the generated insight has a focus to lead with.
15. Coaching reads `Recording.fullAnalysis`, not `analysis` — see gotcha "SwiftData drops the advanced analysis metrics".
16. Every play request goes through `startPlayback(of:at:)`. The drawer, the transcript, the filler chips, and the tips all need the same media checks and the same first-listen gate; a second path would drift from it. The gate holds the requested timestamp in `pendingPlaybackTime` rather than dropping it. `listenBackCount` increments only after `AudioService.play` succeeds, then `AchievementService.shared` rechecks **Brave Listener** with the saved count; missing/iCloud-pending/failed media earns nothing.
17. Stamped surfaces stay **playable** but no longer print the clock time. Whisper word stamps drift enough that a visible "0:38" was often wrong — a wrong number reads as a broken app while a wrong seek just plays nearby audio. Filler chips, **word-swap play points**, and the tip pill all render waveform glyphs (one per occurrence, the pill labelled "Hear it"); all route through `startPlayback(of:at:)`. Never reintroduce a printed stamp without also fixing stamp accuracy end-to-end. The swap card printed `0:37` three times for three occurrences seconds apart before it was brought in line — that is what the drift looks like on screen.
18. Word tap-to-play attaches only when the timestamp is usable (`start > 0`, finite) — `WordSwapOccurrence.isPlayable` applies the same rule to swap play points. Whisper's alignment heads emit zero starts often enough that tapping such a word jumped to the top of the take; the drawer play button still covers "from the top".
19. Playback seeks, it does not restart. `AudioService.play(url:startingAt:)` reuses the live `AVAudioPlayer` when the URL matches (`playerURL`) — recreating it mid-playback landed as an audible jump-cut. Fresh URLs still take the full load path. Absolute-time requests go through `seek(toTime:)`; the fraction-based `seek(to:)` remains the drawer scrubber's API. Both clamp into `[0, duration − 0.1]`.

### Insight scores are never bare numbers

The coaching prompt (`CoachingPrompt.system`) instructs every backend to prefix a score with its metric name using the verbatim `CoachDimension` titles ("Vocal variety 44/100", never "44/100") — in compact mode too. Small local models drop the label anyway, so `CoachingInsightSanitizer.namingBareScores(_:subscores:)` post-passes the tips: a `\d{1,3}/100` (or "out of 100") match is relabelled only when its number equals one of this session's subscores **and** no metric word sits within the 40-character look-back ("overall" counts as named). Unmatched numbers stay as written rather than guessing a label.

## Word swaps

`CrutchSwapsCard.hits(from:)` runs `LexiconInsightsEngine.sessionHits(from:)` over the take's timed transcription words. Pipeline-tagged fillers (`isFiller`) are authoritative; hedge phrases match longest-first and consume their tokens so "not really sure" never double-counts its "really". Rows are habits only — two-plus occurrences, capped at six. `"a lot"` is in the hedge-phrase list, so vague quantity counts toward softeners.

Swaps come from `WordSwapSuggester` (pure, deterministic, on-device — no LLM): each occurrence is disambiguated by neighbors and sentence position — "like three weeks" → "about", "platforms like Figma" → "such as", "feels like we rushed" → "as if", sentence-final "right" → silence plus one real check-in, "really good" → "excellent", "just want" → "I want", "things like planning" → name them, sentence-opening "I think" → state it directly, mid-sentence "you know" → cut it, "maybe three weeks" → "about".

### The rewrite is the product

Every option carries a `SwapEdit` describing what it does to the sentence: `.delete`, `.pause` (same edit, different coaching), `.replace(text, extraTokens:)`, or `.advice`. `WordSwapSuggester.rewrite` applies the winning edit to the occurrence's own words and returns the corrected line, so the card shows **You said → Say this** rather than only naming a fix. Rules with no single substitution ("quantify instead") stay `.advice` and render no rewrite — a wrong rewritten sentence is worse than none.

Mechanics the rewrite owes the reader: `extraTokens` lets "really good" collapse to "excellent" instead of "excellent good"; a deleted sentence-initial crutch capitalizes whatever now starts the line; a deleted word hands back the full stop or comma it was carrying, so "we shipped on time right." becomes "we shipped on time."; and a rewrite identical to the original returns nil.

Legacy `alternatives`-map entries have no declared edit, so `SwapEdit.inferred(from:)` reads one off the copy — conservatively: only a string that is *entirely* one quoted phrase becomes a substitution, because “only” when counting matters is a condition, not an instruction.

### Moments, not repetitions

`WordSwapSuggester.moments(in:)` groups occurrences by the advice they earned. Three "just"s in one sentence pattern are **one** moment with three play points; three "just"s in three patterns are three moments, each with its own before/after. `deduplicated` collapses options that edit the sentence identically, so a row can no longer print "cut it" beside “drop “just” entirely” — it did, from the alternatives map, before the edit model existed.

### Card shape

Accordion: the worst habit opens on appear, the rest collapse to `word · category · count` plus a one-line fix, so six habits' worth of examples are not a wall. Play points are waveform glyphs (invariant 17) filtered by `isPlayable` (invariant 18). Alternates render as flat un-tinted pills — they must never borrow the filled-capsule look of the play buttons beside them, which is exactly how the old card styled un-tappable suggestions. Fragment and rewrite collapse into one VoiceOver element so the comparison is read as a sentence pair, and the play buttons stay separately actionable.

Hand-built hits without occurrences keep the legacy alternatives-map behavior end to end: header fix line, "Also works" pills, and `swaps` all fall back to the map, then to category advice.

### Is this habit getting better?

`PersonalAverage.snapshot` also returns a `CrutchBaseline`: mean per-100-word crutch rates over the same window, built from each earlier take's **`transcriptionText`**, not its timed-word blob. That keeps the window at one string column per row rather than a JSON decode per row, and `LexiconInsightsEngine.crutchCounts(in:)` applies the same longest-first phrase consumption as `sessionHits` so the two agree on what counts.

Rates, not raw counts. Six uses in a three-minute take is not worse than four in forty seconds, and a row that said so would be lying. A habit reads as `less than usual` / `more than usual` outside a ±25% band; inside it nothing renders, because "about usual" on every row is noise. Two things deliberately produce no pill: fewer than two earlier takes long enough to rate (`baselineMinimumWords`), and a word with no prior use at all — "more than usual" against a usual of zero invites the fair reply that there is no usual.

The card's denominator is Whisper's word count while the baseline counts tokenizer words. The few percent of drift between them sits far inside the 25% band, so it cannot flip a verdict.

### Saying it out loud

`WordSwapMoment.practiceLine` renders the rewrite as plain text (ellipses dropped — they mark where the quote was cut, and nobody says them aloud) and the card's **Say it** button hands it to `ReadAloudSelectionView(initialPracticeText:)`, which opens a scored session on an ephemeral `ReadAloudPassage.custom(from:)`. That is the loop the feature was missing: the swap stops being a sentence the user reads once and becomes a rep with word-level accuracy scoring.

Lines under four words or twelve characters offer no button — "we shipped" is a fragment, not a rep — and advice-only options have no line at all. Practising counts as a next step, so it calls `markActivatedIfFirstResult()` like the other practice routes.

## Repeat takes

`PersonalAverage.PreviousTake` finds the last attempt at the same prompt or story (`storyId ?? prompt?.id`, matching how relevance picks its source text) inside a `repeatScanLimit` tail, and `TakeComparisonCard` renders it directly under the hero.

This is the one surface that answers "did the coaching work". The scan filters on the relationship *before* unwrapping `analysis`, so the extra rows cost a fault each rather than a blob decode each. `NextStepCard` passes the full recording into the required repeat route, preserving prompt or Story identity and target duration so a practice-again lands back here with a comparison.

Deltas inside ±3 are reported as noise, not progress — same threshold as `CoachPlan.Trend`.

`next_action` includes `RecordingDetailSource` (`post_session`, `history`,
`story`, `learn`) so the result-to-action funnel can be compared by entry
point. On the first analyzed session, taking a next step, accepting a coach
action, repeating, or completing a share logs `activated` once. Onboarding's
“See my full breakdown” logs the same event at its own forward action;
analysis completion alone remains `analysis_complete`, not activation.

## Cross-links

[speech-pipeline.md](./speech-pipeline.md) · `/SPEECH.md` · [monetization.md](./monetization.md) · [analytics-review.md](./analytics-review.md) · [achievements-goals.md](./achievements-goals.md) · `/docs/AGENT_GOTCHAS.md`
