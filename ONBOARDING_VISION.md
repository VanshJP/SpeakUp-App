# Onboarding Vision — Big Talk

Source-of-truth for why onboarding is shaped the way it is. Read this before
changing anything under `Views/Onboarding/` or the onboarding paths in
`ContentView`. The full research behind it (Mobbin case studies, UX audit of
the old flow, screen-by-screen rationale) lives in `ONBOARDING_REDESIGN.md`;
this file is the distilled contract. Last updated: 2026-08-05.

## The one-sentence vision

A first-time user should reach their first completed baseline recording
feeling guided, confident, and excited — never once wondering
"what am I supposed to do right now?"

## The activation moment

> A new user is **activated** when, in their first session, they
> (1) complete a baseline recording ≥ 30 seconds,
> (2) see the reveal screen, and
> (3) take one forward action from it.

Every onboarding screen exists only to reach that moment with the least
cognitive effort. A screen that doesn't build capability (mic works), context
(why we're recording), or courage (what to say) does not belong in the flow.

## The constitution: real user feedback

This feedback drove the redesign. Any proposed change should be tested
against it — these are the failure modes we must never reintroduce:

- "I'm overwhelmed."
- "The prompt disappeared immediately."
- "I got put into a lesson but had no idea what I was supposed to say."
- "I didn't know if there was a script."
- "The baseline recording should be the first guided experience."
- "I like apps that guide me through their flows simply."
- "Don't make it feel like a chore."
- "Too much reading makes people turn their brains off."

The old flow's fatal flaw, for the record: nine setup screens, then an
auto-started, prompt-less, 60-second free-practice recorder
(`recordingPrompt = nil` → countdown → live mic). The entire point of the
flow was its only unguided moment. The baseline now lives *inside*
onboarding as its climax, and that handoff no longer exists.

## Invariants (do not regress)

These are implemented and load-bearing. Treat them as tests that happen to
be written in prose:

1. **The baseline is the destination, not the doorstep.** The flow ends with
   a score reveal, never with a handoff into a generic recorder.
2. **The user presses every record button.** No auto-started recording,
   ever. The 3-2-1 countdown renders *inside* the record button so the
   screen never changes under the user.
3. **Nothing the user needs disappears.** The prompt is the pinned page
   title for the entire take.
4. **Coach voice, ~25-word cap.** Every screen is something a human coach
   would say. No feature tours, no bullet walls, no terms-and-conditions
   register. Teach through interaction, not paragraphs.
5. **One question, one screen, one tap.** Goal and level advance on tap
   after a payoff line ("Got it. Expect interview-style questions.") —
   every input gets a visible consequence within one screen.
6. **The first number is never a grade.** Copy says "starting line".
   Zero-score takes (silence/gibberish gate) are never shown as a number —
   the user is coached into a retake and the row is deleted. Scores < 40
   get the supportive reveal without the hero number.
7. **Escape hatches at arm's length, shame-free.** Start over is always
   visible mid-take; swap-prompt is one tap away at the moment of panic;
   retakes are unlimited and stated as such *before* the first take.
8. **Effort and permissions only after value.** Calibration, the AI model
   download, and reminders stay out of the first run — they belong to
   `FirstRecordingSetupSheet`, which fires on Today *after* the first score.
   The layout tour (`AppTourView.swift`) follows the same rule and the same
   gate: it runs once, on Today, only after a recording exists. The two are
   strictly sequential — `TodayView.checkFirstRunSurfaces()` shows the sheet
   first and starts the tour from its `onDismiss`, because the tour's
   spotlight is a cutout in a dim layer that a presented sheet would cover.
9. **Progress reads as "enough", not "deadline".** The take clock counts
   up; a baseline take is 30 seconds minimum — the stop button unlocks at
   the same moment the "Enough for a baseline ✓" tick flips, so the floor
   and the goal are one number; nothing forces 60. **30 is the only
   duration the copy ever quotes** — briefing, take screen, and
   announcements all say 30. No em dashes anywhere in onboarding copy.
10. **Waiting is a stage, never a spinner.** The analyzing screen shows the
    real pipeline as ticking stages; the final stage is gated on actual
    analysis completion.
11. **Accessibility parity.** VoiceOver replaces auto-advance with an
    explicit Continue; Reduce Motion collapses the briefing cascade and the
    reveal animation; announcements fire at meaningful moments only
    (record start, 30s, stop) — never per-second.
12. **Interruptions are blameless.** Backgrounding mid-take discards the
    take with "We saved nothing — clean slate…". A resume after force-quit
    lands on the briefing, never cold on the live recorder.

## The flow as built

```
welcome → name → goal → level → mic (sound check) → baselineBriefing → baseline
                                                      ├─ ready / countdown / recording / saving  (OnboardingViewModel.BaselinePhase)
                                                      ├─ analyzing (staged, gated on real analysis)
                                                      └─ reveal → onComplete(result)
```

- Steps: `OnboardingStep` in `ViewModels/OnboardingViewModel.swift`
  (`firstRunSteps` is the walk order; heroes hide ticks/skip).
- Screens: `Views/Onboarding/OnboardingIntroSteps.swift` (cover, name, goal,
  level), `OnboardingSetupSteps.swift` (sound check + deferred
  calibrate/AI/reminder steps), `OnboardingBaselineSteps.swift` (briefing,
  guided recorder, analyzing, reveal).
- Persistence/processing: the baseline saves a real `Recording` row
  (title "My baseline") and runs through `RecordingProcessingCoordinator` —
  no special-cased pipeline.
- The take screen is the app's recorder, not a lookalike: it reuses
  `CircularWaveformView` + `RecordButton` in one control that holds its
  position across every phase (record → countdown → stop → saving), and the
  canvas switches to `AppBackground(.recording)` while audio is live.
- Completion routing (tab + selected recording) is set *before* the cover
  dismisses; achievements and other async work run after, so the last tap of
  onboarding lands on a settled screen rather than a stutter.
- Completion: `OnboardingResult.baselineRecordingID` +
  `reviewBaselineOnFinish` → `ContentView` routes "See my full breakdown"
  through the History → `RecordingDetailView` path, runs the achievements
  check, and keeps `FirstRecordingSetupSheet` eligible (the baseline itself
  doesn't count as "already knows how to record").

## The layout tour (post-first-score)

Onboarding answers "what do I say"; the tour answers "where is everything".
It is deliberately *not* part of the first run — a map is meaningless before
the user has been anywhere, and it would have pushed the baseline further
from launch.

- Seven stops: three on Today (prompt + start buttons, stats rings, quick
  tools), one each on Library, History, Learn, ending on Settings →
  Session Defaults, so the last thing the user learns is where to change
  their recording preset.
- The tour drives `selectedTab` itself and draws over the tab bar, which is
  why `AppTourModel` is owned by `ContentView` and not a tab root.
- Views register spotlight targets with `.tourAnchor(_:)`. An anchor that is
  missing or scrolled mostly out of view degrades to a plain bubble rather
  than dimming the screen around nothing.
- Skip is on every stop, and skipping marks it seen — asking twice is
  nagging. `UserSettings.hasSeenAppTour` is the once-ever gate; finishing
  returns the user to Today rather than parking them in Settings.
- Copy follows the same coach voice and ~25-word cap as the flow.

## Deliberately cut — do not re-add

- **"How It Works" / "What's Inside" explainer pages.** Feature inventories
  serve the builder's pride; the product teaches its own inventory.
- **The vocab editing step.** Homework mid-flow. Seeds still apply silently
  from the level pick (`vocabSeeds(for:)`); Settings → Word Bank is the editor.
- **The "Ready" recap + start-toggle.** The flow needs neither a receipt nor
  a decision at the finish line; the baseline is the finish line.
- **The post-onboarding auto-countdown** (`launchFirstRecording`). This was
  the fatal handoff. It is gone from `ContentView`; do not resurrect it.
- **Script mode ("Read a script instead").** Cut 2026-08-05. Big Talk's
  muscle is thinking on the spot and organizing your thoughts on the spot —
  a read-aloud baseline trains the wrong thing and doesn't compare honestly
  against the spontaneous sessions that follow it. The briefing now says
  this out loud ("No script. The muscle we're building is thinking on the
  spot."), the starter chips remain the anti-freeze aid, and Read-Aloud
  practice lives in the Library for users who want read speech.

## Known ceilings / deferred (fine to build, in this order)

1. **Today hero card** for users who skipped the baseline ("Your starting
   line is waiting…") — the funnel re-entry. Until it exists, their first
   normal recording serves as the implicit comparison point.
2. **"You said N words"** on the analyzing screen — blocked on the pipeline
   persisting transcript before analysis (today both land in one save).

## Measurement

- Funnel: `AnalyticsService` `onboardingStep(step, action:)` with stable
  names (`welcome, name, goal, level, mic, baseline_briefing, baseline`) and
  actions `continue / skip / back / complete`, plus baseline-internal
  actions `take_saved / retry / swap_prompt / reveal`.
- `practiceStarted(useCase: "baseline")` on record start.
- `.activated` already logs once in `RecordingProcessingCoordinator` when
  the first analysis completes — time-to-value is measured where the work
  finishes, not where the UI notices.
- Watch: % of first takes ≥ 30s, retry distribution, swap-prompt share
  (if high, the default prompt is too scary — fix the prompt), % tapping
  "See my full breakdown", second session within 48h.

## Litmus test for any future change

Before shipping a change to onboarding, ask:

1. Does it move the user closer to the activation moment, or is it setup?
2. Would a coach say this sentence in the first five minutes?
3. Does anything the user needs disappear while a mic is live?
4. Did the user press the button, or did we?
5. Could a nervous first-timer end this screen feeling judged?

If any answer is wrong, the change contradicts this document — either fix
the change or update this document deliberately, in the same PR.
