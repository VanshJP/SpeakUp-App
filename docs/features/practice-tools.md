# Practice tools — warm-ups, drills, confidence

## Purpose

Prep and targeted practice surfaces, optionally linked to a Story from Library send-to.

## Warm-ups

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/WarmUp/` — list, exercise, `BreathingAnimationView` |
| VM | `WarmUpViewModel` |
| Model / data | `WarmUpExercise.swift`, `DefaultWarmUps.swift` |

Categories: breathing / tongue twisters / vocal / articulation.

## Drills

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Drills/` — selection, session, result |
| VM | `DrillViewModel` |
| Model | `DrillMode.swift` |

Modes: filler elimination / pace control / pause practice / impromptu sprint.

## Confidence

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Confidence/` — tools list, exercise |
| Model / data | `ConfidenceExercise.swift`, `DefaultConfidenceExercises.swift` |

Kinds: calming / visualization / progressive / affirmation.

## Invariants

1. Presented as sheets from `ContentView` / Library / Today — not separate tabs.
2. `sourceStory` banners when routed from Stories; keep story id plumbing intact.
3. Tool identity colors: `AppColors.toolWarmUp` / `toolDrill` / `toolReadAloud` / `toolCalm` / `toolWheel` — shared with Today quick-action strip.
4. Seed arrays live under `Data/`.

## Cross-links

[today-library.md](./today-library.md) · [stories.md](./stories.md) · [read-aloud.md](./read-aloud.md) · [ui-design-system.md](./ui-design-system.md)
