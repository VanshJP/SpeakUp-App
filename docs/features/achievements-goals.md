# Achievements & goals

## Purpose

Unlockable achievements (gallery + confetti sheet) and user-defined goals with progress from practice.

## Achievements

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Achievements/` — `AchievementGalleryView`, `AchievementUnlockedView` |
| Service | `SpeakUp/Services/AchievementService.swift` |
| Model | `SpeakUp/Models/Achievement.swift` |
| FX | `Views/Components/ConfettiView.swift` |

Presented as sheets from Today / `ContentView` — **not** a tab.

**Gotchas:** CloudKit can duplicate Achievement rows — service dedupes by id. Unlock may trigger review ask (`ReviewRequestService`). New definition cases are inserted on launch (`SpeakUpApp`) and again in `evaluateAll` if a row is missing.

## Goals

| Role | Path |
|------|------|
| View | `SpeakUp/Views/Goals/GoalsView.swift` |
| Service | `SpeakUp/Services/GoalProgressService.swift` |
| Model | `SpeakUp/Models/UserGoal.swift` |

Progress updates from recording pipeline / history signals. Keep templates and progress math in the service, not duplicated in views.

## Cross-links

[today-library.md](./today-library.md) · [recording-detail.md](./recording-detail.md) · [analytics-review.md](./analytics-review.md) · [architecture.md](./architecture.md)
