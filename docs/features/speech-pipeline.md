# Speech pipeline — transcription & scoring

## Canonical contract

**Read `/SPEECH.md` for algorithms, gates, metrics, subscores, weights, filler pipeline, and LLM post-pass.** That file is the source of truth (historically aliased as `SPEECH_ANALYSIS_DEEP_DIVE.md` — that filename does not exist).

This doc only lists wiring and agent gotchas.

## Key files

| Role | Path |
|------|------|
| Orchestrator | `SpeakUp/Services/SpeechService.swift` |
| Scoring pipeline | `SpeechAnalysisPipeline` (`nonisolated` enum, bottom of `SpeakUp/Services/SpeechService.swift`) |
| Job queue | `SpeakUp/Services/RecordingProcessingCoordinator.swift` |
| Scoring | `SpeakUp/Services/SpeechScoringEngine.swift` |
| Whisper / fallback | `WhisperService`, `SpeechService.transcribeWithAppleSpeech` |
| Live word capture | `DictationService` (word bank), `LiveTranscriptionService`, `ReadAloudService` |
| Isolation | `SpeechIsolationService`, `ConversationIsolationService` |
| Fillers | `FillerDetectionPipeline` |
| Structural repetition | `StructuralRepetitionDetector` → `FillerWord(kind: .structural)` + crutch swaps |
| Vocab matching | `VocabMatcher` — inflected bank + daily spotlight words; `WordSafety` gates adds |
| Text / relevance / pitch | `TextAnalysisService`, `PromptRelevanceService`, `PitchAnalysisService` |
| LLM | `LLMService`, `LocalLLMService` |
| Models | `SpeakUp/Models/SpeechAnalysis.swift` |
| Runtime UI entry | `SpeakUp/Views/Detail/RecordingDetailView.swift` |

## Runtime sketch

1. Detail (or coordinator) enqueues when `recording.analysis == nil`.
2. Dedupe on `recordingID` inside `RecordingProcessingCoordinator`.
3. Transcription order: isolation → WhisperKit → raw-URL retry → reload retry → Apple Speech (`SpeechService.transcribeWithAppleSpeech`, not `DictationService`).
4. Primary-speaker labeling → scoring leg runs detached: `Task.detached` invokes `SpeechAnalysisPipeline.analyze(...)` (the coordinator's old `DispatchQueue.global` bridge is gone — under MainActor-default isolation it compiled clean and still hopped to the main actor).
5. Optional LLM coherence enhance (Apple Intelligence → local llama → skip).
6. On success: `AllowanceGate.consume` (not before).

## Agent gotchas

- Story-linked recordings: feed `Story.content` as `promptText` (story wins over Prompt).
- Exhausted free allowance → `analysisBlockedByAllowance`; resume deferred jobs on foreground / entitlement (serial, capped).
- Never decode analysis blobs on main in list `body` — use `RecordingSummary` / chart points.
- Never `#Predicate` on `Recording.analysis` — ObjC crash inside CoreData SQL gen; proxy via `transcriptionText != nil` (`analyzedRecordingCount`).
- Re-fetch `Recording` by id after long transcription before mutating (user may have deleted it).
- Whisper first load is slow — check service state before assuming failure.
- Every `SFSpeech*RecognitionRequest` in the app sets `requiresOnDeviceRecognition = true` unconditionally. On-device is a product claim (`APP_STORE_LISTING.md` §3), so an unavailable recognizer must fail rather than fall back to Apple's servers. Never make it conditional on `supportsOnDeviceRecognition` — that flag reads false while assets install.
- Lowering `DecodingOptions.noSpeechThreshold` makes WhisperKit drop *more* audio, one whole 30 s window at a time, with no error.
- Score philosophy: progressive (short casual ≈ 50–65; solid minute ≈ 75–90; only empty/gibberish ≪ 20).
- Pure scoring types are `nonisolated` — required under MainActor-default isolation (`/docs/AGENT_GOTCHAS.md`). That now includes the pipeline itself plus every engine it calls: `SpeechAnalysisPipeline`, `SpeechScoringEngine`, `PitchAnalysisService`, `TextAnalysisService`, `PromptRelevanceService`, `AudioWaveformGenerator`.
- Deletion flows must call `RecordingProcessingCoordinator.cancelProcessing(recordingID:)` **before** removing the recording row. The coordinator keeps a per-recording `Task` handle (`activeTasks`), so cancel actually stops the work instead of only striking the id from the dedupe set; best-effort by design — a leg past its last cancellation check still finishes, and every persist re-fetches first.
- The Whisper stall watchdog works because `DecodeHeartbeat` carries a one-way abort flag that WhisperKit's per-token transcription callback checks: cancelling the awaited task alone never reaches WhisperKit internals, so without the flag a watchdog timeout abandoned the await but left a zombie decode running while the semaphore let the next caller in.

## Cross-links

`/SPEECH.md` · [recording-detail.md](./recording-detail.md) · [monetization.md](./monetization.md) · [stories.md](./stories.md) · [settings.md](./settings.md) (weights / AI model) · `/docs/AGENT_GOTCHAS.md`
