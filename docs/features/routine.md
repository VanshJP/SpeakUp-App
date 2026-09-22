# Practice routine — the chain, and the handoff between links

A routine is an ordered list of practice steps and a memory of which of them are done today. Its reason to exist is the moment *after* something finishes: every step here was already a door on Today or in the Library, and what was missing was the sentence naming which door comes next.

Sibling docs: [today-library.md](./today-library.md) (the Today module it renders as), [practice-tools.md](./practice-tools.md) (the screens the links open), [settings.md](./settings.md) (the editor's hub row).

## Key files

| Path | Role |
|------|------|
| `Models/PracticeRoutine.swift` | Pure. `RoutineStep`, order (`PracticeRoutine`), per-day progress (`RoutineProgress`). |
| `Services/PracticeRoutineService.swift` | `.shared`, MainActor. Records completions, raises the handoff, carries start requests. |
| `Views/Today/RoutineCard.swift` | The Today block, the handoff bar, and the step→tool colour mapping. |
| `Views/Settings/RoutineSettingsView.swift` | Add / remove / reorder. Reached from Settings and from the card. |
| `SpeakUpTests/PracticeRoutineTests.swift` | Order and progress rules. |

## The chain

Factory: **warm up → today's take → read the score**. Short on purpose — a routine that takes twenty minutes is one people skip on the days they most need it. Available links are `calm`, `warmUp`, `drill`, `readAloud`, `session`, `review`.

## Invariants

1. **The take is pinned.** `session` cannot be removed, and `PracticeRoutine.resolve` puts it back in canonical position (before `review`, never after it) if a stored payload lost it. A chain of preparation for nothing is not a routine, and the Library already serves anyone who wants to practise unmeasured.
2. **Order is canonical on insert.** `PracticeRoutine.adding` inserts by the order of `RoutineStep.allCases` — prep, take, review — so adding Read Aloud puts it before the take rather than appending it behind the review. Reordering afterwards is unrestricted.
3. **Progress is day-stamped and rolls on read.** The app is not running at midnight, so "yesterday's ticks are gone" has to be derived, not fired. `RoutineProgress.rolling` returns `.empty` for a stamp from another day, and every accessor on `UserSettings` goes through it. `marking` after a rollover starts a fresh day rather than adding to a stale set.
4. **The card is a rail, and every marker is a door.** `RoutineCard` draws the chain horizontally - marker + `RoutineStep.shortTitle` per step, connected by half-segments lit by the step *before* them - then the current step's `detail` and one CTA. It was a vertical ladder where only the step named on the button could be tapped, which cost a third of the home screen to say "three things, you are on the first". Tapping any marker calls `onStart` for that step; completion still fires only from a real finish (invariant 6), so jumping ahead ticks nothing by itself.
5. **The handoff looks forward; the card looks outstanding.** `nextAfter` (the handoff) takes the first unfinished link *after* the one just finished — someone who skipped the warm-up and went straight to the take is pointed at the review, not sent back to a warm-up the take has already made pointless. `next` (the card's current step, and its CTA) is the first unfinished link in the chain, so the skipped one stays visible.
6. **Completion is a real finish, never an open.** Warm-up and Calm tick on their runner's `isComplete`, a drill ticks only with a scored `result`, Read Aloud on `sessionState == .finished`, the take on either save path in `ContentView`, and `review` when a breakdown is actually opened. `complete` is idempotent — these all fire from view state that re-evaluates.
7. **Only links in the user's chain raise a handoff.** A warm-up taken on a whim is not a routine, and treating it as one would put the bar in front of everybody who ever opens a tool. It is still ticked, so adding the step later finds it done.
8. **A bar pointing at the screen you are on clears itself.** Completing the step a live handoff names dismisses it — a take routed straight into its own breakdown ticks `review` while the bar is still offering it.
9. **The bar lives over the tab surface, not inside the screen that finished** — that screen is a sheet on its way out. Set while the sheet is still up, the bar is simply already there when it goes. The app tour outranks it: a spotlight with a bar floating over it teaches nothing.
10. **`ContentView` routes every step except `.session`.** The day's prompt and the duration pill exist only on Today, so `ContentView` sets the tab and leaves the request standing; `TodayView` takes it, on the request itself or on the edge where it becomes the active tab (the handoff can be raised from another tab, and the request lands before the switch does).
11. **A chain of one renders nothing.** With only the take in it, the card is the session module said twice — `moduleHasContent` reports false, which is also what gives it the dashed dormant placeholder in Today's layout editor.
12. **Colour is not on the model.** `RoutineStep` is `nonisolated` and pure; `PracticeToolKind` and `AppColors` are MainActor-isolated, so `tool` and `tint` live in a `RoutineCard.swift` extension (gotchas §7). Do not fork tool identity colours here.

## Schema

Additive only (`UserSettings`): `routineStepsRaw: [String]` (empty = factory chain), `routineCompletedRaw: [String]`, `routineProgressDay: Date?`. A settings reset clears all three — the order is a preference and the ticks belong to a day the reset has just ended.

## Deliberately not built

- **A second overlay.** Achievements and coach notes already own full-screen interruption. The handoff is a dismissible bar.
- **Streaks or scores per routine.** The streak is one number and it counts days the user spoke. A routine-completion streak would be a second scoreboard competing with it.
- **Drag to reorder.** Six rows at most, and arrows are already reachable by every assistive technology without an accessibility action of their own.
