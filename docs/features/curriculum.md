# Curriculum — Learn tab

## Purpose

Multi-week phases and lessons with signal-driven progression (not only manual “complete”). Distinct from Library → Tools: Learn is a curriculum path; warm-ups/drills/calm are quick prep reps.

## Key files

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Curriculum/` — `CurriculumView`, `LessonDetailView`, `LessonContentView`, `LessonCompletionView`, `LessonPath`, `LessonGlyphView`, `LessonTeachingChrome`, `PracticeResultsCard` |
| Glyphs | `LessonIdentity` + `LessonMotif` (`Models/LessonIdentity.swift`) → `LessonGlyphView` (Canvas art per lesson) |
| VM | `SpeakUp/ViewModels/CurriculumViewModel.swift` |
| Services | `CurriculumService`, `CurriculumActivitySignalStore` |
| Models | `CurriculumModels.swift`, `CurriculumProgress.swift`, `LessonContent.swift`, `LessonIdentity.swift` |
| Seed | `SpeakUp/Data/DefaultCurriculum.swift` |
| Tests | `SpeakUpTests/LessonIdentityTests.swift` — catalog ↔ seed coverage |

## Invariants

1. All eight weeks are open during the beta — the `PaidFeature.fullCurriculum` lock is removed from the UI ([monetization.md](./monetization.md)). Weeks still unlock in order.
2. Advancement uses durable activity signals in `CurriculumActivitySignalStore` — preserve signal semantics when changing lesson completion UX. Review/practice signals come from `CurriculumSessionSignals.scan(recordings)`: one decode pass over history feeding every activity. Per-activity blob reads were O(activities × recordings) on the main actor; do not reintroduce them.
3. Seed content stays in `Data/DefaultCurriculum.swift`. New lesson → add a row in `LessonIdentity.catalog` (motif + accent) in the same PR.
4. `CurriculumView` opens on a one-row header (eyebrow **LEARN** + **Your path** + the trophy) and then the **Continue** card (progress is a quiet accessory in that card's header). Directly under it, **Review last lesson** nudges the prior completed lesson so review is not buried in the path. No intro card and no separate stats card — the header row is chrome, not a card, and carries no stats. Warm-ups/drills/calm stay under Library → Tools.
    - The Continue card is **not** `elevated`. It holds a white `GlassButtonLabel`, which casts its own shadow; the heavy card shadow under it read as a second, doubled edge. Same reasoning as `CoachFocusCard`.
5. Lesson practice feedback uses `CoachingTipService` (same voice as Recording Detail) — no parallel praise strings. `PracticeResultsCard` resolves `recording.analysis` + the tip once into `@State` (blob re-decodes on every access). Pace UI and curriculum copy follow `resolvedTargetWPM`, not a fixed 130–170 band.
6. Curriculum practice with a `frameworkHint` opens `RecordingView` with that framework pre-selected and persists `frameworkUsed` so PREP/STAR completion signals are real, not “any analyzed take.”
7. **No navigation bar** (`.toolbar(.hidden, for: .navigationBar)`, like every root tab): Achievements trophy is `awardsRow`, which is also where the page says its own name — without it the tab opened on a lone icon over empty space. The trophy wears `.headerIconChrome()`, the same 44pt plate as the filter buttons on Prompts / Stories / History. Pushed `LessonDetailView` adds `.restoresNavigationBar()`. Details: [ui-design-system.md](./ui-design-system.md) rule 9.
8. **Next lesson stays in the detail stack.** `LessonDetailView` holds `@State lesson` and on "Next Lesson" swaps it in place (`advanceToNextLessonInPlace`) instead of `dismiss()`-ing back to the path list.
9. **Path nodes use lesson glyphs**, not a shared book SF Symbol. Completed rows caption **Tap to review**; revisiting a completed lesson shows **Done reviewing** (does not re-fire the completion celebration). Review activities list recent recordings and a listen lens from the lesson objective — not a lone “Mark as Done” button.
10. Glyph accents come from `AppColors` category tones; phase headers tint with `LessonIdentity.forPhase(week:)`. Keep glass tint ≤ 0.10 on cards ([ui-design-system.md](./ui-design-system.md) rule 12). A phase header is **two lines** — dot + `WEEK N` + state icon + count, then the title — not one row of six things: on one row the title was the element that lost, first at 375pt and then at every accessibility text size.
11. **Lesson detail is teacher-led.** `LessonBoardHeader` states today's focus + roadmap; `LessonPlanStrip` shows labeled Learn/Practice/Drill/Warm-up/Review chips (not anonymous capsules); `LessonCoachCue` frames the current stage. Bottom CTAs use pedagogical verbs (`Got it`, `Next · Practice`, `Finish lesson`). Completion restates the objective as “You can now…” plus the worked stages — not a trophy checklist alone.

## Cross-links

[monetization.md](./monetization.md) · [recording.md](./recording.md) · [recording-detail.md](./recording-detail.md) · [today-library.md](./today-library.md) · [practice-tools.md](./practice-tools.md) · [ui-design-system.md](./ui-design-system.md)
