# Coach notes

## Purpose

Rare, optional coach notes when practice history earns one — welcome-back after a break, a soft landing on a rough take, a streak or skill celebration. Not a second coaching system: scores and `CoachPlan` stay the main path; these are short asides, at most one celebration per week.

## Key files

| Role | Path |
|------|------|
| Signals / budget engine | `SpeakUp/Models/CoachMoment.swift` |
| Presentation + SwiftData I/O | `SpeakUp/Services/CoachMomentService.swift` |
| Inline card + overlay | `SpeakUp/Views/CoachMoment/CoachMomentCard.swift` |
| Persistence | `UserSettings.coachMomentWeekKey` / `coachMomentCelebrationsUsedThisWeek` / `coachMomentDeliveredIDs` / `coachMomentClearedDimensionsRaw` |
| Today eval | `TodayViewModel.loadData` → `CoachMomentService.evaluateToday` |
| Today card | `TodayView` (FriendChallenge-style, above modules) |
| Overlay | `ContentView` (after achievements) |
| Detail eval | `RecordingDetailView.evaluateCoachMomentIfNeeded` |
| Tests | `SpeakUpTests/CoachMomentTests.swift` |

## Signals

| Signal | Celebration? | Surface | Trigger |
|--------|--------------|---------|---------|
| `returnFromLapse` | no | Today | ≥ 5 quiet days, not practiced today |
| `softLanding` | no | Detail | Overall &lt; 45 with real words (not a dead mic) |
| `streakMilestone` | yes | Overlay | Streak ≥ 7 and multiple of 7, practiced today |
| `practiceAnniversary` | yes | Overlay | 30 / 100 / 365 days since first recording |
| `firstAxisClear` | yes | Detail | Dimension hits mastery (85) for the first time |
| `fillerBreakthrough` | yes | Detail | Zero fillers on a take with ≥ 40 words |

Care notes never spend the weekly celebration budget. Celebrations cap at **1 per calendar week**.

## Tone / privacy

1. User-facing label is **Coach note** — never "hospitality", "ghosts", or Guidara jargon.
2. No transcript keyword mining. Signals come from scores, streaks, and dates only.
3. Welcome-back copy never names how many days were missed.
4. Every note is dismissible; dismiss still marks delivered so it does not nag all day.
5. Analytics: `milestone(type: coach_moment_<signal>)` only — no transcript text.

## Invariants

1. Pure judgement stays in `CoachMomentEngine` — `nonisolated`, injectable `now`, no `ModelContext`. Service owns fetch + pending slots.
2. Additive `UserSettings` only. Empty week key / zero used / empty lists = never shown.
3. Delivered moment ids are capped (~40) so CloudKit rows do not grow forever.
4. First-axis wins persist `CoachDimension.rawValue` on consume so the toast is once per dimension.
5. One pending note **per surface** (`pendingToday` / `pendingDetail` / `pendingOverlay`). Today eval must not clobber a detail soft-landing. Achievements overlay outranks coach-note overlay.
6. `CoachMomentEngine.propose(..., surface:)` filters by surface so Today care cannot starve an overlay celebration on the same visit.
7. No new Today home module — transient card like `FriendChallengeCard`, not a customizable block.

## Cross-links

[today-library.md](./today-library.md) · [recording-detail.md](./recording-detail.md) · [achievements-goals.md](./achievements-goals.md) · [analytics-review.md](./analytics-review.md)
