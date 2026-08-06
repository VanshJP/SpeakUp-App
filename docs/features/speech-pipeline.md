# Speech pipeline — transcription & scoring

## Canonical contract

**Read `/SPEECH.md` for algorithms, gates, metrics, subscores, weights, filler pipeline, and LLM post-pass.** That file is the source of truth (historically aliased as `SPEECH_ANALYSIS_DEEP_DIVE.md` — that filename does not exist).

This doc only lists wiring and agent gotchas.

## Key files

| Role | Path |
|------|------|
| Orchestrator | `SpeakUp/Services/SpeechService.swift` |
| Job queue | `SpeakUp/Services/RecordingProcessingCoordinator.swift` |
| Scoring | `SpeakUp/Services/SpeechScoringEngine.swift` |
| Whisper / fallback | `WhisperService`, `DictationService` |
| Isolation | `SpeechIsolationService`, `ConversationIsolationService` |
| Fillers | `FillerDetectionPipeline` |
| Text / relevance / pitch | `TextAnalysisService`, `PromptRelevanceService`, `PitchAnalysisService` |
| LLM | `LLMService`, `LocalLLMService` |
| Models | `SpeakUp/Models/SpeechAnalysis.swift` |
| Runtime UI entry | `SpeakUp/Views/Detail/RecordingDetailView.swift` |

## Runtime sketch

1. Detail (or coordinator) enqueues when `recording.analysis == nil`.
2. Dedupe on `recordingID` inside `RecordingProcessingCoordinator`.
3. Transcription order: isolation → WhisperKit → reload retry → Apple Speech.
4. Primary-speaker labeling → `SpeechService.analyze(...)`.
5. Optional LLM coherence enhance (Apple Intelligence → local llama → skip).
6. On success: `AllowanceGate.consume` (not before).

## Agent gotchas

- Story-linked recordings: feed `Story.content` as `promptText` (story wins over Prompt).
- Exhausted free allowance → `analysisBlockedByAllowance`; resume deferred jobs on foreground / entitlement (serial, capped).
- Never decode analysis blobs on main in list `body` — use `RecordingSummary` / chart points.
- Whisper first load is slow — check service state before assuming failure.
- Score philosophy: progressive (short casual ≈ 50–65; solid minute ≈ 75–90; only empty/gibberish ≪ 20).

## Cross-links

`/SPEECH.md` · [recording-detail.md](./recording-detail.md) · [monetization.md](./monetization.md) · [stories.md](./stories.md) · [settings.md](./settings.md) (weights / AI model)
