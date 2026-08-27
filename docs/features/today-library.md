# Today & Library

## Purpose

**Today** — home: modular blocks (rings, focus, session, prep tools, optional learn), streak, word workout, weekly recap. Users customize which blocks show and in what order (Bevel-style).  
**Library** — unified browser: prompts, stories, tools (warm-ups, drills, read-aloud, calm).

## Key files — Today

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Today/` — `TodayView`, `TodayHomeCustomizeView`, `SessionBriefRow`, `StoryPromptCard`, `WeeklyRecapCard`, `FriendChallengeCard` |
| Layout | `SpeakUp/Models/TodayHomeModule.swift` — `TodayHomeModule`, `TodayHomeLayout` |
| Tool catalog | `SpeakUp/Models/PracticeToolKind.swift` — shared titles / outcomes / best-for |
| VM | `SpeakUp/ViewModels/TodayViewModel.swift` |
| Services | `WeeklyProgressService`, `VocabChallengeService` |
| Components | `RingStatsView`, `StreakChip`, `ToolPurposeBanner` |
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
3. Library sections: `.prompts` / `.stories` / `.tools`. Recording start callbacks bubble to `ContentView`.
4. Prompt category gates for the wheel live in Settings (`PromptSettingsView`).
5. Spotlight targets: mark with `.tourAnchor(_:)` for `AppTourView`.
6. Inbound friend-challenge links (`source=share`) persist on `SharedChallengeStore` and surface as `FriendChallengeCard` when the countdown does not run (onboarding, cancel). Do not start a countdown over onboarding.
7. Word workout is **not** a Today card. It renders as `SessionBriefRow`, a single strip between the prompt card and the start button — it is the spec for the take you are about to record, and recording is the only way it completes. `VocabChallengeCard` is deleted. Skip and add-to-bank hang off each chip as a tap `Menu`. Not a sheet (a full screen of chrome for two rare verbs, and it covered the prompt) and not a `contextMenu` (nobody long-presses a chip they have no reason to think is interactive). The chip carries a chevron and new words carry a sage dot — keep both, they are what makes the row look like a control. Do not put the row back below the start button — nothing under the CTA gets read. Knobs live in Settings → Word Workout. See [vocab-challenge.md](./vocab-challenge.md).
8. **The rotating daily challenge is deleted** (model, service, widget, and `SessionBriefRow` row). Nobody used it, and it competed with the word workout for the same strip. Do not reintroduce a second daily objective — the prompt and the words are the day's spec.
9. **Arrival moment.** `TodayView.playArrivalIfNeeded()` fires once per calendar day, keyed on the `lastArrivalDay` AppStorage stamp: the streak chip springs in, a success haptic fires, and `ConfettiView` runs on every seventh day. It waits on `viewModel.isLoading` so it never celebrates a streak of zero, and `arrivalLine` never claims a day the user has not earned — before today's session it reads "one session keeps it".
10. Goal progress refresh fires from Today's load but never blocks it: `GoalProgressService.refreshGoals` freezes per-goal windows on the main actor, scans recordings on a background `ModelContext`, then applies outcome diffs back on main. The scan decodes one analysis blob per session — inline, it stalled every Today visit as history grew.
11. **Customizable home.** Visible modules and order live in additive `UserSettings.todayHomeLayoutRaw` (`[String]` of `TodayHomeModule` raw values). Empty = factory default via `TodayHomeLayout.resolve`. **Session is always forced visible** — it cannot be hidden. Learn is off by default so Today stays a practice surface. Customize from the Today toolbar (`slider.horizontal.3`), the Prep tools "Edit" control, or Settings → Today Layout (`TodayHomeCustomizeView`). Pinned in `TodayHomeLayoutTests`.
12. **Prep tools strip** uses `PracticeToolKind` outcome copy (not one-word labels). When a coach plan exists (or the user has not practiced today), a "Suggested before you start" banner routes to the matching tool — including Read Aloud even though that tool's grid tile lives in Library.

## Cross-links

[today-library.md](./today-library.md) · [stories.md](./stories.md) · [practice-tools.md](./practice-tools.md) · [widgets.md](./widgets.md) · [monetization.md](./monetization.md) · [vocab-challenge.md](./vocab-challenge.md) · `/ONBOARDING_VISION.md`

## Today's focus

`TodayView.focusSection` renders the shared `CoachFocusCard` from `TodayViewModel.coachPlan`, built by `CoachPlanService` in the heavy off-main pass with the user's own `ScoreWeights`. The same pass feeds a bounded recent-window `LexiconInsightsEngine` profile in as a `CrutchHint`, so when the focus is fillers the plan names the user's top crutch word ("The repeat offender: 'like'") instead of the bare category.

The same profile also steers **prompt selection**: `TodayViewModel` blends the settings mix with lexicon weakness rates via `PromptMix.adapted(weakRatesByCategory:)`, so practice types the user measurably struggles in (≥ 2 sessions, weak rate above threshold) draw up to 2× more often. Rules that must not regress: the Settings gate always wins (disabled stays 0), evidence gates noise out, and boosts cap at 2× base weight. Pinned in `PromptMixAdaptationTests`.

**This is the placement that matters.** The session coaching screen can only tell you what to work on *after* the take you could have applied it to; Today is where the focus becomes an instruction. Default layout puts it directly above the session module for that reason — users can reorder via customize, but do not remove the focus→session instructional pairing from the factory default.

`TodayFocusCard` and `SpeechSubscores.rollingAverage` are gone. That card ranked by lowest rolling subscore over ten sessions with failed captures averaged in, while the session screen ranked by weighted deficit over twenty with them excluded — two engines that routinely named different areas on the same day. One engine now: `CoachPlanService.plan(window:weights:)`. Do not add a second.
