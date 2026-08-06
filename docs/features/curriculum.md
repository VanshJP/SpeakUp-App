# Curriculum — Learn tab

## Purpose

Multi-week phases and lessons with signal-driven progression (not only manual “complete”).

## Key files

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Curriculum/` — `CurriculumView`, `LessonDetailView`, `LessonContentView`, `LessonCompletionView`, `LessonPath`, `PracticeResultsCard` |
| VM | `SpeakUp/ViewModels/CurriculumViewModel.swift` |
| Services | `CurriculumService`, `CurriculumActivitySignalStore` |
| Models | `CurriculumModels.swift`, `CurriculumProgress.swift`, `LessonContent.swift` |
| Seed | `SpeakUp/Data/DefaultCurriculum.swift` |

## Invariants

1. Weeks beyond the first require Lifetime: `PaidFeature.fullCurriculum` via `PaywallCoordinator`.
2. Advancement uses durable activity signals in `CurriculumActivitySignalStore` — preserve signal semantics when changing lesson completion UX.
3. Seed content stays in `Data/DefaultCurriculum.swift`.

## Cross-links

[monetization.md](./monetization.md) · [recording.md](./recording.md) · [today-library.md](./today-library.md)
