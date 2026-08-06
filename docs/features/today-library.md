# Today & Library

## Purpose

**Today** — home: rings, focus/prompt, streak, daily challenge, weekly recap, quick tools, story shortcut.  
**Library** — unified browser: prompts, stories, tools (warm-ups, drills, read-aloud, confidence).

## Key files — Today

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Today/` — `TodayView`, `TodayFocusCard`, `DailyChallengeCard`, `StoryPromptCard`, `WeeklyRecapCard` |
| VM | `SpeakUp/ViewModels/TodayViewModel.swift` |
| Services | `DailyChallengeService`, `WeeklyProgressService` |
| Components | `RingStatsView`, `StreakChip` |
| Widget writes | `SpeakUp/Services/WidgetDataProvider.swift` |

## Key files — Library

| Role | Path |
|------|------|
| Hub | `SpeakUp/Views/Practice/PracticeHubView.swift` (`PracticeSection`) |
| Prompts | `Views/Prompts/` — all / add / batch CSV |
| CSV | `PromptCSVService`, `Data/DefaultPrompts.swift` |
| Wheel | `Views/PromptWheel/PromptWheelView.swift`, `PromptWheelViewModel` |

## Invariants

1. Fingerprint-gate `WidgetCenter.reloadAllTimelines()` from `TodayViewModel` — never reload unconditionally.
2. First-run after onboarding: `FirstRecordingSetupSheet` then `AppTourView` (sequential; tour model on `ContentView`).
3. Library sections: `.prompts` / `.stories` / `.tools`. Recording start callbacks bubble to `ContentView`.
4. Prompt category gates for wheel/challenge live in Settings (`PromptSettingsView`).
5. Spotlight targets: mark with `.tourAnchor(_:)` for `AppTourView`.

## Cross-links

[recording.md](./recording.md) · [stories.md](./stories.md) · [practice-tools.md](./practice-tools.md) · [widgets.md](./widgets.md) · [monetization.md](./monetization.md) · `/ONBOARDING_VISION.md`
