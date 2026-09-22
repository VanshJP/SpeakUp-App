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

**Unlock moment:** `AchievementUnlockedView` is a medal, not a card with an icon: gold angular rim, graphite face, gilded glyph, flipping in edge-first (`rotation3DEffect`) and landing with the success haptic, then one band of light sweeps the face. Confetti is full-screen from behind the medal. The card and its button ride `.introReveal()` so the only exit never waits on the flip (gotcha §23). Celebration surface - exempt from the no-glow rule.

**Gotchas:** CloudKit can duplicate Achievement rows — service dedupes by id. Celebrations are in-app only: no milestone notification and no review ask. New definition cases are inserted on launch (`SpeakUpApp`) and again in `evaluateAll` if a row is missing; existing rows refresh title/description/icon from `AchievementDefinition` without touching unlock state.

`AchievementService.shared` is the app-wide observable instance used by
`ContentView` and recording detail. The first successful playback increments
`UserSettings.listenBackCount`, saves it, then checks achievements with that
count; failed or still-downloading playback does not unlock **Brave Listener**.
Using a throwaway service instance would persist the unlock but lose the
root-level celebration.

## Goals

| Role | Path |
|------|------|
| View | `SpeakUp/Views/Goals/GoalsView.swift` |
| Service | `SpeakUp/Services/GoalProgressService.swift` |
| Model | `SpeakUp/Models/UserGoal.swift` |

Progress updates from recording pipeline / history signals. Mechanics: `GoalProgressService.refreshGoals` snapshots each goal's window on the main actor, scans all recordings on a background `ModelContext` (`Task.detached`; one analysis decode feeds every goal whose window contains the session), then applies `GoalProgressOutcome` diffs back on the main context and saves only real changes. Called from Today's load and `GoalsView`. Keep templates and progress math in the service, not duplicated in views.

## Cross-links

[today-library.md](./today-library.md) · [recording-detail.md](./recording-detail.md) · [analytics-review.md](./analytics-review.md) · [architecture.md](./architecture.md)
