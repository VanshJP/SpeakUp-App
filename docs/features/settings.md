# Settings

## Purpose

Hub that routes to focused settings surfaces (session, analysis, AI, prompts, weights, calibration, data, etc.).

## Key files

| Role | Path |
|------|------|
| Hub | `SpeakUp/Views/Settings/SettingsView.swift` |
| Pages | `ProfileSettingsView`, `TodayHomeCustomizeView` (Today Layout), `SessionDefaultsView`, `AnalysisSettingsView`, `AIModelSettingsView`, `FeedbackSettingsView`, `PromptSettingsView`, `ScoreWeightsView`, `VoiceProfileView`, `VoiceCalibrationView`, `ReminderSettingsView`, `DataManagementView`, `WordWorkoutSettingsView`, `WordBankView`, `RecordingLookView`, `AnalyticsDiagnosticsView` |
| Privacy & data | `SpeakUp/Views/Settings/PrivacyDataView.swift` |
| VM | `SettingsViewModel.swift` |
| Model | `UserSettings.swift`, `SupportLinks.swift` |

## Invariants

1. iCloud toggle flips freely — no paid gate during the beta ([monetization.md](./monetization.md)).
2. Support / privacy / terms URLs from Info.plist (`BT*URL` keys) — hide rows when unset.
3. DEBUG Lifetime override via `EntitlementStore.setDebugOverride` only.
4. Score weights persist on `UserSettings`; defaults in `ScoreWeights.defaults` (`SPEECH.md`).
5. Sheets from Settings: `.appBackground(.subtle)`.
6. `RecordingLookView` is the cosmetic picker: one hero preview on top (countdown dial + recording ring on the chosen backdrop), then four labelled grids — background / waveform / record button / timer — persisting `recordingBackdrop`, `waveformStyle`, `recordButtonStyle`, `countdownLook`, `countdownStyle`. Timer Direction (count up / count down) lives here, not in Session Defaults — one dial configured on two screens. No section tabs and no horizontal strips: every option is visible at once. Previews use the real components, never stand-ins. Looks change **form only** — the brand palette is fixed ([ui-design-system.md](./ui-design-system.md)). The backdrop and the timer look both paint the whole session (countdown **and** recording). `RecordingLookPreview` is a full-screen cover that plays countdown → recording; the record button skips ahead, then stops and dismisses. The stored column is still `UserSettings.countdownBackdrop` (schema is additive-only).
7. `soundPack` (Session Defaults → Cue Sound) sets `ChirpPlayer.shared.pack`. Set it in **both** `SettingsViewModel.saveSettings` and `SpeakUpApp.ensureSettingsExist` — the app-boot assignment is what survives a relaunch.
8. `shareCardTheme` is picked in `ShareCardSheet`, not here ([recording-detail.md](./recording-detail.md)).
9. Daily word workout has its own hub row (**Word Workout** → `WordWorkoutSettingsView`), holding `VocabChallengeSettingsCard`: master toggle, words per day, "Teach new words". It is not inside `WordBankView` — the workout is the feature and the bank is one of its inputs, so burying the knobs above a word list two levels down had it backwards. `WordBankView` is now **Word Lists** (vocab / dictation / fillers) and stays one tabbed screen: the three tabs share a pinned bottom input bar and one `DictationService`, so splitting them into separate screens would triplicate both. Additive `UserSettings` fields; default on. The bank / dictionary / spaced-review source flags are still stored but no longer surfaced — always `true`. See [vocab-challenge.md](./vocab-challenge.md).

10. Voice profile lives on `VoiceProfileView`, reached from **Analysis**, not Data Management. It is an input to scoring — Auto Pace Target learns from it — not data hygiene, and filing it beside "Clear All Data" hid it. `DataManagementView` is reset-settings and clear-all-data only, and its hub subtitle says exactly that: there is no export on that screen (journal export is History → Progress → More).

11. **Today Layout** (`TodayHomeCustomizeView`, hub row under You) edits `UserSettings.todayHomeLayoutRaw`. Same editor as Today's customize sheet; push with `showsDoneButton: false`. See [today-library.md](./today-library.md).

## Cross-links

[monetization.md](./monetization.md) · [icloud.md](./icloud.md) · [speech-pipeline.md](./speech-pipeline.md) · [analytics-review.md](./analytics-review.md) · `/SPEECH.md`
