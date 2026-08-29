# Coach notes

## Purpose

Rare, optional coach notes when practice history earns one — welcome-back after a break, a soft landing, a skill mark, or a practice anniversary. Not a second coaching system: scores and `CoachPlan` stay the main path; these are short asides, at most one celebration per week.

## Key files

| Role | Path |
|------|------|
| Signals / budget engine | `SpeakUp/Models/CoachMoment.swift` |
| Presentation + SwiftData I/O | `SpeakUp/Services/CoachMomentService.swift` |
| Inline card + overlay | `SpeakUp/Views/CoachMoment/CoachMomentCard.swift` — CTAs are `GlassButton.primary` |
| Persistence | `UserSettings.coachMomentWeekKey` / `coachMomentCelebrationsUsedThisWeek` / `coachMomentDeliveredIDs` / `coachMomentClearedDimensionsRaw` |
| Today eval | `TodayViewModel.loadData` → `CoachMomentService.evaluateToday` |
| Today card | `TodayView` (FriendChallenge-style, above modules) |
| Overlay | `ContentView` (after achievements) |
| Detail eval | `RecordingDetailView.evaluateCoachMomentIfNeeded` |
| Tests | `SpeakUpTests/CoachMomentTests.swift` |

## Signals

| Signal | Celebration? | Surface | Trigger |
|--------|--------------|---------|---------|
| `returnFromLapse` | no | Today | ≥ 5 quiet days, not practiced today; stable id tied to the last practice day means once per absence episode |
| `softLanding` | no | Detail | At least 2 scored sessions; overall &lt; 45 with real words (not a dead mic) |
| `practiceAnniversary` | yes | Overlay | 30 / 100 / 365 days since first recording |
| `firstAxisClear` | yes | Detail | At least 2 scored sessions; dimension hits mastery (85) for the first time |

Care notes never spend the weekly celebration budget. Celebrations cap at **1 per calendar week**.

## Tone / privacy

1. User-facing label is **Coach note** — never "hospitality", "ghosts", or Guidara jargon.
2. No transcript keyword mining. Signals come from scores and dates only.
3. Welcome-back copy never names how many days were missed.
4. Every note is dismissible. Dismiss records delivery; a dismissed celebration still spends the weekly slot so another cannot replace it.
5. Analytics: `milestone(type: coach_moment_<signal>)` only — no transcript text.
6. Detail notes run only for the result reached directly from the recording that just finished. Opening old History or Story recordings is inert.

## Invariants

1. Pure judgement stays in `CoachMomentEngine` — `nonisolated`, injectable `now`, no `ModelContext`. Service owns fetch + pending slots.
2. Additive `UserSettings` only. Empty week key / zero used / empty lists = never shown.
3. Day-keyed delivery ids are capped at 40, return episodes at 10, while anniversary/axis milestones are retained. The current absence id cannot be pushed out by daily notes, and the CloudKit row stays bounded in normal use.
4. First-axis wins persist `CoachDimension.rawValue` on accept **or dismiss** so the toast is once per dimension.
5. One pending note **per surface** (`pendingToday` / `pendingDetail` / `pendingOverlay`). Today eval must not clobber a detail soft-landing. Achievements overlay outranks coach-note overlay.
6. Today evaluates care before celebrations. A welcome-back note beats anniversary confetti when both apply.
7. No new Today home module — transient card like `FriendChallengeCard`, not a customizable block.
8. Soft-landing and first-axis-clear notes replace `NextStepCard`; two adjacent actions are never shown.
9. A pending overlay is never silently replaced by a concurrent Today/detail reload. Leaving a fresh detail **abandons** its pending note: clear presentation state, spend no budget, mark no skill as seen.
10. Streaks do not produce coach-note overlays. Achievements own milestones; Today owns the quiet arrival haptic. One event gets one celebration.
11. Detail eligibility uses `PersonalAverage.Baselines.priorSessionCount + 1`, already loaded before evaluation. Do not add another SwiftData history count.
12. Anniversary acceptance only closes the note. A celebration never turns into a forced recording funnel.

## Cross-links

[today-library.md](./today-library.md) · [recording-detail.md](./recording-detail.md) · [achievements-goals.md](./achievements-goals.md) · [analytics-review.md](./analytics-review.md)
