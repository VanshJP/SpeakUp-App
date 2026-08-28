# Today & Library

## Purpose

**Today** — home: modular blocks (rings, focus, session, prep tools, optional learn), streak, word workout, weekly recap. Users customize which blocks show and in what order (Bevel-style).  
**Library** — unified browser: prompts, stories, tools (warm-ups, drills, read-aloud, calm).

## Key files — Today

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Today/` — `TodayView` (hosts `InteractivePromptCard`, and its own layout edit mode), `SessionWordsRow`, `StoryPromptCard`, `WeeklyRecapCard`, `FriendChallengeCard` |
| Layout | `SpeakUp/Models/TodayHomeModule.swift` — `TodayHomeModule`, `TodayHomeLayout` |
| Tool catalog | `SpeakUp/Models/PracticeToolKind.swift` — shared titles / outcomes / best-for |
| VM | `SpeakUp/ViewModels/TodayViewModel.swift` |
| Services | `WeeklyProgressService`, `VocabChallengeService` |
| Components | `RingStatsView`, `StreakChip`, `ToolTileLabel` |
| Widget writes | `SpeakUp/Services/WidgetDataProvider.swift` |

## Key files — Library

| Role | Path |
|------|------|
| Hub | `SpeakUp/Views/Practice/PracticeHubView.swift` (`PracticeSection`) |
| Prompts | `Views/Prompts/` — all / add / batch CSV |
| CSV | `PromptCSVService`, `Data/DefaultPrompts.swift` |
| Wheel | `Views/PromptWheel/PromptWheelView.swift`, `PromptWheelViewModel` |

## Invariants

1. Fingerprint-gate `WidgetCenter.reloadAllTimelines()` from `TodayViewModel` — never reload unconditionally. Mechanism: `updateWidgetData()` joins a 12-component payload (streak, prompt text/category/id, last score, weekly count/goal/avg/minutes, improvement rate, readiness, last practice date), `WidgetDataProvider.todayPayloadChanged` SHA-256s it and stores the digest under `widgetStateFingerprint` in the App Group. Unchanged → skip **both** the App Group writes and the reload; `loadData` runs on every Today appearance and pull-to-refresh, so without this gate every visit burned a WidgetKit refresh.
2. First-run after onboarding: `FirstRecordingSetupSheet` then `AppTourView` (sequential; tour model on `ContentView`).
3. Library sections: `.prompts` / `.stories` / `.tools`. Recording start callbacks bubble to `ContentView`. The Tools tab is a 2-column tile grid (see [practice-tools.md](./practice-tools.md)) whose tiles **push** the tool as a full page; Today renders the same four tools as a 2×2 grid of the shared `ToolTileCard` (subtitles name the job; no cost meta — the sheets state costs themselves) and presents them as **sheets**. Only tools that start a session now live here (Warm-Ups / Drills / Read Aloud / Confidence). Names match the Library exactly — one vocabulary across surfaces; do not fork tile labels per screen. The prompt wheel lives in Library → Prompts ("Spin the Wheel" card), not on Today.
4. Prompt category gates for the wheel live in Settings (`PromptSettingsView`).
5. Spotlight targets: mark with `.tourAnchor(_:)` for `AppTourView`.
6. Inbound friend-challenge links (`source=share`) persist on `SharedChallengeStore` and surface as `FriendChallengeCard` when the countdown does not run (onboarding, cancel). Do not start a countdown over onboarding.
7. Word workout is **not** a Today card, and no longer its own strip either. It renders as `SessionWordsRow` **inside** the prompt card, under a hairline the row owns itself — the card is the brief for one take (topic, length, words) and those are all parameters of the same object. The row draws nothing at all on a day with no workout, hairline included, so the card ends at the prompt text. `VocabChallengeCard` is deleted. The chips carry a `USE` prefix: without a label nobody could tell what two bare words were for, and the book glyph that preceded it explained nothing. Skip and add-to-bank hang off each chip as a tap `Menu`. Not a sheet (a full screen of chrome for two rare verbs, and it covered the prompt) and not a `contextMenu` (nobody long-presses a chip they have no reason to think is interactive). The chip carries a chevron and new words carry a sage dot — keep both, they are what makes the row look like a control. **The chips own the full card width.** The duration pill shared their line until the word cap (3, `SettingsViewModel` line 304) made the last chip wrap directly under it — an orphan beside an unrelated control, and the pill's width is what forced the wrap in the first place. It now sits in the card header with difficulty and reroll. Do not put it back. Do not pull the row back out into a standalone strip, and never put it below the start button — nothing under the CTA gets read. Knobs live in Settings → Word Workout. See [vocab-challenge.md](./vocab-challenge.md).
8. **The rotating daily challenge is deleted** (model, service, widget, and its row in what is now `SessionWordsRow`). Nobody used it, and it competed with the word workout for the same strip. Do not reintroduce a second daily objective — the prompt and the words are the day's spec.
9. **Arrival moment.** `TodayView.playArrivalIfNeeded()` fires once per calendar day, keyed on the `lastArrivalDay` AppStorage stamp: the streak chip springs in, a success haptic fires, and `ConfettiView` runs on every seventh day. It waits on `viewModel.isLoading` so it never celebrates a streak of zero, and `arrivalLine` never claims a day the user has not earned — before today's session it reads "one session keeps it".
10. Goal progress refresh fires from Today's load but never blocks it: `GoalProgressService.refreshGoals` freezes per-goal windows on the main actor, scans recordings on a background `ModelContext`, then applies outcome diffs back on main. The scan decodes one analysis blob per session — inline, it stalled every Today visit as history grew.
11. **Customizable home, edited in place.** Visible modules and order live in additive `UserSettings.todayHomeLayoutRaw` (`[String]` of `TodayHomeModule` raw values). Empty = factory default via `TodayHomeLayout.resolve`. **Session is always forced visible** — it cannot be hidden. Learn is off by default so Today stays a practice surface. Pinned in `TodayHomeLayoutTests`.

    **Today is its own editor** — there is no customize sheet and no Settings row. The toolbar control (or a long-press on any block) flips `isEditingLayout`, and the *real* blocks start wiggling: same rings, same prompt card, drag them where you want. This replaced a sheet of schematic stand-ins, which asked you to edit a drawing of the page instead of the page. Home-screen grammar throughout: ⊖ drops a block into the **Hidden** tray, ⊕ or a drag back out returns it, and the tray is itself a drop target.

    Four things that look like choices but are not. Editing blocks are wrapped in `allowsHitTesting(false)` under a near-transparent grab layer, so a drag has something to catch and a stray tap can't fire "Start Speaking" underneath. Reorder rides on `draggable`/`dropDestination` rather than a `DragGesture`, because the blocks live in a scroll view and the system drag is the one that doesn't fight it. **Weekly recap and Coach focus render nothing until they have data**, which in edit mode would be an invisible, undraggable gap — `moduleHasContent` swaps in a dashed `dormantModuleCard` saying when the block shows up for real. And drag is invisible to assistive tech, so every block carries Move up / Move down / Hide `accessibilityActions`, with the wiggle off under Reduce Motion.

12. **Prep tools strip** is four `ToolTileLabel` tiles — identity icon + short name only. Outcome copy belongs to the surfaces where you are still choosing (Library rows, the suggestion banner), not repeated under every tile. When a coach plan exists (or the user has not practiced today), a "Start with …" banner names the tool and its outcome and routes straight to it.

11. **One object: the brief owns its action.** Today's core action is the prompt card (`InteractivePromptCard` / `StoryPromptCard`) with a white "Start Speaking" capsule as its last element (`SessionStartFooter`), nothing between them. Two earlier shapes failed — twin "With Prompt" / "Free Practice" capsules gave a minority path half the screen's authority, and a `SessionModePicker` segmented pill was a fourth rounded slab reading as another chip row. Do not reintroduce either. A third shape also failed: the capsule floating *between* the card and the tools strip read as an island belonging to neither neighbor, which is why it moved inside the card as a footer. If a new session parameter needs a home it goes **in** the card — header for a control, `SessionWordsRow` for content — not into a new strip. An `eyebrowStyle()` label above the card ("Today's prompt" / "Today's story") names the brief so the page reads as labeled steps — focus, prompt, tools — and "Practice Tools" + a one-line subtitle header the tile strip; without them four icon tiles read as decoration, not doors.
    **The page has exactly one filled white capsule.** `CoachFocusCard` used to carry its own identical white CTA one scroll above Start Speaking, collapsing the hierarchy into two competing heroes; its practice routing is now a compact pill tinted with the focus color (`AppColors.tint(for:)`) — function kept, volume dropped — and the focus card is never `elevated`. Do not promote it back while Start Speaking exists on the same screen.
12. **No prompt is a second start, not a mode.** It is the quiet "Talk without a prompt" text button under the Start capsule inside `SessionStartFooter`: always visible, unmistakably subordinate, and one tap instead of set-mode-then-confirm. There is no `freePractice` state to keep in sync — the button calls `onStartRecording(nil, selectedDuration)` directly.
13. **The prompt card is a reading surface, not a control.** Both cards dropped their whole-card `onTapGesture`; the Start capsule in the footer is the only way to begin — the card hosts it, but the card itself is never tappable. The tap was invisible (no chevron, no label — `StoryPromptCard` needed a pulsing "Tap to practice" caption to advertise it, which is the tell) and it fought the duration `Menu` inside the same card for the same gesture. The header is now everything *about* the take — category, difficulty, length, reroll — which is what removed both the 44pt footer row and the separate "Today's Story" title row.
14. **Never line-limit the prompt text.** `InteractivePromptCard` clipped at four lines, which is the one thing a prompt card must not do. Condensing comes from `GlassCard(padding: 14)`, 10pt inner spacing, 18pt type, and folding the word strip into the card — not from truncation.
15. `TodayView.onStartStoryPractice` is `((Story, RecordingDuration) -> Void)` — it carries the duration because `StoryPromptCard` shows a `DurationPill` and `ContentView` used to hardcode `.sixty`, so picking a length there silently did nothing. `PracticeHubView` has its own separate callback and still passes no duration; it has no length control to honour.

## Cross-links

[today-library.md](./today-library.md) · [stories.md](./stories.md) · [practice-tools.md](./practice-tools.md) · [widgets.md](./widgets.md) · [monetization.md](./monetization.md) · [vocab-challenge.md](./vocab-challenge.md) · `/ONBOARDING_VISION.md`

## Today's focus

`TodayView.focusSection` renders the shared `CoachFocusCard` from `TodayViewModel.coachPlan`, built by `CoachPlanService` in the heavy off-main pass with the user's own `ScoreWeights`. The same pass feeds a bounded recent-window `LexiconInsightsEngine` profile in as a `CrutchHint`, so when the focus is fillers the plan names the user's top crutch word ("The repeat offender: 'like'") instead of the bare category.

The same profile also steers **prompt selection**: `TodayViewModel` blends the settings mix with lexicon weakness rates via `PromptMix.adapted(weakRatesByCategory:)`, so practice types the user measurably struggles in (≥ 2 sessions, weak rate above threshold) draw up to 2× more often. Rules that must not regress: the Settings gate always wins (disabled stays 0), evidence gates noise out, and boosts cap at 2× base weight. Pinned in `PromptMixAdaptationTests`.

**This is the placement that matters.** The session coaching screen can only tell you what to work on *after* the take you could have applied it to; Today is where the focus becomes an instruction. Default layout puts it directly above the session module for that reason — users can reorder via customize, but do not remove the focus→session instructional pairing from the factory default.

`TodayFocusCard` and `SpeechSubscores.rollingAverage` are gone. That card ranked by lowest rolling subscore over ten sessions with failed captures averaged in, while the session screen ranked by weighted deficit over twenty with them excluded — two engines that routinely named different areas on the same day. One engine now: `CoachPlanService.plan(window:weights:)`. Do not add a second.
