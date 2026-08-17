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
| Share cards | `ShareCardSheet` (picker + preview), `ScoreCardRenderer`, `ProgressCardRenderer`, `SharePresenter`, `SharedPromptLink`, `SharedPromptResolver` |
| Inbound challenge | `SharedChallengeStore`, `FriendChallengeCard` (Today), countdown chrome in `CountdownOverlayView` |

> Note: older docs mentioned `DetailAnalysisTab` — layout evolved into hero / reveal / transcript / playback pieces. Prefer current files above.

## Invariants

1. Resolve `resolvedAudioURL` / file existence **once** into `@State` — not in `body`.
2. `markFirstResultSeen()` only when analysis completed — gates auto-paywall and review.
3. Deferred-by-allowance UI must offer unlock path via paywall; fail-open policy lives in `PaywallCoordinator`.
4. Processing: prefer `RecordingProcessingCoordinator` over ad-hoc parallel jobs.
5. After long transcribe/analyze: coordinator re-fetches by id before write (deleted object trap).
6. Share score / progress cards via `SharePresenter` only (completed-share analytics). Score-card shares that include the prompt also attach a caption with a try-this-prompt URL (`SharedPromptLink`); do not invent a second activity sheet.
7. Prompt text on a share card and in the share URL is opt-in. Scores-only shares must not put the prompt (or `beat`) on the link. Story sessions may show the title on the card but never encode story body into the URL.
8. `ShareCardSheet` is the one share surface: variant tabs (Scores / Challenge) over a live preview, a `ScoreCardTheme` filter strip, then Save / Copy / Share. `.scores` **must** stay the default selection — the default card carries no prompt. Themes change only the card backdrop (all stay dark, so the hero body needs no per-theme colors) and persist to `UserSettings.shareCardTheme`; the render cache is keyed by variant **and** theme. Save and Copy log `share_complete` too; they are the same intent by another route.
9. Share captions are three lines at most (headline, prompt quote, URL). Explanation belongs on the card or in the sheet's subtitle, not in text the recipient reads.

## Cross-links

[speech-pipeline.md](./speech-pipeline.md) · `/SPEECH.md` · [monetization.md](./monetization.md) · [analytics-review.md](./analytics-review.md) · [achievements-goals.md](./achievements-goals.md) · `/docs/AGENT_GOTCHAS.md`
