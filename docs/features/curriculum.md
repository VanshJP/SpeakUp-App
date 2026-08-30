# Curriculum — Learn tab

## Purpose

Multi-week phases and lessons with signal-driven progression (not only manual “complete”). Distinct from Library → Tools: Learn is a curriculum path; warm-ups/drills/calm are quick prep reps.

## Key files

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Curriculum/` — `CurriculumView`, `LessonDetailView`, `LessonContentView`, `LessonCompletionView`, `LessonPath`, `PracticeResultsCard` |
| VM | `SpeakUp/ViewModels/CurriculumViewModel.swift` |
| Services | `CurriculumService`, `CurriculumActivitySignalStore` |
| Models | `CurriculumModels.swift`, `CurriculumProgress.swift`, `LessonContent.swift` |
| Seed | `SpeakUp/Data/DefaultCurriculum.swift` |

## Invariants

1. All eight weeks are open during the beta — the `PaidFeature.fullCurriculum` lock is removed from the UI ([monetization.md](./monetization.md)). Weeks still unlock in order.
2. Advancement uses durable activity signals in `CurriculumActivitySignalStore` — preserve signal semantics when changing lesson completion UX. Review/practice signals come from `CurriculumSessionSignals.scan(recordings)`: one decode pass over history feeding every activity. Per-activity blob reads were O(activities × recordings) on the main actor; do not reintroduce them.
3. Seed content stays in `Data/DefaultCurriculum.swift`.
4. `CurriculumView` opens on the **Continue** card (progress is a quiet accessory in that card's header). No intro card and no separate stats card — those buried the CTA under boxes. Warm-ups/drills/calm stay under Library → Tools.
5. Lesson practice feedback uses `CoachingTipService` (same voice as Recording Detail) — no parallel praise strings. Pace UI and curriculum copy follow `resolvedTargetWPM`, not a fixed 130–170 band.
6. Curriculum practice with a `frameworkHint` opens `RecordingView` with that framework pre-selected and persists `frameworkUsed` so PREP/STAR completion signals are real, not “any analyzed take.”
7. **Next lesson stays in the detail stack.** `LessonDetailView` holds `@State lesson` and on "Next Lesson" swaps it in place (`advanceToNextLessonInPlace`) instead of `dismiss()`-ing back to the path list.

## Cross-links

[monetization.md](./monetization.md) · [recording.md](./recording.md) · [recording-detail.md](./recording-detail.md) · [today-library.md](./today-library.md) · [practice-tools.md](./practice-tools.md)
