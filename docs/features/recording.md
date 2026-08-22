# Recording — capture session

## Purpose

Full-screen practice take: countdown → record with live fillers / waveform / framework cues → save `Recording` for later analysis.

## Key files

| Role | Path |
|------|------|
| UI | `SpeakUp/Views/Recording/` — `RecordingView`, `RecordButton`, `TimerDial` / `TimerView` (`TimerView.swift`), `CountdownOverlayView`, `FillerCounterOverlay`, `MicLevelPill` (`RecordingView.swift`), `FrameworkOverlayView` |
| VM | `SpeakUp/ViewModels/RecordingViewModel.swift` + `+AudioMonitoring`, `+Computed`, `+Permissions`, `+RecordingControl`, `+Timer` |
| Audio | `SpeakUp/Services/AudioService.swift` |
| Live fillers | `SpeakUp/Services/LiveTranscriptionService.swift` |
| Coaching audio/haptics | `HapticCoachingService`, `ChirpPlayer` |
| Word workout strip | `VocabStrip` in `RecordingView.swift` — today's spotlight words as chips inside the top bar, below the prompt card. It used to be a floating panel that covered the prompt; toggle it from the session options menu. |
| Waveform gen | `AudioWaveformGenerator` |
| Cosmetic looks | `CircularWaveformView` (`RecordingView.swift`), `RecordButton`, `TimerDial` (`TimerView.swift`), `RecordingBackdropView` + `WaveformStyle` / `RecordButtonStyle` / `TimerLook` / `RecordingBackdrop` (`UserSettings.swift` + `RecordingBackdrop.swift`); all picked in Settings → Recording Look (`RecordingLookView`). Full-screen try-on is `RecordingLookPreview` — it plays countdown then recording, and the record button stops it. |
| Model | `SpeakUp/Models/Recording.swift`, `SpeechFramework.swift`, `RecordingGroup.swift` |

## Flow

1. `ContentView` sets prompt and/or `recordingStoryId`, duration, optional goal, optional `recordingChallenge`.
2. Countdown sheet → `RecordingView` `fullScreenCover`. Friend-challenge links (`source=share`) add countdown chrome and log `practice_start` as `shared_prompt`.
3. Story practice: set `recordingStoryId`, clear `recordingPrompt`.
4. On stop: persist `Recording` (audio/video URL); analysis runs later via coordinator (see speech pipeline).

## Invariants

- User presses every record control (especially onboarding — see `ONBOARDING_VISION.md`).
- High-frequency audio levels must not re-diff the whole screen — pass snapshots into POD subviews (`RecordButtonWaveformStack` pattern).
- Look settings (`waveformStyle`, `recordButtonStyle`, `countdownLook`, `countdownBackdrop`) are read at the call site and passed in as plain values — the components never query settings themselves, so the settings preview can render any style. Wired in recording + drills; onboarding stays on defaults.
- `WaveformStyle.off` renders `EmptyView` with **no frame**, so the record button collapses to its own 80pt instead of centring in an empty 220pt canvas. Any new layout around the waveform must survive it being absent.
- `TimerLook` is orthogonal to `CountdownStyle` (dial shape vs. count up/down).
- `TimerLook` styles **both** halves of a session: the countdown dial and the recording clock (and the drill clock) all render through one `TimerDial`, scaled by `diameter` — 200 on the countdown and while recording, 150 for settings thumbnails. It used to style the countdown only, so the recording screen silently fell back to a plain ring. New timer visuals go in `TimerDial`, never in a call site.
- The countdown and the recording screen are laid out **slot for slot** — prompt on top, dial in the middle at the same `diameter`, actions along the bottom — so the hand-off moves nothing but the prompt card shrinking. Changing one screen's vertical structure means changing the other.
- Top bar = status (`FillerCounterOverlay`, `MicLevelPill`), bottom = controls (record button, hint, coaching cue). The live filler count is status and lived above the record button until it kept shoving it down; don't move controls up or status down.
- Mic activity comes from `AudioService.isHearingInput` — a decaying peak, not `audioLevel > -40`. The raw comparison flips on every gap between words. Both the recording and drill screens read the service property; the decay/floor knobs live in `AudioService`.
- `RecordingBackdrop` is orthogonal to both and paints the **whole session** — prepare countdown (`CountdownOverlayView`), `RecordingView`, and `DrillSessionView`. `.base` resolves to `AppBackground(style: .recording)`, so the default look is unchanged. Do not paint any screen outside a session with it.
- Deep-link `record` clears prior prompt/story/goal context.
- Allowance is **not** consumed at capture time — only after successful analysis (`AllowanceGate.consume`).

## Cross-links

[speech-pipeline.md](./speech-pipeline.md) · [recording-detail.md](./recording-detail.md) · [stories.md](./stories.md) · [monetization.md](./monetization.md) · [vocab-challenge.md](./vocab-challenge.md) · [architecture.md](./architecture.md)

## Focus intent pill

`RecordingView.focusIntentPill` shows the current `CoachPlan` focus in the top bar: area plus technique name during the countdown, area alone once recording starts — mid-take is the wrong moment for a paragraph, but the reminder has to be there because that is the only window in which it can be acted on.

Loaded in its own `.task`, separate from the configure task that auto-starts recording, so resolving it can never delay the countdown. Hidden when the plan is graduating (nothing left to work on).
