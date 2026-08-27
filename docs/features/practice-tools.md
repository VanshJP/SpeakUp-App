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

1. Presented as **sheets** from `ContentView` (Today toolbar), Today's focus card, and `RecordingDetailView` next-steps (drills / warm-ups / read-aloud — Calm has no next-step route; there is no subscore that means "nervous", so do not invent one without product intent); pushed as **full pages** from the Library Tools tab via `navigationDestination(item:)` — browsing context gets the whole screen. Selection views take `isPushed: true` to skip their inner `NavigationStack` and the sheet-only ✕ (Back replaces it). Never a separate tab.
2. `sourceStory` banners when routed from Stories; keep story id plumbing intact.
3. Tool identity colors: `AppColors.toolWarmUp` / `toolDrill` / `toolReadAloud` / `toolCalm` / `toolWheel` — shared with the Today prep strip via `PracticeToolKind.color`. Sub-category and drill-mode colors draw from the muted jewel set (`categoryBrandBright/Copper/Plum/Sage/Indigo/Amber`) — never system `.orange/.purple/.blue/.red`.
4. Seed arrays live under `Data/`.
5. Every tool sheet opens with `ToolPurposeBanner` (outcome + best-for, both from `PracticeToolKind`) above the list/grid.
6. Every list page opens with the same header grammar: eyebrow label + one explainer sentence (`Get Ready`, `Sharpen Up`, `Read Aloud`, `Settle Down`), then filters/banner.
7. Library → Tools leads with an intro that separates Tools from Prompts/Stories, then outcome-forward rows (not icon + one-line subtitle only).
8. **Map before mask.** Warm-Ups and Calm open unfiltered ("All" pill first), grouped into labeled sections — category name + icon + count (`GlassSectionHeader`) + a one-line `purpose` caption on the model. A filter pill collapses to the single matching group; it never hides the taxonomy on arrival. Filtered-empty states offer a "Show All" recovery button.
9. Runner controls use `GlassButton` (primary = forward/Done, secondary = Back) and `Font.displayNumeral` for the hero countdown — no hand-rolled white capsules. The warm-up transport trio (restart/play/skip) is round-icon, exempt from the capsule rule. Runners confirm before discarding an active session (warm-up ✕ mid-run asks, same as drills).
10. `ConfidenceCategory.color` draws from the jewel set; exercise steps read via `step(safelyAt:)`, never a raw subscript. Step cards re-`.id` on the index so swaps animate; finishing fires `Haptics.success()` + the `.exhale` chirp, distinct from step ticks.
11. The Library Tools tab renders outcome-forward **rows** — icon, title, outcome, best-for, then count/time meta — not a grid of icon tiles, and opens each tool as a pushed page (`isPushed: true`), because Library is where you browse. Searchable across title/outcome/best-for, empty state on no match. Today's prep strip uses the dense `PrepToolTile`; History's grid uses the compact `ToolTileLabel` (`Views/Components/ToolTile.swift`). Three surfaces, three densities, one copy source (`PracticeToolKind`) — do not hand-roll a fourth tile dialect.
12. Selection pages state the cost of an item before you commit: warm-up rows carry seconds + relative arc; Calm rows carry minutes · step count; drill tiles carry duration + a `liveFeedback` line naming what the session shows while it runs; Read Aloud cards carry word count + ≈minutes at ~150 wpm, and a "N of M passages" caption while filters are active.
13. **Timers tell the truth.** Step/duration clocks finish inside the tick that reaches zero (a "48s" box-breathing round lasts 48s, and 4-7-8 runs 4-7-8). Drill countdowns likewise; the drill timer also stops the session early with an "ended early: recognition stopped" note if transcription dies mid-drill.
14. **Silence is not a score.** A drill whose mic or speech recognition can't start sets `errorMessage` and exits via alert — it never awards "Perfect! Zero fillers!" for audio that was never heard. Pause Practice is exempt (it scores metering silence). Read Aloud carries the same doctrine as result notices (see [read-aloud.md](./read-aloud.md)).
15. Breathing circle scale is computed from accumulated phase time (`TimelineView`, paused when paused) — never `withAnimation`, which cannot be cancelled and desyncs from the clock.

## Cross-links

[today-library.md](./today-library.md) · [stories.md](./stories.md) · [read-aloud.md](./read-aloud.md) · [ui-design-system.md](./ui-design-system.md)
