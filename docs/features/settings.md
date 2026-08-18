# Settings

## Purpose

Hub that routes to focused settings surfaces (session, analysis, AI, prompts, weights, calibration, data, etc.).

## Key files

| Role | Path |
|------|------|
| Hub | `SpeakUp/Views/Settings/SettingsView.swift` |
| Pages | `ProfileSettingsView`, `SessionDefaultsView`, `AnalysisSettingsView`, `AIModelSettingsView`, `FeedbackSettingsView`, `PromptSettingsView`, `ScoreWeightsView`, `VoiceCalibrationView`, `ReminderSettingsView`, `DataManagementView`, `WordBankView` (incl. daily word workout), `RecordingLookView`, `AnalyticsDiagnosticsView` |
| Lifetime row | `SpeakUp/Views/Paywall/LifetimeStatusRow.swift` |
| VM | `SettingsViewModel.swift` |
| Model | `UserSettings.swift`, `SupportLinks.swift` |

## Invariants

1. iCloud toggle: call `PaywallCoordinator.allow(.iCloudSync)` before enabling preference.
2. Support / privacy / terms URLs from Info.plist (`BT*URL` keys) — hide rows when unset.
3. DEBUG Lifetime override via `EntitlementStore.setDebugOverride` only.
4. Score weights persist on `UserSettings`; defaults in `ScoreWeights.defaults` (`SPEECH.md`).
5. Sheets from Settings: `.appBackground(.subtle)`.
6. `RecordingLookView` is the cosmetic picker: one hero preview on top (countdown dial + recording ring on the chosen backdrop), then four labelled grids — background / waveform / record button / timer — persisting `recordingBackdrop`, `waveformStyle`, `recordButtonStyle`, `countdownLook`. No section tabs and no horizontal strips: every option is visible at once. Previews use the real components, never stand-ins. Looks change **form only** — the brand palette is fixed ([ui-design-system.md](./ui-design-system.md)). The backdrop and the timer look both paint the whole session (countdown **and** recording). `RecordingLookPreview` is a full-screen cover that plays countdown → recording; the record button skips ahead, then stops and dismisses. The stored column is still `UserSettings.countdownBackdrop` (schema is additive-only).
7. `soundPack` (Session Defaults → Cue Sound) sets `ChirpPlayer.shared.pack`. Set it in **both** `SettingsViewModel.saveSettings` and `SpeakUpApp.ensureSettingsExist` — the app-boot assignment is what survives a relaunch.
8. `shareCardTheme` is picked in `ShareCardSheet`, not here ([recording-detail.md](./recording-detail.md)).
9. Daily word workout knobs live on the Vocab tab of `WordBankView`, above the word list: master toggle, words per day, and "Teach new words". Additive `UserSettings` fields; default on. The bank / dictionary / spaced-review source flags are still stored but no longer surfaced — always `true`. See [vocab-challenge.md](./vocab-challenge.md).

## Cross-links

[monetization.md](./monetization.md) · [icloud.md](./icloud.md) · [speech-pipeline.md](./speech-pipeline.md) · [analytics-review.md](./analytics-review.md) · `/SPEECH.md`
