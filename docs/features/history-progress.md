# History, progress, journal, streak

## Purpose

Browse takes, contribution/streak UI, metric charts, then-vs-now replay, PDF journal export.

## Key files

| Area | Path |
|------|------|
| History | `SpeakUp/Views/History/` — `HistoryView`, `ActivityStrip`, `ComparisonView`, `ProgressChartsView` |
| Progress | `SpeakUp/Views/Progress/` — `BeforeAfterReplayView`, `JournalExportView`, `JournalSummaryView` |
| Streak | `SpeakUp/Views/Streak/` — `StreakDetailView`, `FlameAnimationView` |
| VMs | `HistoryViewModel` (`RecordingSummary`), `ComparisonViewModel`, `ProgressReplayViewModel` |
| Services | `JournalExportService`, `ProgressCardRenderer` |
| Model | `ProgressCardData.swift` |

## Invariants

1. **No analysis decode in list/chart `body`.** Background `ModelContext` → `RecordingSummary` / `ChartRecordingPoint`. Fetch only needed columns when possible (`propertiesToFetch`).
2. Journal export gated: `PaywallCoordinator.allow(.journalExport)`.
3. Progress / share cards are **not** gated by default (`PaidFeature.progressCards` exists but omitted from `FreeTierPolicy.default`) — share loop must stay free for acquisition.
4. Streak sheet is presentation from Today/History — not a tab.

## Cross-links

[monetization.md](./monetization.md) · [recording-detail.md](./recording-detail.md) · [analytics-review.md](./analytics-review.md) · [speech-pipeline.md](./speech-pipeline.md)
