# Settings

## Purpose

Hub that routes to focused settings surfaces (session, analysis, AI, prompts, weights, calibration, data, etc.).

## Key files

| Role | Path |
|------|------|
| Hub | `SpeakUp/Views/Settings/SettingsView.swift` |
| Pages | `ProfileSettingsView`, `SessionDefaultsView`, `AnalysisSettingsView`, `AIModelSettingsView`, `FeedbackSettingsView`, `PromptSettingsView`, `ScoreWeightsView`, `VoiceCalibrationView`, `ReminderSettingsView`, `DataManagementView`, `WordBankView`, `AnalyticsDiagnosticsView` |
| Lifetime row | `SpeakUp/Views/Paywall/LifetimeStatusRow.swift` |
| VM | `SettingsViewModel.swift` |
| Model | `UserSettings.swift`, `SupportLinks.swift` |

## Invariants

1. iCloud toggle: call `PaywallCoordinator.allow(.iCloudSync)` before enabling preference.
2. Support / privacy / terms URLs from Info.plist (`BT*URL` keys) — hide rows when unset.
3. DEBUG Lifetime override via `EntitlementStore.setDebugOverride` only.
4. Score weights persist on `UserSettings`; defaults in `ScoreWeights.defaults` (`SPEECH.md`).
5. Sheets from Settings: `.appBackground(.subtle)`.

## Cross-links

[monetization.md](./monetization.md) · [icloud.md](./icloud.md) · [speech-pipeline.md](./speech-pipeline.md) · [analytics-review.md](./analytics-review.md) · `/SPEECH.md`
