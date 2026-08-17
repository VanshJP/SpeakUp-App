# Recording — capture session

## Purpose

Full-screen practice take: countdown → record with live fillers / waveform / framework cues → save `Recording` for later analysis.

## Key files

| Role | Path |
|------|------|
| UI | `SpeakUp/Views/Recording/` — `RecordingView`, `RecordButton`, `TimerView`, `CountdownOverlayView`, `FillerCounterOverlay`, `FrameworkOverlayView` |
| VM | `SpeakUp/ViewModels/RecordingViewModel.swift` + `+AudioMonitoring`, `+Computed`, `+Permissions`, `+RecordingControl`, `+Timer` |
| Audio | `SpeakUp/Services/AudioService.swift` |
| Live fillers | `SpeakUp/Services/LiveTranscriptionService.swift` |
| Coaching audio/haptics | `HapticCoachingService`, `ChirpPlayer` |
| Waveform gen | `AudioWaveformGenerator` |
| Cosmetic looks | `CircularWaveformView` (`RecordingView.swift`), `RecordButton`, `CountdownDial` (`CountdownOverlayView.swift`) + `WaveformStyle` / `RecordButtonStyle` / `CountdownLook` (`UserSettings.swift`); all picked in Settings → Recording Look (`RecordingLookView`) |
| Model | `SpeakUp/Models/Recording.swift`, `SpeechFramework.swift`, `RecordingGroup.swift` |

## Flow

1. `ContentView` sets prompt and/or `recordingStoryId`, duration, optional goal, optional `recordingChallenge`.
2. Countdown sheet → `RecordingView` `fullScreenCover`. Friend-challenge links (`source=share`) add countdown chrome and log `practice_start` as `shared_prompt`.
3. Story practice: set `recordingStoryId`, clear `recordingPrompt`.
4. On stop: persist `Recording` (audio/video URL); analysis runs later via coordinator (see speech pipeline).

## Invariants

- User presses every record control (especially onboarding — see `ONBOARDING_VISION.md`).
- High-frequency audio levels must not re-diff the whole screen — pass snapshots into POD subviews (`RecordButtonWaveformStack` pattern).
- Look settings (`waveformStyle`, `recordButtonStyle`, `countdownLook`) are read at the call site and passed in as plain values — the components never query settings themselves, so the settings preview can render any style. Wired in recording + drills; onboarding stays on defaults.
- `CountdownLook` is orthogonal to `CountdownStyle` (dial shape vs. count up/down).
- Deep-link `record` clears prior prompt/story/goal context.
- Allowance is **not** consumed at capture time — only after successful analysis (`AllowanceGate.consume`).

## Cross-links

[speech-pipeline.md](./speech-pipeline.md) · [recording-detail.md](./recording-detail.md) · [stories.md](./stories.md) · [monetization.md](./monetization.md) · [architecture.md](./architecture.md)
