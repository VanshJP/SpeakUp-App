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

1. **No analysis decode in list/chart `body`.** Background `ModelContext` → `RecordingSummary` / `ChartRecordingPoint` (`HistoryViewModel.fetchSummaries`, `ProgressChartsView`). Recipe: `/docs/AGENT_GOTCHAS.md` §3.
2. Never `#Predicate { $0.analysis != nil }` — process crash. Proxy with `transcriptionText != nil` when counting analyzed takes.
3. Journal export gated: `PaywallCoordinator.allow(.journalExport)`.
4. Progress / share cards are **not** gated (`PaidFeature.progressCards` exists but is omitted from both `FreeTierPolicy.trial` and `.expired`) — share loop must stay free for acquisition. Shares go through `SharePresenter`.
5. Streak sheet is presentation from Today/History — not a tab.

## Cross-links

[monetization.md](./monetization.md) · [recording-detail.md](./recording-detail.md) · [analytics-review.md](./analytics-review.md) · [speech-pipeline.md](./speech-pipeline.md) · `/docs/AGENT_GOTCHAS.md`
