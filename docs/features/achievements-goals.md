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

Progress updates from recording pipeline / history signals. Mechanics: `GoalProgressService.refreshGoals` snapshots each goal's window on the main actor, scans all recordings on a background `ModelContext` (`Task.detached`; one analysis decode feeds every goal whose window contains the session), then applies `GoalProgressOutcome` diffs back on the main context and saves only real changes. Called from Today's load and `GoalsView`. Keep templates and progress math in the service, not duplicated in views.

## Cross-links

[today-library.md](./today-library.md) · [recording-detail.md](./recording-detail.md) · [analytics-review.md](./analytics-review.md) · [architecture.md](./architecture.md)
