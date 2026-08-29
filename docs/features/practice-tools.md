# Practice tools — warm-ups, drills, confidence, read-aloud

## Purpose

Prep and targeted practice surfaces, optionally linked to a Story from Library send-to. Each tool has a single catalog entry in `PracticeToolKind` (title, outcome, best-for, icon, color) so Today, Library, and sheet headers never disagree about what the tool is for.

## Catalog

| Role | Path |
|------|------|
| Shared copy / identity | `SpeakUp/Models/PracticeToolKind.swift` |
| Page skeleton | `SpeakUp/Views/Components/ToolPage.swift` — `ToolPage`, `ToolFilterBar`, `SourceStoryBanner` |
| Item row | `SpeakUp/Views/Components/PracticeItemRow.swift` |
| Shared tile | `SpeakUp/Views/Components/ToolTile.swift` — `ToolTileLabel` (Today strip + History grid) |

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

1. Presented as **sheets** from `ContentView` (Today toolbar), Today's focus card, and `RecordingDetailView` next-steps (drills / warm-ups / read-aloud — Calm has no next-step route; there is no subscore that means "nervous", so do not invent one without product intent); pushed as **full pages** from the Library Tools tab via `navigationDestination(item:)` — browsing context gets the whole screen. Selection views take `isPushed: true` and hand it to `ToolPage`, which owns what it changes: no inner `NavigationStack`, and no sheet-only ✕ (Back replaces it). Never a separate tab.
2. `sourceStory` banners when routed from Stories; keep story id plumbing intact.
3. Tool identity colors: `AppColors.toolWarmUp` / `toolDrill` / `toolReadAloud` / `toolCalm` / `toolWheel` — shared with the Today prep strip via `PracticeToolKind.color`. Sub-category and drill-mode colors draw from the muted jewel set (`categoryBrandBright/Copper/Plum/Sage/Indigo/Amber`) — never system `.orange/.purple/.blue/.red`.
4. Seed arrays live under `Data/`.
5. **One page skeleton, not four.** All four tool pages are a `ToolPage`: it owns the background, the scroll, the column padding, the nav title (from `PracticeToolKind.title`, so "Quick Drills" can't drift from `Drills` again), the sheet ✕, and the single secondary header line (`PracticeToolKind.outcome`). A page supplies its filters and its items and nothing else — that is what keeps a fifth dialect from appearing. Filters go in a `ToolFilterBar` so no page insets its pills inside the already-padded column; `sourceStory` uses the shared `SourceStoryBanner`.
6. **One line of chrome, not three.** The nav bar already names the page, so an eyebrow label and a purpose card on top of it were the same sentence three times; `ToolPurposeBanner` was deleted, not relocated. `bestFor` is a browsing aid and stays in the Library rows only.
7. Library → Tools leads with an intro that separates Tools from Prompts/Stories, then outcome-forward rows (not icon + one-line subtitle only).
8. **Map before mask.** Warm-Ups and Calm open unfiltered ("All" pill first), grouped into labeled sections — category name + icon + count (`GlassSectionHeader`) + a one-line `purpose` caption on the model. A filter pill collapses to the single matching group; it never hides the taxonomy on arrival. Filtered-empty states offer a "Show All" recovery button.
9. Runner controls use `GlassButton` (primary = forward/Done, secondary = Back) and `Font.displayNumeral` for the hero countdown — no hand-rolled white capsules. The warm-up transport trio (restart/play/skip) is round-icon, exempt from the capsule rule. Runners confirm before discarding an active session (warm-up ✕ mid-run asks, same as drills).
10. `ConfidenceCategory.color` draws from the jewel set; exercise steps read via `step(safelyAt:)`, never a raw subscript. Step cards re-`.id` on the index so swaps animate; finishing fires `Haptics.success()` + the `.exhale` chirp, distinct from step ticks.
11. **Explain once, at the surface where the choice is made.** The Library Tools tab renders outcome-forward **rows** — icon, title, outcome, best-for, count/time meta — because that is the browsing surface, and opens each tool as a pushed page (`isPushed: true`). Searchable across title/outcome/best-for, empty state on no match. Today's prep strip and History's grid both use the compact `ToolTileLabel` (`Views/Components/ToolTile.swift`) — icon + short name, no description: four tiles each carrying a two-line outcome read as a wall of grey text, and on Today the suggestion banner already explains the one tool that matters. Two densities, one copy source (`PracticeToolKind`) — do not hand-roll a third tile dialect.
12. **Every item is a `PracticeItemRow`** — dial, title, subtitle, optional tag chip, play affordance. Drills used to be a 2x2 of 176pt tiles and Read Aloud a bespoke `PassageCard`; four items each stacking an icon, title, outcome, live-feedback label and duration (two of them tinted) is five things competing inside one card, and it made Drills the odd page out. Cost is split by size: the **dial** takes one short unit that fits its 8pt label (`45s`, `3m`, `2m`), the **chip** takes the qualifier that doesn't — Calm's step count (it used to be crammed into the dial as "3m · 4 steps"), a drill's `liveFeedback`, a passage's difficulty + word count. Read Aloud keeps its "N of M passages" caption while filters are active.
13. **Timers tell the truth.** Step/duration clocks finish inside the tick that reaches zero (a "48s" box-breathing round lasts 48s, and 4-7-8 runs 4-7-8). Drill countdowns likewise; the drill timer also stops the session early with an "ended early: recognition stopped" note if transcription dies mid-drill.
14. **Silence is not a score.** A drill whose mic or speech recognition can't start sets `errorMessage` and exits via alert — it never awards a clean-run result for audio that was never heard. Pause Practice is exempt (it scores metering silence). Read Aloud carries the same doctrine as result notices (see [read-aloud.md](./read-aloud.md)).
15. Pace-control drills score against `DrillViewModel.targetWPM` (from `UserSettings.resolvedTargetWPM`), not a fixed 130–170 band. Result copy names that target.
16. Breathing circle scale is computed from accumulated phase time (`TimelineView`, paused when paused) — never `withAnimation`, which cannot be cancelled and desyncs from the clock.

## Cross-links

[today-library.md](./today-library.md) · [stories.md](./stories.md) · [read-aloud.md](./read-aloud.md) · [ui-design-system.md](./ui-design-system.md)
