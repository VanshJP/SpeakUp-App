# Recording detail — analyze & reveal UI

## Purpose

After a take: staged analyzing, score reveal, transcript / playback / coaching, next steps. Marks first completed result (unlocks auto-paywall + review eligibility).

## Key files

| Role | Path |
|------|------|
| Root | `SpeakUp/Views/Detail/RecordingDetailView.swift` |
| Stages | `AnalyzingView`, `ScoreHeroCard`, `ScoreRevealView` |
| Playback | `PlaybackDrawer`, `RecordingDetailPlaybackViewModel` |
| Transcript | `TranscriptViews`, `TranscriptExcerptCard`, `WPMChartView` |
| Coaching / next | `CoachingTipsView`, `NextStepCard`, `ListenBackEncouragementView` |
| First-run setup | `FirstRecordingSetupSheet` (post-onboarding, after first score) |
| Share cards | `ScoreCardRenderer`, `ProgressCardRenderer`, `SharePresenter` |

> Note: older docs mentioned `DetailAnalysisTab` — layout evolved into hero / reveal / transcript / playback pieces. Prefer current files above.

## Invariants

1. Resolve `resolvedAudioURL` / file existence **once** into `@State` — not in `body`.
2. `markFirstResultSeen()` only when analysis completed — gates auto-paywall and review.
3. Deferred-by-allowance UI must offer unlock path via paywall; fail-open policy lives in `PaywallCoordinator`.
4. Processing: prefer `RecordingProcessingCoordinator` over ad-hoc parallel jobs.

## Cross-links

[speech-pipeline.md](./speech-pipeline.md) · `/SPEECH.md` · [monetization.md](./monetization.md) · [analytics-review.md](./analytics-review.md) · [achievements-goals.md](./achievements-goals.md)
