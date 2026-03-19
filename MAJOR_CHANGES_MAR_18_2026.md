# SpeakUp iOS – Major Changes (Mar 18, 2026)

This document summarizes the major product/engineering updates implemented for the current improvement pass.

## 1) Event Detail Page + Script Editor

- Added a new **Plan Details** section in `EventDetailView` with editable:
  - Event date/time
  - Duration (minutes)
  - Daily practice capacity (minutes/day)
- Added explicit **Save Plan Details** action that persists changes and regenerates prep tasks.
- Wired teleprompter handoff so users can jump directly into recording from event prep.
- Improved script editor affordance in `ScriptEditorView`:
  - Focus-aware visual border
  - “Tap to edit” hint
  - Empty-state placeholder copy

## 2) Whisper Word/Name Dictionary (Synced with Word Bank)

- Updated transcription pipeline so **Word Bank terms now bias Whisper decoding**:
  - `RecordingDetailView` passes `vocabWords` into `SpeechService.transcribe(...)`
  - `SpeechService` forwards preferred terms to `WhisperService`
  - `WhisperService` appends preferred names/terms to its decode prompt conditioning
- Updated Word Bank UX copy to clearly indicate Whisper bias behavior.
- Updated Word Bank input handling to support **names/proper nouns** (e.g. “Vansh”):
  - Removed strict dictionary-word rejection
  - Added case-insensitive dedupe and removal

## 3) Recording Detail View Playback + Gesture Behavior

- Improved transcript word-highlighting sync by replacing cursor-drift logic with a tolerance-aware index resolver (`wordIndexForPlaybackTime`).
- Reduced aggressive swipe-down interaction on playback drawer:
  - Capped drag displacement to partial movement
  - Removed full swipe-to-hide behavior from vertical gesture path
  - Kept expand/collapse as the primary interaction

## 4) AI Coaching Insights Rendering + Deduplication

- Added AI insight sanitation in `LLMService`:
  - Normalizes bullet output
  - Deduplicates repeated tips
  - Limits output to up to 3 unique items
- Updated `RecordingDetailView` AI insight rendering to parse and display markdown/structured list output instead of raw text blobs.

## 5) Clarity Score Recalibration

- Tuned clarity subscore formula in `SpeechService` to be less punitive:
  - More forgiving articulation mapping
  - Softer duration consistency curve
  - Lower hedge penalty impact
  - Added small pace-alignment bonus
- Net effect: clarity is still quality-sensitive but less harsh for natural speaking variance.

## 6) Teleprompter UX Rethink

- Introduced workflow modes in `TeleprompterView`:
  - **Live**: normal rehearsal mode
  - **Pre-Record**: countdown + auto-scroll rehearsal with direct start-recording handoff
  - **External**: explicit mirrored-display/AirPlay guidance + start-recording handoff
- Added recording handoff callback (`onStartRecording`) so teleprompter no longer traps users in a dead-end flow on phone-only usage.

## 7) Today View Practice Cards

- Compacted Practice Tool cards in `TodayView`:
  - Reduced icon footprint
  - Reduced card height
  - Tighter grid spacing
  - Reduced subtitle line usage

## 8) Goals Page Functional Progress Tracking

- Added `GoalProgressService` to compute real progress from recording data.
- Integrated goal refresh in:
  - `GoalsViewModel.loadGoals()`
  - `TodayViewModel.loadActiveGoals()`
- Goal calculations now auto-update for sessions/week, streak, score improvement, filler reduction, and total minutes.

## 9) Learning Path Auto-Checkmark

- Added `CurriculumActivitySignalStore` for activity completion signals (drills, exercises, read-aloud).
- Added auto-completion engine in `CurriculumService`:
  - Infers completion from actual recordings + activity signals
  - Auto-marks matching activities as completed
  - Auto-syncs lesson completion/advancement when all activities are complete
- Hooked signals from real actions:
  - Drill completion (`DrillViewModel`)
  - Warm-up exercise completion (`WarmUpViewModel`)
  - Read Aloud completion (`ReadAloudViewModel`)

## 10) Follow-up Overhaul: Dictation vs Vocab + Event UX + AI Insight Formatting

### Dictation Dictionary separated from Vocab Tracking

- Added a dedicated `dictationBiasWords` field to `UserSettings` and matching helper methods.
- Updated `SettingsViewModel` to maintain separate local state + validation flows for:
  - `vocabWords` (analytics/highlighting)
  - `dictationBiasWords` (Whisper bias only)
- Updated `WordBankView` to include three explicit tabs:
  - **Vocab**
  - **Dictation**
  - **Filler Words**
- Updated transcription path in `RecordingDetailView`:
  - `preferredTerms` now comes from `settings.dictationBiasWords`
  - Vocab tracking remains based on `settings.vocabWords`

### Event pages head-to-toe simplification pass

- Reworked `EventListView` into a simpler flow:
  - Added top summary metrics card
  - Added segment filter (Upcoming / Past / All)
  - Moved archive visibility into a lightweight inline control
  - Removed high-friction sort-chip complexity
- Rebuilt `CreateEventView` from a 3-step wizard into a single, scannable flow:
  - Session type
  - Essentials
  - Optional context
  - Script
  - Create actions
- Refocused `EventDetailView` on fewer high-value sections:
  - Quick actions
  - Editable plan details
  - “Today Focus” task list with optional full timeline expansion
  - Compact recommended tools grid
  - Script-at-a-glance
- Simplified `TeleprompterView` workflow modes to:
  - **Pre-Record**
  - **External Display**
  - with clearer mode subtitles and recording handoff placement
- Updated `ScriptEditorView` to a cleaner top-summary + save-first layout.

### AI Insights markdown rendering cleanup

- Replaced plain markdown-to-`Text` fallback with block-based rendering in `RecordingDetailView`.
- Added line classification for:
  - headings (`#`)
  - bullets (`-`, `*`, `•`, numbered items)
  - paragraphs
- Bullets now render with consistent visual bullet rows and inline markdown parsing per line.

