# Practice tools — warm-ups, drills, confidence, read-aloud

## Purpose

Prep and targeted practice surfaces, optionally linked to a Story from Library send-to. Each tool has a single catalog entry in `PracticeToolKind` (title, outcome, best-for, icon, color) so Today, Library, and sheet headers never disagree about what the tool is for.

## Catalog

| Role | Path |
|------|------|
| **Shared outcome axis** | `SpeakUp/Models/PracticeFocus.swift` — 8 cases, every catalog maps onto it |
| Shared copy / identity | `SpeakUp/Models/PracticeToolKind.swift` — adds `format`, `focuses`, `itemCount(for:)` |
| Outcome browser | `SpeakUp/Views/Practice/PracticeFocusView.swift` — `PracticeImproveEntryRow`, `PracticeImproveListView`, `PracticeFocusRow`, `PracticeFocusDetailView`, `PracticeToolRoute`, `PracticeImproveRoute` |
| Page skeleton | `SpeakUp/Views/Components/ToolPage.swift` — `ToolPage`, `ToolPageAction`, `ToolPresentation`, `FocusSection`, `SourceStoryBanner` |
| Item row | `SpeakUp/Views/Components/PracticeItemRow.swift` |
| Shared tile | `SpeakUp/Views/Components/ToolTile.swift` — `ToolTileLabel` (Today strip + History Review grid), `ToolCategoryCard` (Library Tools grid) |
| Review catalog | `SpeakUp/Models/ReviewToolKind.swift` — Compare / Listen back / Goals / Journal |
| Screen awake | `SpeakUp/Extensions/View+KeepsScreenAwake.swift` — `keepsScreenAwake(_:)`, on every runner |

## Warm-ups

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/WarmUp/` — list, exercise, `BreathingAnimationView` |
| VM | `WarmUpViewModel` |
| Model / data | `WarmUpExercise.swift`, `DefaultWarmUps.swift` |

Categories: breathing / tongue twisters / vocal / articulation. The page
**groups by `WarmUpCategory.focus`**, not by the category — the category is the
row's tag. Covered focuses: steady nerves, clarity, presence.

**The runner** (`WarmUpExerciseView`) opens on a ready screen — what the exercise is for, its length, rounds (breathing), one **Begin** — rather than mid-step under a clock that is not running. Breathing counts in for `WarmUpViewModel.leadInSeconds` before the first step ("Get ready"; the skip control reads "Start now"). While it runs, the orb is the timer: a ring around it draws the step's elapsed share, the count sits inside, and tapping the orb pauses or resumes. Under it: a short phase word (Breathe in / Hold / Breathe out) and the step's full label on as many lines as it needs (it used to truncate to one line), then "Next: …". Progress is rounds for breathing ("Round 2 of 3") and step segments for the rest. The orb animates each step toward `BreathingAnimationView.targets(for:)` — full after an inhale, empty after an exhale, and short of full when an inhale is followed by another, so the physiological sigh's second sniff has somewhere to go. Its phase clock restarts on the step index; it used to restart only when the kind of step changed, which froze the orb for the second sniff. Restart re-runs from the count-in; Go again returns to the ready screen.

Evidence-led additions: **Physiological Sigh** (`cyclic_sighing` — double inhale,
long exhale; the exhale-focused breathwork that beat mindfulness meditation on
mood and respiratory rate in Balban et al., *Cell Reports Medicine* 2023) and
**Hum Into Speech** (`hum_into_speech` — the resonant-voice bridge from hum to
words, so the warmed-up tone is the one you speak with). Every breathing seed
encodes exactly three rounds (the rounds picker rebuilds from the first third)
and every seed's `durationSeconds` equals its steps' sum; both are pinned in
`SpeakUpTests/PracticeToolProgressTests.swift`.

## Drills

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Drills/` — selection, session, result |
| VM | `DrillViewModel` |
| Model | `DrillMode.swift` — `outcome` + duration `description`, `durationLadder`, `coachingCue`, `AppColors` identity tones |
| Memory | `SpeakUp/Models/DrillProgress.swift` — `DrillRecord` (best / last / runs / level, pure `folding`), `DrillProgressStore` (one `UserDefaults` JSON blob) |
| Prompts | `SpeakUp/Data/DefaultDrillPrompts.swift` — familiar topics for the habit drills, harder ones for the thinking drills |

Modes: filler elimination / pace control / pause practice / impromptu sprint (PREP cues) / vocal variety / emphasis / Q&A sprint. Grouped by `DrillMode.focus`; `initialFocus` arrives from the outcome browser.

- **Every drill has something to say.** Filler Elimination, Pace Control and Pause Practice used to open on a bare clock; they now get a low-planning familiar topic (fillers cluster where a speaker is still deciding what to say) plus a `coachingCue`. The topic is picked at selection so the prep countdown shows it and Try again keeps it. **Opened from a Story** ("Drilling from …"), the four topic drills (filler, pace, pause, impromptu) take the story as their topic instead; Vocal Variety, Emphasis and Q&A keep their own line or question. The banner used to be the only thing the story changed.
- **The prep countdown names the round** (`Filler Elimination · 45s`) - the ladder changes it run to run. The Drills card's duration (`PracticeToolKind.format`) is derived from every `durationLadder` (`15s-2 min`); it said "15-60s" while Pace Control climbs to two minutes.
- **Drills remember.** `DrillViewModel.publishResult` folds each run into `DrillProgressStore`; rows show `Best N` (and `Level x of y` on a laddered drill), and the result screen calls out `DrillResult.milestone` — a new personal best, or a longer round unlocked.
- **Timed drills climb a ladder** (`durationLadder`): Filler Elimination 15 → 30 → 45 → 60 s, Impromptu 30 → 45 → 60 → 90, Pause Practice 45 → 60 → 90, Q&A 45 → 60 → 90, Pace Control 60 → 90 → 120. Vocal Variety and Emphasis work one fixed line, which a longer clock does not make harder, so they keep one rung. A rung opens on a passed run that went the full round **at the highest rung already open** (`DrillRecord.folding(ranLevel:)`); repeating a shorter round never opens the one after the round you have not run. The competing response from habit-reversal training ("close your lips and pause instead") is the in-session cue, and a result with fillers names which ones (from `liveFillerWordCounts`).
- **Longer is a choice, not a surprise.** A cleared round's result offers **Go Ns** (the next rung, `DrillResult.longerRoundSeconds`) and **Repeat Ns** (`DrillResult.level`); a miss offers Try again at the same length. The ladder used to climb behind Try again, so the button that said "again" quietly ran a longer round, and only Filler Elimination had a ladder at all. `DrillViewModel.startDrill(mode:level:)` runs a chosen rung; nil runs the highest one open, which is what the list row shows.
- **Pace Control shows pace over the last 10 s** (`rollingWPM`, `paceWindowSeconds`) against the user's own target ± `paceBand`, with which way to move. The score is 60 % closeness of the average to target plus 40 % share of seconds spent inside the band — holding a pace is the skill, and a take swinging 110 ↔ 190 can still average 150.

`CoachDimension.vocalVariety` → `vocalVariety` drill; `delivery` → `emphasis`. Impromptu and Q&A show timed structure beats (PREP / CLEAR-lite). Vocal Variety scores post-stop via `PitchAnalysisService` on the discarded take.

## Confidence (Calm)

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Confidence/` — tools list, exercise |
| Model / data | `ConfidenceExercise.swift`, `DefaultConfidenceExercises.swift` |

Kinds: calming / visualization / progressive / affirmation — displayed under
outcome names ("Settle the body", "Rehearse it going well", "Face it in steps",
"Quiet the inner critic"). Grouped by `ConfidenceCategory.focus`, which covers
steady nerves and mindset. Sheet title is **Calm** (matches Today / Library naming).

- **No generic affirmations.** `power_statements` keeps its id (lesson `w4_l1_a2` launches it) but is now **Reframe the Nerves** — reappraising arousal as excitement, the version of self-talk that improved speeches (Brooks 2014). Repeating positive self-statements made people with low self-esteem feel worse (Wood et al. 2009). **Coach Yourself by Name** (`self_distanced_talk`) is self-distanced talk (Kross et al. 2014). Lessons launch exercises by id; `everyLessonExerciseStillExists` pins that.
- The runner pages like cards: swipe the step card left for the next step and right for the previous one (Next / Back stay), with the same segmented step progress as the warm-up runner.
- **Guided mode** ("Guide me" in the runner) reads each step aloud through `PronunciationService.prepareForGuidance()` (spoken-audio playback, heard with the ring switch off), holds for `ConfidenceExercise.guidedHoldSeconds`, and advances. Grounding and visualization start "close your eyes"; the runner used to make you open them for every step.

## Invariants

1. Presented as **sheets** from `ContentView` (Today tiles), Today's focus card, and `RecordingDetailView` next-steps (drills / warm-ups / read-aloud — Calm has no next-step route; there is no subscore that means "nervous", so do not invent one without product intent); **pushed** from the Library Tools tab (`ToolPresentation.pushed`, via `navigationDestination`). Selection views take `presentation:` and hand it to `ToolPage`, which owns what it changes: sheets get an inner `NavigationStack` + ✕; pushed keeps system Back and the inline title. Never a separate tab.
    - Library used to swap the tool in place (`ToolPresentation.embedded`) behind a hand-rolled "All tools" pill and a `withAnimation` slide. It was the only place in the app where opening something did not push, it read as a different kind of motion from a story or Compare one section over, and it nested a tool's `LazyVStack` inside the hub's. That case and its `embeddedBody` are **deleted**, so `ToolPresentation` is `.sheet` or `.pushed` and there is no third way to open a tool. The unused `ToolPage(tool:isPushed:)` convenience init went with it.
2. `sourceStory` banners when routed from Stories; keep story id plumbing intact.
3. Tool identity colors: `AppColors.toolWarmUp` / `toolDrill` / `toolReadAloud` / `toolCalm` — one per `PracticeToolKind` case that has a colour, shared with the Today prep strip via `PracticeToolKind.color`. Sub-category and drill-mode colors draw from the muted jewel set (`categoryBrandBright/Copper/Plum/Sage/Indigo/Amber`) — never system `.orange/.purple/.blue/.red`.
4. Seed arrays live under `Data/`.
5. **One page skeleton, not four.** All four tool pages are a `ToolPage`: it owns the background, the scroll, the column padding, the nav title (from `PracticeToolKind.title`, so "Quick Drills" can't drift from `Drills` again), the sheet ✕, and the single secondary header line (`PracticeToolKind.outcome`). Pushed and sheet presentations both get that chrome; only the ✕ differs. A page supplies its items and nothing else — that is what keeps a fifth dialect from appearing. `sourceStory` uses the shared `SourceStoryBanner`. `ToolPage(focus:)` owns the `ScrollViewReader` that reveals an arrival group (invariant 8).
6. **One line of chrome, not three.** The nav bar already names the page, so an eyebrow label and a purpose card on top of it were the same sentence three times; `ToolPurposeBanner` was deleted, not relocated. `bestFor` is a browsing aid and stays in the Library rows only.
7. Library → Tools is a **practice 2×2**, one **`PracticeImproveEntryRow`**, and a **Review 2×2** (same card recipe, copy from `ReviewToolKind`). It used to lead with the outcome axis in full — a header, a caption and one `PracticeFocusRow` per `PracticeToolKind.coveredFocuses` — above the same grid, which made the landing the longest screen in the app and offered two doors to the same forty exercises. The axis is not gone: every tool page groups by it, and `PracticeImproveListView` (pushed by `PracticeImproveRoute`) still holds the eight rows for the entry that starts from a problem rather than a format. **Search is the exception** — a query for "fillers" renders the matching `PracticeFocusRow`s inline, because a search result should be the thing, not a row promising to contain it. A practice card pushes its tool; do not re-create the forward/back edges by hand — the navigation stack owns that motion now. Outcome and best-for stay on VoiceOver / the pushed page's header; the grid must stay scannable like Prompts categories.
8. **Map, never mask.** All four tool pages show every group, always. Each section is the shared `FocusSection` — title + count + the focus's `promise`, then its rows on **one `GlassRowGroup`** (hairlines inset to the row text via `PracticeItemRow.dividerInset`) — so one page's grouping cannot drift from the others'. **There are no filter controls on a tool page.** Each one used to carry a `FocusFilterBar` sitting directly on top of the section headings, which is the same eight words twice: a control, and the thing the control acted on. Seven drills, a dozen warm-ups and two Calm groups are a scroll, not a search problem, and the pills cost a full-width row on every page to save nobody anything. Read Aloud was the extreme case and carried **two** bars plus a "12 of 20 passages" caption explaining what they had done. `FocusFilterBar`, `ToolFilterBar` and `FilterPill` are **deleted** — do not reintroduce a pill row on a tool page; if a catalog ever grows past what scrolling can serve, add search, not filters. Arriving from the outcome browser now **scrolls** to the group (`ToolPage(focus:)` → `proxy.scrollTo(focus)`, anchored by `FocusSection.id(focus)`) instead of hiding the other seven: a page that opens pre-filtered has thrown away material the reader never asked to lose. Nothing filters, so the "Show All" empty states are gone too — they were unreachable.
9. Runner controls use `GlassButton` (primary = forward/Done, secondary = Back) and `Font.displayNumeral` for the hero countdown — no hand-rolled white capsules. The warm-up transport trio (restart/play/skip) is round-icon (`glassCircle()`), exempt from the capsule rule; the orb itself is also a pause control. Runners confirm before discarding an active session (warm-up ✕ mid-run asks, same as drills; Calm asks once past the first step or while guiding). Every runner ✕ is the same 44pt `glassCircle()` - the drill's used to be a material disc.
10. `ConfidenceCategory.color` draws from the jewel set; exercise steps read via `step(safelyAt:)`, never a raw subscript. The step card's tint is that colour at **0.10** with an `IconChip` glyph - `GlassCard` applies a tint as given, and the full-strength colour made it a solid slab. Steps slide under `AppMotion.slide` and cross-fade under Reduce Motion; "Guide me" keeps one label and exposes `.isSelected`. Step cards re-`.id` on the index so swaps animate; finishing fires `Haptics.success()` + the `.exhale` chirp, distinct from step ticks.
11. **Explain once, at the surface where the choice is made.** The Library Tools tab renders a compact **category grid**, then pushes the chosen practice tool (`ToolPresentation.pushed`). Review tools open sheets / pushes via `ContentView` callbacks (same doors as History → Progress). Searchable across title/outcome/best-for, empty state on no match. Today's prep strip and History's Review grid both use the compact `ToolTileLabel`; Library uses the denser `ToolCategoryCard`. Two densities, shared catalogs (`PracticeToolKind` / `ReviewToolKind`) — do not hand-roll a third tile dialect.
12. **Every item is a `PracticeItemRow`** — dial, title, subtitle, optional tag (`StatusPill` in the row's tint), play affordance. It is a **row, not a card**: no plate of its own, `RowPressStyle` on press, always inside its `FocusSection`'s `GlassRowGroup` (a column of forty separate cards was the old shape). The dial's cost label scales with Dynamic Type (`@ScaledMetric`, 8pt base) and shrinks back rather than leave the ring. The play affordance is **neutral** (a painted white-on-glass circle, the on-card recipe of `GlassButton.secondary`): the row's identity colour already sits in the dial and the chip, and a filled play disc in that colour made the affordance the loudest thing on every row. Drills used to be a 2x2 of 176pt tiles and Read Aloud a bespoke `PassageCard`; four items each stacking an icon, title, outcome, live-feedback label and duration (two of them tinted) is five things competing inside one card, and it made Drills the odd page out. Cost is split by size: the **dial** takes one short unit that fits its 8pt label (`45s`, `3m`, `2m`), the **chip** takes the qualifier that doesn't — Calm's step count (it used to be crammed into the dial as "3m · 4 steps"), a drill's `liveFeedback`, a passage's difficulty + word count. Read Aloud keeps its "N of M passages" caption while filters are active.
13. **Timers tell the truth.** Step/duration clocks finish inside the tick that reaches zero (a "48s" box-breathing round lasts 48s, and 4-7-8 runs 4-7-8). Drill countdowns likewise; the drill timer also stops the session early with an "ended early: recognition stopped" note if transcription dies mid-drill. Drill prep uses one `fullScreenCover` that owns countdown → session — never an overlay clipped to the Library tools list (that rendered the dial as a card-shaped box).
14. **Silence is not a score.** A drill whose mic or speech recognition can't start sets `errorMessage` and exits via alert — it never awards a clean-run result for audio that was never heard. A silent take scores 0 too: Filler Elimination needs `max(5, duration / 3)` words (silence used to pass as "Clean run" and would now climb the ladder), Impromptu and Q&A score 0 below their word minimums instead of the 50-point floor, and Pause Practice needs voice in at least a quarter of the metering frames between markers (its markers score silence, so a silent take used to hit all three). Read Aloud carries the same doctrine as result notices (see [read-aloud.md](./read-aloud.md)).
14a. `DrillResultView` owns the result haptic: the ring sweeps and the number counts up with `Haptics.playCountUp`, then success (passed) or light (not). `DrillViewModel.finishDrill` fires none - both firing buzzed twice for one result. That includes the silent-take path of the pitch-scored drill. A miss reads **"Not yet"** (it used to say "Try again" directly above a Try again button); a milestone is a success `StatusPill`.
14b. **Pitch scoring is visible.** While `isAnalyzingPitch`, the record button's slot holds a `VoiceLoader` and "Scoring pitch…" - it used to empty, leaving a frozen clock.
15. Pace-control drills score against `DrillViewModel.targetWPM` (from `UserSettings.resolvedTargetWPM`), not a fixed 130–170 band — and so does the live display, which used to print "target 130-170" whatever the setting said. Result copy names that target and the share of time on pace.
16. Breathing circle scale is computed from accumulated phase time (`TimelineView`, paused when paused) — never `withAnimation`, which cannot be cancelled and desyncs from the clock.
17. **One axis: `PracticeFocus`.** The four tools are *formats* — how long
    they take and whether the mic opens — and `PracticeToolKind.format` is the
    line that says so. What they *improve* is `PracticeFocus`, and several of
    them improve the same things on purpose. Every tool page groups and filters
    by focus; the old per-tool taxonomies (Breathing / Tongue Twisters / Vocal /
    Articulation, Calming / Visualization / Progressive / Affirmation, News /
    Literature / Technical) named mechanisms, so twelve labels were on screen
    and none said what changed. They survive as row tags. Do **not** add a
    second grouping axis, and do not give a catalog a private outcome enum —
    extend `PracticeFocus`.
18. **Focus listings are derived, never written down.** `itemCount(for:)`
    counts the seed arrays and everything else is built on it — `focuses`,
    `tools(for:)`, `coveredFocuses`, and each page's `availableFocuses`, which
    simply forward to `PracticeToolKind.<tool>.focuses`. A listed-but-empty
    tool is therefore not expressible, which is why the Improve list and the
    focus page have no empty states. Do not reintroduce a second derivation
    (one asking a category enum which focuses exist would list a focus whose
    only category ships nothing). `SpeakUpTests/PracticeFocusTests.swift` pins
    the content side: every `PracticeFocus` case must ship material somewhere,
    and each tool's per-focus counts must sum to its whole catalog.
19. **`PracticeFocus` is `nonisolated`, but `color` is `@MainActor`.** It has to
    be nonisolated so `allCases` stays reachable from `ReadAloudCategory`, which
    is nonisolated too (gotcha §1); `AppColors` is default-isolated, so only the
    colour member is pinned. Keep that split when adding members.
20. **A tool page's nav bar can hold one action** (`ToolPageAction`, rendered
    `.topBarTrailing` by `ToolPage`). Read Aloud uses it for "Add your own
    passage". An "add" affordance belongs there or on a rail — never as a
    full-width card above the catalog the page exists to show.
21. **A runner is presented on its subject, never on a flag.** `DrillSelectionView` hands the `DrillMode` to `fullScreenCover(item:)` and `DrillFlowView` owns the countdown → session phase as its own state. It used to be three `@State` values — a presentation flag, the mode the cover unwrapped, and the phase — with an `onDismiss` clearing the last two. SwiftUI runs `onDismiss` *after* the dismissal animation, so starting a second drill while the first was animating out opened the cover onto a mode that had just been nilled: blank screen, immediate self-dismiss, works on the second tap. `ConfidenceToolsView` and `ReadAloudSelectionView` present the same way. Gotcha §27.
    - **An `initialMode` launch is one-shot and hands back.** `.task` runs again whenever the page reappears, and a full-screen cover closing is a reappearance, so `DrillSelectionView` guards the launch with `didLaunchInitialMode` (Read Aloud's `didStartInitialPractice` is the same guard). When a drill opened that way closes, the sheet dismisses too: a result's next step or Today's focus card returns to its caller, not to the drill catalog.
22. **Countdown Cancel is immediate.** `CountdownOverlayView` ticks via a cancellable `.task` loop and sets `hasCompleted` on Cancel / Start now so a stray tick cannot complete a dismissed countdown. Own the hit surface (`.contentShape` + full-screen frame) — a parent scroll used to eat the first taps.
23. **Every runner keeps the screen awake while it runs** (`keepsScreenAwake`: Read Aloud while listening, drills while active, warm-ups while running, Calm until complete). They are all minutes of speaking or breathing without a touch; Auto-Lock used to dim and lock the phone mid-exercise, and in Read Aloud it took the microphone with it.
24. **Live counts add across utterances.** `LiveTranscriptionService.liveWordCount` / `liveFillerCount` are committed-plus-live, banking each utterance when a request ends or the recognizer restarts inside one (`RecognitionContinuity`). They used to be `max(total, this request)`, so every word and filler after the first pause went uncounted — pace drills scored slow and Filler Elimination could pass a run with fillers in it. A final that restates the whole request moves that request's committed counts back into the live utterance (`absorbRequestIntoUtterance`) so nothing counts twice.
25. **The drill meter redraws the rings, not the screen.** `DrillViewModel.audioLevel` updates every 100 ms; only the private `DrillWaveform` subview reads it. Read from `DrillSessionView.bottomControls` it re-ran the whole drill body ten times a second. The same tick keeps `levelSamples` and the peak-over-median `liveEnergySwing` for Vocal Variety and Emphasis only — the two drills that show or score on it — and writes the swing only when the whole-dB readout or its shown/hidden state would change.

## Read-Aloud

Catalog passages plus **Practice anything** (type a word / sentence / paragraph, hear TTS, then score with the same alignment engine). See [read-aloud.md](./read-aloud.md).

## Outcome browser

Library → Tools → a `PracticeFocusRow` pushes `PracticeFocusDetailView`, which
lists every tool with material for that focus and its item count, then pushes a
`PracticeToolRoute` into that tool already narrowed (`initialFocus:`). The page
is titled with `focus.title` and opens on the promise line only, like a tool
page. Every pushing row here - Improve list, focus page, the landing's Improve
+ Words entry pair, search results - is a `PracticeLinkRowLabel` inside one
`GlassRowGroup`, pressed with `RowPressStyle`; none is a card of its own.

**Search reaches the exercises.** `PracticeToolKind.items(matching:)` matches
item names and their category names across the four catalogs ("box
breathing", "impromptu", "tongue twister" used to return "No tools match"); a
hit pushes its tool page scrolled to the item's group. The empty state offers
**Clear search**. This is
the screen that answers "aren't warm-ups drills too?" — under *Be understood*
you see tongue twisters, articulation warm-ups and the precision read-aloud
passages side by side, distinguished by `format` rather than filed apart.

Routing is value-based (`.navigationDestination(for:)`) so a focus page can
push a tool page on top of itself; Library's practice cards use
`NavigationLink(value:)` + `ToolCategoryCardLabel` for the same reason.
