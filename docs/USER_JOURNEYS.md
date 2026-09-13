# User journeys — product audit

Last audited: 2026-09-13

## Scope and method

This audit follows every production entry point in `ContentView`, then checks
the destination views, completion states, recovery states, and onward actions.
It covers onboarding, Today, Library, recording, results, History, Learn,
Stories, practice tools, reminders, widgets, sharing, and Settings.

Evidence is source-level because the Linux agent host cannot run Xcode or an
iOS simulator. Visual behavior still needs device or CI validation.

Production references used for flow comparison:

- [Duolingo onboarding](https://mobbin.com/flows/ac9d2f58-868d-4fd3-a79c-9655ce6b1522):
  explicit progress, one choice per screen, daily goal, recommended start.
- [Duolingo first lesson](https://mobbin.com/flows/b736389a-cb5c-4889-8011-a220baf09171):
  value before setup, visible lesson progress, clear completion payoff.
- [Speak home](https://mobbin.com/flows/713714a7-149b-4df4-b09e-446567613c3a):
  one current lesson, separate free-practice and drill lanes.
- [Babbel home](https://mobbin.com/flows/c6af6ba1-bdf6-4f09-8615-966afabe1c30):
  one dominant next action backed by a visible learning plan.
- [Duolingo speaking lesson](https://mobbin.com/flows/eeed3ac8-ec59-44f8-9758-a08ada0a1063):
  explicit record action, persistent task context, completion summary.
- [Speak Q&A lesson](https://mobbin.com/flows/eed0e043-6c35-48a6-9a1d-b961328770b7):
  staged speaking prompts, visible progress, immediate continuation.

Big Talk should copy the interaction principles, not the gamification. Its
advantage is private, open-ended speech with actionable coaching.

## North-star outcomes

1. **Activation:** complete a first take, see the result, then choose a forward
   action. Analysis completion alone means value is ready; it does not prove
   the user engaged with the value.
2. **Practice outcome:** each scored take ends with one specific adjustment and
   a route to apply it.
3. **Retention:** the next visit makes the useful action obvious without loss
   warnings, forced setup, or a competing objective.

## Flow ownership

| Surface | Primary job | Success event | Must not become |
|---|---|---|---|
| Onboarding | Build enough confidence and context for a guided baseline | First result reveal → full breakdown | Feature tour or setup checklist |
| Today | Start the most relevant practice now | Recording starts | Second curriculum or dashboard-only home |
| Library | Choose subject or tool intentionally | Prompt, Story, or tool opens | Another Today feed |
| Recording detail | Explain result and prescribe one next action | Next action starts | Passive report |
| History / Progress | Find evidence of change over time | Session opens, comparison/review starts | Practice launcher with misleading shortcuts |
| Learn | Provide teacher-led structure | Current activity and lesson complete | Tool catalog |
| Settings | Change behavior and data deliberately | Setting persists | Discovery hub |
| Widgets / links | Re-enter a known job quickly | Correct in-app route opens | Standalone data store |

## User-story audit

| Priority | User story | Primary flow | Verdict |
|---|---|---|---|
| P0 | As a nervous first-time speaker, I want to know exactly what to say and when to record. | Onboarding → guided baseline | **Optimized.** Prompt remains visible, recording is user-started, 30 seconds is enough, and failure/retake paths protect the work. |
| P0 | As a first-time user who skips the baseline, I want an obvious way to return without being dropped into free talk. | Onboarding skip → Today | **Improved in this audit.** Zero-session Today now says “Set your starting line,” labels the first prompt, uses a matching CTA, and hides prompt-less free talk until one take exists. |
| P0 | As a speaker who just received feedback, I want the prescribed next action to work from every result entry point. | Result → drill/warm-up/read-aloud/repeat | **Fixed in this audit.** History, Story, and Learn detail routes now provide a real repeat action instead of rendering a dead primary CTA. |
| P0 | As a Story user, I want “Practice Again” to repeat my Story, not open unrelated free practice. | Story result → repeat | **Fixed in this audit.** Repeat preserves `storyId`; direct Story history routes back to the same Story. |
| P0 | As a returning speaker, I want a single obvious daily action. | Today → prompt → countdown → recording | **Optimized.** Session stays pinned, owns the only primary CTA, and adapts prompt mix to goals and demonstrated weakness. |
| P0 | As a user waiting on on-device analysis, I want confidence that my take is safe and a way to leave. | Recording → analyzing | **Optimized.** Staged status, first-model-download explanation, background processing, Save & close, and retry recovery are present. |
| P1 | As a user with a weak score, I want one concrete fix rather than a wall of metrics. | Result → NextStep / CoachMoment | **Optimized.** Weighted rolling focus selects one area and routes to the owning tool. |
| P1 | As a user repeating a take, I want a fair comparison. | Result → repeat → result | **Improved in this audit.** Subject and original target duration survive the repeat; same-subject comparison already exists. |
| P1 | As a user with a specific topic, I want to find or add it quickly. | Library → Prompts | **Optimized.** Search, filters, single/batch add, wheel, and direct recording route share one section. |
| P1 | As a user rehearsing personal material, I want writing, practice, prep, and progress connected. | Library → Stories → Story detail | **Optimized.** Story-linked warm-up, drill, recording, history, and fidelity scoring remain connected. |
| P1 | As a user working on articulation, I want scripted and custom speech practice. | Library / next step → Read Aloud | **Partially optimized.** Catalog, saved text, one-off text, TTS, dictionary, and alignment scoring share one tool, but results are session-local and do not enter History. |
| P1 | As a user who wants structure, I want the app to remember my next lesson. | Learn → Continue → activity → completion | **Optimized.** Current lesson is dominant, review is nearby, activities carry teaching context, and next lesson stays in place. |
| P1 | As a user checking progress, I want a conclusion before charts. | History → Progress | **Optimized after two analyzed sessions.** Hero verdict precedes trends, scenarios, language, and review tools; thin-data states are explicit. |
| P1 | As a user with no History yet, I want the empty-state action to tell the truth. | History empty → Today | **Fixed in this audit.** CTA now says “Choose Today’s Prompt”; it no longer promises that recording starts immediately. |
| P1 | As a user returning under stress, I want quick preparation without hunting. | Today / Library → Warm-Up, Drills, Calm | **Optimized.** Today recommends one prep tool; Library remains the full catalog; Calm stays user-selected because no score measures nerves. |
| P1 | As a user building a habit, I want encouragement without guilt. | Today streak / reminder / widget | **Optimized.** One optional reminder, calm streak copy, and fingerprint-gated widgets avoid urgency ladders. |
| P1 | As a user who listens to my own voice, I want that uncomfortable but useful action recognized. | Recording detail → first playback | **Fixed in follow-up.** Brave Listener now unlocks only after playback starts successfully and uses the root-observed achievement service, so its celebration is visible. |
| P2 | As a user proud of progress, I want to share safely. | Result / Progress → share | **Optimized.** Scores-only is default, prompt sharing is opt-in, and challenge links close the acquisition loop. |
| P2 | As a privacy-conscious user, I want local control over models, data, and analytics. | Settings → AI / Privacy & Data / diagnostics | **Optimized.** Analytics is local by default and event schema cannot carry audio, transcripts, prompts, exact scores, or recipients. |
| P2 | As an experienced user, I want the home to match my routine. | Today → Edit homepage | **Optimized.** Modules reorder/hide in place, session cannot disappear, and accessibility actions mirror drag controls. |

## Cross-flow findings

### Working as intended

- Today and Learn do not compete: Today starts a rep; Learn supplies a course.
- Library and Today use different density for the same tool catalog, while the
  canonical title/outcome/route stays shared.
- Review tools appear in Library and Progress for discovery, but both routes
  use the same destinations.
- Result coaching and Today focus use the same `CoachPlanService`; they cannot
  prescribe different weak areas from separate algorithms.
- Post-first-score setup and the app tour happen after demonstrated value,
  remain dismissible, and recheck when Today becomes active after onboarding.

### Corrected in this audit

- Result entry points had drifted. `RecordingDetailView` accepted an optional
  prompt-only retry, so Story and Learn could show a no-op primary action and
  History converted Story repeats to free practice.
- Activation measurement fired when analysis finished, before result
  engagement. `activated` now fires once on the onboarding reveal action or a
  forward action from the first result. `analysis_complete` still measures
  pipeline readiness.
- `next_action` could not compare result entry points. It now carries a stable
  source: post-session, History, Story, or Learn.
- The skipped-baseline and empty-History routes used generic or misleading
  copy instead of naming the actual next step.
- Today could perform its only first-run-surface check while onboarding still
  had zero recordings. The active, unobscured Today edge and pull-to-refresh
  now re-run the guarded check.
- `listenBackCount` changed without achievement evaluation and before playback
  success. It now records the listen after `AudioService.play` succeeds and
  checks the shared achievement service.
- Onboarding's welcome promised a minute while its contract and recorder use
  30 seconds. The welcome now names the same duration.
- Read-Aloud documentation claimed SwiftData persistence that does not exist.
  The feature brief now names results as ephemeral until a deliberate storage
  design is implemented.

## Action plan

### P0 — completed

1. Restore repeat-practice continuity across History, Stories, and Learn.
2. Preserve Story subject, target duration, and curriculum framework.
3. Add skipped-baseline re-entry on Today without adding a second hero.
4. Align activation analytics with the product definition.
5. Add source attribution to the result-to-next-action funnel.
6. Make History empty-state and tour copy describe their real actions.
7. Re-trigger post-first-score setup and tour after onboarding/tab return.
8. Unlock and surface Brave Listener after successful first playback.
9. Align onboarding duration copy and Read-Aloud documentation with code truth.

### P1 — next evidence-led work

1. Add actions to scenario-readiness rows; they currently identify the weak
   situation but cannot start matching practice.
2. Surface one or two active goals on Today, where goal data is already loaded
   but currently has no UI.
3. Unify Today rings with History → Progress so both entry points include
   trajectory, scenarios, language insight, and review tools.
4. Add a useful CTA to the zero/one-session Progress state.
5. Route weekly/readiness widgets to Progress instead of dropping every widget
   into generic recording.
6. Design Read-Aloud History persistence, including media ownership and an
   analysis shape, before implementing it.
7. Measure first-result forward-action rate by source and weak area. If one
   source underperforms, inspect that handoff before changing the card.
8. Measure skipped-baseline users reaching their first recording. If the new
   framing does not close the gap, restore the guided baseline itself rather
   than adding more explanation.
9. Add route-contract tests around repeat plans (prompt, Story, free practice,
   duration, framework) after extracting that mapping into a pure type.
10. Validate first-score setup plus seven-step tour on a small phone and at
   accessibility text sizes; shorten only when observed completion or layout
   evidence says it is necessary.

### P2 — later

1. Decide whether widget and deep-link opens need a coarse source dimension on
   `practice_start`; do not add prompt text or campaign detail to behavior logs.
2. Evaluate whether users discover Learn from the tab without enabling the
   optional Today module. Keep Learn off the default home unless evidence shows
   a discovery problem.
3. Review Story deletion behavior for old linked recordings so repeat copy can
   explicitly explain when the original Story no longer exists.
