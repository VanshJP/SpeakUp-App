# Practice routine — the chain, and the handoff between links

A routine is an ordered list of practice steps and a memory of which of them are done today. Its reason to exist is the moment *after* something finishes: every step here was already a door on Today or in the Library, and what was missing was the sentence naming which door comes next.

Sibling docs: [today-library.md](./today-library.md) (the Today module it renders as), [practice-tools.md](./practice-tools.md) (the screens the links open), [settings.md](./settings.md) (the editor's hub row).

## Key files

| Path | Role |
|------|------|
| `Models/PracticeRoutine.swift` | Pure. `RoutineStep`, order (`PracticeRoutine`), per-day progress (`RoutineProgress`). |
| `Services/PracticeRoutineService.swift` | `.shared`, MainActor. Records completions, raises the handoff, carries start requests. |
| `Views/Today/RoutineCard.swift` | The Today block (one step card on a stack), the handoff bar, and the step→tool colour mapping. |
| `Views/Settings/RoutineSettingsView.swift` | Add / remove / reorder. Reached from Settings and from the card. |
| `SpeakUpTests/PracticeRoutineTests.swift` | Order and progress rules. |

## The chain

Factory: **warm up → today's take → read the score**. Short on purpose — a routine that takes twenty minutes is one people skip on the days they most need it. Available links are `calm`, `warmUp`, `drill`, `readAloud`, `session`, `review`.

## Invariants

1. **The take is pinned.** `session` cannot be removed, and `PracticeRoutine.resolve` puts it back in canonical position (before `review`, never after it) if a stored payload lost it. A chain of preparation for nothing is not a routine, and the Library already serves anyone who wants to practise unmeasured.
2. **Order is canonical on insert.** `PracticeRoutine.adding` inserts by the order of `RoutineStep.allCases` — prep, take, review — so adding Read Aloud puts it before the take rather than appending it behind the review. Reordering afterwards is unrestricted.
3. **Progress is day-stamped and rolls on read.** The app is not running at midnight, so "yesterday's ticks are gone" has to be derived, not fired. `RoutineProgress.rolling` returns `.empty` for a stamp from another day, and every accessor on `UserSettings` goes through it. `marking` after a rollover starts a fresh day rather than adding to a stale set.
4. **The card deals one step at a time.** `RoutineCard` is a `GlassSectionHeader` ("Your routine", time left, edit) over a single card for the step the user is on - `IconChip`, "Step n of m" eyebrow, title, `detail`, and a secondary Start (Open for the review). Finishing a step deals the next card; the steps still to come show as up to two painted stack edges under the card, the way iOS stacks notifications, so the chain reads as cards without drawing them all. The face swaps inside one persistent glass plate (no glass-on-glass, no glass cross-fade); the edges are painted, not glass, because they sit flush against the plate. When nothing is left the card becomes "Routine done". Earlier shapes - a vertical ladder, a rail of markers, a timeline of waveform clips with a playhead - each put the whole chain on screen to say "do the warm-up", and the timeline read as a scrubber nobody could drag. The card is not a door to every step any more: the take is one tap away in the prompt card below it, and the tools are in Prep tools. Completion still fires only from a real finish (invariant 6).
5. **The handoff and the card both look forward.** `nextAfter` (the handoff) takes the first unfinished link *after* the one just finished — someone who skipped the warm-up and went straight to the take is pointed at the review, not sent back to a warm-up the take has already made pointless. The card uses `RoutineProgress.upNext(in:completed:)`: the first unfinished link after the furthest one done, so a skipped link is passed rather than dealt again. **The take is never passed** - opening an old breakdown from History ticks the review without a take today, and the card must still deal the take. `next` (first unfinished, skipped or not) is kept for `isDone`. `PracticeRoutineTests` pins both.
6. **Completion is a real finish, never an open.** Warm-up and Calm tick on their runner's `isComplete`, a drill ticks only with a scored `result`, Read Aloud on `sessionState == .finished`, the take on either save path in `ContentView`, and `review` when a breakdown is actually opened. `complete` is idempotent — these all fire from view state that re-evaluates.
7. **Only links in the user's chain raise a handoff.** A warm-up taken on a whim is not a routine, and treating it as one would put the bar in front of everybody who ever opens a tool. It is still ticked, so adding the step later finds it done.
8. **A bar pointing at the screen you are on clears itself.** Completing the step a live handoff names dismisses it — a take routed straight into its own breakdown ticks `review` while the bar is still offering it.
9. **The bar lives on the tab surface, not inside the screen that finished** — that screen is a sheet on its way out. Set while the sheet is still up, the bar is simply already there when it goes. It is hosted in each tab's `safeAreaBar(edge: .bottom)` (`ContentView.tabContent(for:)`), so it sits above the floating tab bar and lifts scroll content clear of itself. It used to be a `ZStack` sibling of the `TabView`, whose safe area ends at the home indicator, which put it on top of the tabs. The app tour outranks it: a spotlight with a bar floating over it teaches nothing. Its button is `GlassButton.secondary` (Start speaking is Today's only white primary) and its line reads "Done. Next up:" - step titles are imperatives, so "<step> done" read "Run a drill done".
10. **`ContentView` routes every step except `.session`.** The day's brief (prompt or story) and the duration pill exist only on Today, so `ContentView` sets the tab and leaves the request standing; `TodayView` takes it, on the request itself or on the edge where it becomes the active tab (the handoff can be raised from another tab, and the request lands before the switch does), and starts it through `startTodaysTake()` - a story on a story day. `review` opens the latest take's breakdown (`ContentView.openLatestTake()`), not the History list it would have to be found in.
11. **A chain of one renders nothing.** With only the take in it, the card is the session module said twice — `moduleHasContent` reports false, which is also what gives it the dashed dormant placeholder in Today's layout editor.
12. **Colour is not on the model.** `RoutineStep` is `nonisolated` and pure; `PracticeToolKind` and `AppColors` are MainActor-isolated, so `tool` and `tint` live in a `RoutineCard.swift` extension (gotchas §7). Do not fork tool identity colours here.

## Schema

Additive only (`UserSettings`): `routineStepsRaw: [String]` (empty = factory chain), `routineCompletedRaw: [String]`, `routineProgressDay: Date?`. A settings reset clears all three — the order is a preference and the ticks belong to a day the reset has just ended.

## Deliberately not built

- **A second overlay.** Achievements and coach notes already own full-screen interruption. The handoff is a dismissible bar.
- **Streaks or scores per routine.** The streak is one number and it counts days the user spoke. A routine-completion streak would be a second scoreboard competing with it.
- **Drag to reorder.** Six rows at most, and arrows are already reachable by every assistive technology without an accessibility action of their own.
