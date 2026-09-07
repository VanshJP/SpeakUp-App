# Recording — capture session

## Purpose

Full-screen practice take: countdown → record with live fillers / waveform / framework cues → save `Recording` for later analysis.

## Key files

| Role | Path |
|------|------|
| UI | `SpeakUp/Views/Recording/` — `RecordingView`, `RecordButton`, `TimerDial` / `TimerView` / `SessionDialSlot` / `SessionDial` (`TimerView.swift`), `CountdownOverlayView`, `FillerCounterOverlay`, `MicLevelPill` (`RecordingView.swift`), `FrameworkOverlayView` |
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
- `TimerLook` styles **both** halves of a session: the countdown dial and the recording clock (and the drill clock) all render through one `TimerDial`, scaled by `diameter`. It used to style the countdown only, so the recording screen silently fell back to a plain ring. New timer visuals go in `TimerDial`, never in a call site.
- **No session screen writes a dial `diameter`.** The middle of every session screen is a `SessionDialSlot` (`TimerView.swift`): a greedy `GeometryReader` that takes whatever the top and bottom slots left, targets 80% of that slot's short side (clamped 170–260, never wider than the slot), then picks the largest rung of `SessionDial.ladder` that actually fits via `ViewThatFits(in: .vertical)`. The old `Spacer() / 200pt dial / Spacer()` sized the dial without reference to the room it had — worst with `WaveformStyle.off`, where the controls collapse to 80pt and the dial sat in a ~400pt gap with ~90pt empty on either side — and at accessibility text sizes on a small phone the same fixed number pushed the record button off the bottom. Countdown, recording, drills and the Recording Look try-on all use the slot.
- **The dial is not the only thing in the slot,** and `GeometryReader` does not clip. A framework cue (recording), a mode metric (drills) and a phase label (try-on) share it, which is what the `ViewThatFits` ladder is for: sizing from the slot alone pushed those siblings out over the record button. If you add something to a slot, do not also add a `Spacer` or a fixed height — let the ladder resolve it.
- **Nothing may change the slot's height mid-take.** The slot is `container − topBar − bottomControls`, so anything that grows either one resizes the dial mid-sentence. The coaching cue is an `.overlay` on `bottomControls`, not a row inside it, for exactly this reason — as a row it pushed ~58pt in the moment it fired, shoving the record button down and shrinking the dial. New transient chrome on a session screen is an overlay or it is nothing.
- The countdown and the recording screen are laid out **slot for slot** — prompt on top, dial slot in the middle, actions along the bottom — so the dial never *moves* across the hand-off. It can still change size: the countdown's bottom is two buttons, the recording screen's is a record button wrapped in up to 220pt of waveform, so with a waveform style on the take's dial lands smaller than the countdown's, and with `WaveformStyle.off` they match at the cap. Changing one screen's vertical structure means changing the other.
- **Session screens respect the safe area.** No blanket `.ignoresSafeArea()` on `RecordingView` / `CountdownOverlayView` / `RecordingLookPreview`: every backdrop they can wear (`RecordingBackdropView`, `AppBackground`) already bleeds on its own. Consuming the insets at the top of the screen is what put the countdown's prompt card under the status bar, and it forced every slot to guess with a hard-coded 50pt.
- Top bar = status (`FillerCounterOverlay`, `MicLevelPill`), bottom = controls (record button, hint, coaching cue). The live filler count is status and lived above the record button until it kept shoving it down; don't move controls up or status down.
- The take's focus rides on the **prompt card's meta line** ("Personal Growth · Vocal variety"), not in a pill of its own — two stacked capsules were two rows of chrome for one sentence of context. `focusIntentPill` is the fallback for sessions with no prompt card (story practice, free takes).
- Mic activity comes from `AudioService.isHearingInput`, which **latches**: a take starts green (the peak is primed above the floor, buying ~2.5 s of grace), drops to the amber "No sound" only if nothing at all arrives, and stays green for good once one reading clears `hearingFloor`. The question the indicator answers is "is this mic working", not "is sound arriving in this exact 100 ms" — the earlier raw comparison strobed between words, and the decaying peak that replaced it still dropped out on a long pause, which is the same false alarm arriving more slowly. Latch on the raw `level`, **never** on `inputPeak` (primed to 0, already above the floor). `resetInputConfidence()` clears it on every start / stop / cancel, so the latch never leaks across takes. Both the recording and drill screens read the service property; the knobs live in `AudioService`.
- `RecordingBackdrop` is orthogonal to both and paints the **whole session** — prepare countdown (`CountdownOverlayView`), `RecordingView`, and `DrillSessionView`. `.base` resolves to `AppBackground(style: .recording)`, so the default look is unchanged. Do not paint any screen outside a session with it.
- Deep-link `record` clears prior prompt/story/goal context. Mid-session / onboarding links are ignored (`showingRecording` / `showingCountdown` / `showOnboarding`) — same guards on `story/new`.
- Session Feedback defaults **off** (`sessionFeedbackEnabled`). When on, the recorder still skips the questionnaire for the first analyzed session so activation (baseline → score reveal) is never blocked.
- Allowance is **not** consumed at capture time — only after successful analysis (`AllowanceGate.consume`).
- Capture/save failures are never silent: `RecordingView` says the take did not save, explicitly removes blame, and offers Try Again or Cancel without exposing raw audio errors.

## Cross-links

[speech-pipeline.md](./speech-pipeline.md) · [recording-detail.md](./recording-detail.md) · [stories.md](./stories.md) · [monetization.md](./monetization.md) · [vocab-challenge.md](./vocab-challenge.md) · [architecture.md](./architecture.md)

## Focus intent pill

The current `CoachPlan` focus shows in the top bar: on the prompt card's meta line when there is a prompt, and as `RecordingView.focusIntentPill` when there is not. Area plus technique name during the countdown, area alone once recording starts — mid-take is the wrong moment for a paragraph, but the reminder has to be there because that is the only window in which it can be acted on.

Loaded in its own `.task`, separate from the configure task that auto-starts recording, so resolving it can never delay the countdown. Hidden when the plan is graduating (nothing left to work on).
