# Settings

## Purpose

Hub that routes to focused settings surfaces (session, analysis, AI, prompts, weights, calibration, data, etc.).

## Key files

| Role | Path |
|------|------|
| Hub | `SpeakUp/Views/Settings/SettingsView.swift` |
| Pages | `ProfileSettingsView`, `SessionDefaultsView`, `AnalysisSettingsView`, `AIModelSettingsView`, `FeedbackSettingsView`, `PromptSettingsView`, `ScoreWeightsView`, `VoiceCalibrationView`, `ReminderSettingsView`, `DataManagementView`, `WordBankView`, `RecordingLookView`, `AnalyticsDiagnosticsView` |
| Lifetime row | `SpeakUp/Views/Paywall/LifetimeStatusRow.swift` |
| VM | `SettingsViewModel.swift` |
| Model | `UserSettings.swift`, `SupportLinks.swift` |

## Invariants

1. iCloud toggle: call `PaywallCoordinator.allow(.iCloudSync)` before enabling preference.
2. Support / privacy / terms URLs from Info.plist (`BT*URL` keys) — hide rows when unset.
3. DEBUG Lifetime override via `EntitlementStore.setDebugOverride` only.
4. Score weights persist on `UserSettings`; defaults in `ScoreWeights.defaults` (`SPEECH.md`).
5. Sheets from Settings: `.appBackground(.subtle)`.
6. `RecordingLookView` is the cosmetic picker: live preview on top, filter strip below, four sections (waveform / button / countdown / canvas) persisting `waveformStyle`, `recordButtonStyle`, `countdownLook`, `countdownBackdrop`. Previews use the real components, never stand-ins. Looks change **form only** — the brand palette is fixed ([ui-design-system.md](./ui-design-system.md)). `countdownBackdrop` paints **only** the prepare countdown (`CountdownOverlayView`); the recording session stays on `AppBackground.recording`. Preview presents a full-screen cover whose bottom-centre stop button dismisses it.
7. `soundPack` (Session Defaults → Cue Sound) sets `ChirpPlayer.shared.pack`. Set it in **both** `SettingsViewModel.saveSettings` and `SpeakUpApp.ensureSettingsExist` — the app-boot assignment is what survives a relaunch.
8. `shareCardTheme` is picked in `ShareCardSheet`, not here ([recording-detail.md](./recording-detail.md)).

## Cross-links

[monetization.md](./monetization.md) · [icloud.md](./icloud.md) · [speech-pipeline.md](./speech-pipeline.md) · [analytics-review.md](./analytics-review.md) · `/SPEECH.md`
