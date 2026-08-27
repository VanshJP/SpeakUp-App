# Practice tools — warm-ups, drills, confidence, read-aloud

## Purpose

Prep and targeted practice surfaces, optionally linked to a Story from Library send-to. Each tool has a single catalog entry in `PracticeToolKind` (title, outcome, best-for, icon, color) so Today, Library, and sheet headers never disagree about what the tool is for.

## Catalog

| Role | Path |
|------|------|
| Shared copy / identity | `SpeakUp/Models/PracticeToolKind.swift` |
| Purpose banner | `SpeakUp/Views/Components/ToolPurposeBanner.swift` |

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
| Model | `DrillMode.swift` — `outcome` + duration `description`, `AppColors` identity tones |

Modes: filler elimination / pace control / pause practice / impromptu sprint.

## Confidence (Calm)

| Role | Path |
|------|------|
| Views | `SpeakUp/Views/Confidence/` — tools list, exercise |
| Model / data | `ConfidenceExercise.swift`, `DefaultConfidenceExercises.swift` |

Kinds: calming / visualization / progressive / affirmation. Sheet title is **Calm** (matches Today / Library naming).

## Invariants

1. Presented as sheets from `ContentView` / Library / Today — not separate tabs.
2. `sourceStory` banners when routed from Stories; keep story id plumbing intact.
3. Tool identity colors: `AppColors.toolWarmUp` / `toolDrill` / `toolReadAloud` / `toolCalm` / `toolWheel` — shared with Today prep strip via `PracticeToolKind.color`.
4. Seed arrays live under `Data/`.
5. Every tool sheet opens with `ToolPurposeBanner` (outcome + best-for) above the list/grid.
6. Library → Tools leads with an intro that separates Tools from Prompts/Stories, then outcome-forward rows (not icon + one-line subtitle only).

## Cross-links

[today-library.md](./today-library.md) · [stories.md](./stories.md) · [read-aloud.md](./read-aloud.md) · [ui-design-system.md](./ui-design-system.md)
