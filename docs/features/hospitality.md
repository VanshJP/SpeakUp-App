# Hospitality (95/5)

## Purpose

Unreasonable hospitality for Big Talk — Guidara's rule: run 95% of the experience for consistent excellence, spend 5% on rare personal gestures that make someone feel seen. The coach is the frontline ("dot on the line"): it notices unspoken needs ("ghosts") and acts without a settings form.

## Key files

| Role | Path |
|------|------|
| Signals / gestures / budget engine | `SpeakUp/Models/Hospitality.swift` |
| Presentation + SwiftData I/O | `SpeakUp/Services/HospitalityService.swift` |
| Inline card + overlay | `SpeakUp/Views/Hospitality/HospitalityMomentCard.swift` |
| Persistence | `UserSettings.hospitalityWeekKey` / `hospitalityLegendsUsedThisWeek` / `hospitalityDeliveredIDs` / `hospitalityClearedDimensionsRaw` |
| Today eval | `TodayViewModel.loadData` → `HospitalityService.evaluateToday` |
| Today card | `TodayView` (FriendChallenge-style, above modules) |
| Overlay | `ContentView` (after achievements) |
| Detail eval | `RecordingDetailView.evaluateHospitalityIfNeeded` |
| Tests | `SpeakUpTests/HospitalityTests.swift` |

## Signals (ghosts)

| Signal | Legend? | Surface | Trigger |
|--------|---------|---------|---------|
| `returnFromLapse` | no | Today | ≥ 3 days since last practice, not practiced today |
| `softLanding` | no | Detail | Overall &lt; 45 with real words (not a dead mic) |
| `streakMilestone` | yes | Overlay | Streak ≥ 7 and multiple of 7, practiced today |
| `practiceAnniversary` | yes | Overlay | 30 / 100 / 365 days since first recording |
| `firstAxisClear` | yes | Detail | Dimension hits mastery (85) for the first time |
| `fillerBreakthrough` | yes | Detail | Zero fillers on a take with ≥ 40 words |
| `lifeContextPrep` | yes | Today | Transcript keywords (interview, wedding, standup, pitch deck, presentation) |

Care gestures (lapse / soft landing) never spend the weekly legend budget. Legends cap at **1 per calendar week**.

## Invariants

1. Pure judgement stays in `HospitalityEngine` — `nonisolated`, injectable `now`, no `ModelContext`. Service owns fetch + `pendingMoment`.
2. Additive `UserSettings` only. Empty week key / zero used / empty lists = never hosted.
3. Delivered moment ids are capped (~40) so CloudKit rows do not grow forever.
4. First-axis wins persist `CoachDimension.rawValue` on consume so the toast is once per dimension.
5. One pending moment **per surface** (`pendingToday` / `pendingDetail` / `pendingOverlay`). Today eval must not clobber a detail soft-landing. Achievements overlay outranks hospitality overlay.
6. `HospitalityEngine.propose(..., surface:)` filters by surface so Today care cannot starve an overlay legend on the same visit.
6. No new Today home module — transient card like `FriendChallengeCard`, not a customizable block.
7. Analytics: `milestone(type: hospitality_<signal>)` only — no transcript text.
8. Life-context detection is keyword-narrow on purpose (`pitch deck` / `investor`, not bare `pitch`).

## Cross-links

[today-library.md](./today-library.md) · [recording-detail.md](./recording-detail.md) · [achievements-goals.md](./achievements-goals.md) · [analytics-review.md](./analytics-review.md)
