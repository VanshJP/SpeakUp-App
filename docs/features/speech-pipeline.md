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
| Transcriber | `OnDeviceTranscriber` — Apple `SpeechAnalyzer` (`SpeechTranscriber`; `DictationTranscriber` on iPhone 11-class phones) |
| Pause recovery | `WordTimingRefiner` — pulls tiled word ranges onto the voiced audio |
| Live word capture | `DictationService` (word bank), `LiveTranscriptionService`, `ReadAloudService` |
| Noise / speakers | `SpeechIsolationService` (noise measurement only), `ConversationIsolationService` |
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
3. One detached job (`SpeechService.transcribeTake`): decode `MonoPCM` once → `OnDeviceTranscriber` → `WordTimingRefiner` → `FillerDetectionPipeline` → primary-speaker labeling + noise measurement. Then the scoring leg runs detached: `Task.detached` invokes `SpeechAnalysisPipeline.analyze(...)`.
4. Optional LLM coherence enhance (Apple Intelligence → local llama → skip).
5. On success: `AllowanceGate.consume` (not before).

## Agent gotchas

- Story-linked recordings: feed `Story.content` as `promptText` (story wins over Prompt).
- Exhausted free allowance → `analysisBlockedByAllowance`; resume deferred jobs on foreground / entitlement (serial, capped).
- Never decode analysis blobs on main in list `body` — use `RecordingSummary` / chart points.
- Never `#Predicate` on `Recording.analysis` — ObjC crash inside CoreData SQL gen; proxy via `transcriptionText != nil` (`analyzedRecordingCount`).
- Re-fetch `Recording` by id after long transcription before mutating (user may have deleted it).
- **Feed `SpeechAnalyzer` PCM converted to `bestAvailableAudioFormat`**, never a file (`analyzeSequence(from:)` / `start(inputAudioFile:)`). The analyzer rejects formats it does not list - its own file reader included - with `SFSpeechErrorDomain` 3, "Audio format is not supported". `OnDeviceTranscriber.convert` does it from the take's one `MonoPCM` decode.
- **`SpeechTranscriber` word ranges tile each phrase edge to edge.** A pause lives inside the word before it. Anything that reads gaps between words (pause metrics, filler context, phonation time, MLR) needs `WordTimingRefiner.refine` first; `transcribeTake` runs it before filler tagging.
- **Hesitations need `SpeechTranscriber`.** It keeps "um" and writes "uh" as "ah" (both in `FillerWordList`). `DictationTranscriber` strips them, with or without punctuation, so iPhone 11-class phones (8-core Neural Engine, `SpeechTranscriber.isAvailable == false`) count only word fillers. The analytics dimension `processingPath` says which ran.
- **The simulator cannot transcribe.** Neither transcriber reports a compatible audio format there, so takes fail with "not available on this device". Test scoring on a device; UI work can use `ScreenshotSeeder`.
- The speech model is the system's (`AssetInventory`), shared across apps and usually installed already. `SpeechService.prepareModel()` runs at launch, at take start (`RecordingViewModel.prepareSpeechModel()`), and before every transcription; concurrent calls share one download. Analyzing UI keys "Downloading…" off `isDownloadingModel`.
- The transcriber's only timeout is its own deadline (`30 s + half the take`), raced through a continuation. Never race it in a task group: a group waits for every child before it rethrows, so the timeout could not fire past a wedged call.
- `SpeechAnalyzer` needs no `SFSpeechRecognizer` authorization and has no server path. Every **live** `SFSpeech*RecognitionRequest` (dictation, Read Aloud, the in-take filler counter) still sets `requiresOnDeviceRecognition = true` unconditionally - on-device is a product claim (`APP_STORE_LISTING.md` §3). Never make it conditional on `supportsOnDeviceRecognition`, which reads false while assets install.
- Score philosophy: progressive (short casual ≈ 50–65; solid minute ≈ 75–90; only empty/gibberish ≪ 20).
- Pure scoring types are `nonisolated` — required under MainActor-default isolation (`/docs/AGENT_GOTCHAS.md`). That now includes the pipeline itself plus every engine it calls: `SpeechAnalysisPipeline`, `SpeechScoringEngine`, `PitchAnalysisService`, `TextAnalysisService`, `PromptRelevanceService`, `AudioWaveformGenerator`, `OnDeviceTranscriber`, `WordTimingRefiner`.
- Deletion flows must call `RecordingProcessingCoordinator.cancelProcessing(recordingID:)` **before** removing the recording row. The coordinator keeps a per-recording `Task` handle (`activeTasks`), and `SpeechService.transcribe` forwards that cancel into its detached job and the analyzer (`cancelAndFinishNow`). Best-effort by design — a leg past its last cancellation check still finishes, and every persist re-fetches first.
- The local LLM and transcription no longer share app memory: nothing unloads the LLM before a take, and the LLM has nothing to evict when it loads.
- Do not bring WhisperKit back for fillers. Its filler prompt made the decoder drop whole 30 s windows (the back half of most one-minute takes) after up to six temperature retries per window - that retry loop was the analyzing-screen hang - and `SpeechTranscriber` keeps hesitations without a prompt.

## Cross-links

`/SPEECH.md` · [recording-detail.md](./recording-detail.md) · [monetization.md](./monetization.md) · [stories.md](./stories.md) · [settings.md](./settings.md) (weights / AI model) · `/docs/AGENT_GOTCHAS.md`
