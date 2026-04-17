# CLAUDE.md

Guidance for Claude Code / Augment Agent on the SpeakUp iOS project. This file and `AGENTS.md` are the same file (AGENTS.md is a symlink).

## Persona — Smart Caveman (full mode)

All AI responses in this project default to **Smart Caveman, full intensity**.

- Drop articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging.
- Fragments OK. Short synonyms (big not extensive, fix not "implement a solution for"). Technical terms exact. Code blocks unchanged. Errors quoted exact.
- Pattern: `[thing] [action] [reason]. [next step].`
- Auto-clarity exceptions: destructive action warnings, multi-step sequences where fragment order risks misread, explicit user confusion. Resume caveman after clear part done.
- Never write commits/PRs/code comments in caveman — normal English for persisted artifacts.
- User may switch with `/caveman lite|full|ultra` or `stop caveman`. Level persists until changed.

## Workflow — **AI MUST NOT BUILD OR TEST**

**Hard rule:** the AI agent does not run iOS builds, does not run simulators, does not run automated tests, does not invoke `xcodebuild`, `xcrun simctl`, `idb`, XCUITest, or any emulator/device interaction. The developer handles all build + test loops independently.

Do:
- Edit Swift source, markdown, configuration.
- Use `codebase-retrieval`, `view`, and `grep` to understand code before editing.
- Trace downstream impact of every edit (callers, subclasses, schemas, viewmodels).
- When changes are complete, hand off to the developer with a clear summary of what changed and what should be built/tested.

Do not:
- Run `xcodebuild`, `xcrun`, `idb`, `simctl`, screenshot automation, accessibility trees.
- Launch long-running processes to verify compile.
- Install dependencies without explicit permission (use `xcodebuild -resolvePackageDependencies` etc. only when asked).
- Loop on build errors — surface any suspected error, let the developer confirm.

If the user explicitly asks "build it" or "run tests," still defer: respond with the exact commands the developer should run, don't execute them.

## Project Overview

SpeakUp = native iOS speech practice app. SwiftUI + SwiftData + WhisperKit. On-device transcription, multi-dimensional speech scoring, optional on-device LLM coherence pass. Features: recording, drills, warm-ups, confidence tools, structured curriculum, user-authored Stories (rich-text scripts), Read-Aloud passages with pronunciation scoring, social challenges, journal PDFs, achievements, iCloud sync, widgets.

Bundle id: `com.vansh.SpeakUpMore`. Deployment: iOS 17+. Liquid glass effects activate on iOS 26+.

## Architecture

**MVVM + Services** with `@Observable` (iOS 17+):
```
View (SwiftUI) → ViewModel (@Observable) → Service (@Observable) → SwiftData Models
```

### Layer responsibilities

- **Models/** — SwiftData entities: `Recording`, `Prompt`, `UserSettings`, `UserGoal`, `Achievement`, `CurriculumProgress`, `RecordingGroup`, `Story`, `StoryFolder`. Pure structs / value types: `SpeechAnalysis` (metrics + `EnhancedSpeechMetrics` + subscores + scoring), `DrillMode`, `WarmUpExercise`, `ConfidenceExercise`, `SocialChallenge`, `DailyChallenge`, `SpeechFramework`, `CurriculumModels`, `LessonContent`, `ReadAloudPassage`, `FillerWordList`, `UserModels`.
- **Services/** — `@Observable`, no UI, own error enum. Current roster:
  - **Transcription & audio:** `SpeechService` (orchestrator), `WhisperService` (WhisperKit), `AudioService` (AVFoundation record/play/metering), `LiveTranscriptionService` (real-time fillers), `DictationService` (Apple Speech fallback), `SpeechIsolationService` (on-device AVAudioEngine voice isolation), `ConversationIsolationService` (primary-speaker labeling when multi-speaker), `AudioWaveformGenerator`.
  - **Analysis pipeline:** `SpeechScoringEngine` (subscores + overall + gates), `TextAnalysisService` (authority, hedges, power words, sentence structure, coherence), `PromptRelevanceService` (keyword + semantic + sentence alignment), `PitchAnalysisService` (vDSP autocorrelation F0 contour), `FillerDetectionPipeline` (shared pause-aware filler tagging for Whisper / Apple Speech / live).
  - **LLM:** `LLMService` (Apple Intelligence / FoundationModels front-door + memory-pressure monitor), `LocalLLMService` (llama.cpp via `LlamaSwift` — download, load, generate on devices without Apple Intelligence), `StoryTaggingService` (conservative LLM tag extraction for Stories), `RecordingProcessingCoordinator` (idempotent per-recording transcribe → analyze → LLM enhance job queue).
  - **Practice & coaching:** `HapticCoachingService`, `ChirpPlayer`, `CoachingTipService`, `WeakAreaService`, `DailyChallengeService`, `WeeklyProgressService`, `CurriculumService`, `CurriculumActivitySignalStore`, `GoalProgressService`, `AchievementService`.
  - **Read-Aloud:** `ReadAloudService` (scores delivered passage vs reference), `PronunciationService` (AVSpeechSynthesizer + UIReferenceLibrary dictionary lookups).
  - **Platform / IO:** `NotificationService`, `ExportService` (UIActivityViewController share), `ScoreCardRenderer` (UIKit-drawn shareable PNG), `JournalExportService` (PDF), `SocialChallengeService` (deep-link challenges), `PromptCSVService` (bulk prompt import/export), `ICloudStorageService` (audio file migration + CloudKit sync preference resolution), `WidgetDataProvider` (App Group shared data).
- **ViewModels/** — `@MainActor @Observable`. Own UI state, call services, never import SwiftData types: `TodayViewModel`, `RecordingViewModel` (split across `+AudioMonitoring`, `+Computed`, `+Permissions`, `+RecordingControl`, `+Timer`), `HistoryViewModel`, `SettingsViewModel`, `OnboardingViewModel`, `PromptWheelViewModel`, `ComparisonViewModel`, `ProgressReplayViewModel`, `DrillViewModel`, `WarmUpViewModel`, `CurriculumViewModel`, `ReadAloudViewModel`, `RecordingDetailPlaybackViewModel`, `StoriesViewModel`.
- **Views/** — grouped by feature (see table below). Shared pieces in `Components/`.
- **Theme/** — `AppColors`, `GlassStyles`, `AppBackground`. All UI uses the glassmorphism system — no raw colors or inline styling.
- **Extensions/** — `Date+Helpers.swift`, `Haptics.swift`, `View+Glass.swift` (iOS 26 liquid glass).
- **Data/** — `DefaultPrompts`, `DefaultWarmUps`, `DefaultConfidenceExercises`, `DefaultCurriculum`, `DefaultReadAloudPassages`, `DefaultFeedbackQuestions`, `SchemaVersioning` (V1 → V16).
- **SpeakUpWidget/** — WidgetKit target. Widgets: `DailyPromptWidget`, `DailyChallengeWidget`, `QuickPracticeWidget`, `QuickStoryWidget`, `StatsRingWidget`, `StreakWidget`, `WeeklyProgressWidget`. Reads via App Group from `WidgetDataProvider`.

### View groups

| Folder | Key files | Purpose |
|--------|-----------|---------|
| `Today/` | `TodayView`, `DailyChallengeCard`, `WeeklyProgressCard`, `StoryPromptCard` | Home — stats rings, prompt card, quick-access toolbar, daily challenge, weekly progress, story prompt shortcut |
| `Practice/` | `PracticeHubView` | **Library tab root** — unified browser across prompts, stories, warm-ups, drills, read-aloud |
| `Prompts/` | `AllPromptsView`, `AddPromptView`, `BatchAddPromptsView` | Browse / add / CSV-import prompts |
| `Stories/` | `StoriesListView`, `StoryDetailView`, `StoryEditorView`, `StoryFolderBar`, `StoryFolderEditorSheet` | User-authored rich-text scripts in folders; link Stories to recordings for script-aware relevance scoring |
| `ReadAloud/` | `ReadAloudSelectionView`, `ReadAloudSessionView`, `ReadAloudResultView`, `DictionaryView`, `WordDetailSheet` | Read-aloud practice with pronunciation score + word-level dictionary |
| `Recording/` | `RecordingView`, `RecordButton`, `TimerView`, `CountdownOverlayView`, `FillerCounterOverlay`, `FrameworkOverlayView` | Full-screen recording; live fillers, framework cues, circular waveform |
| `Detail/` | `RecordingDetailView`, `AnalyzingView`, `DetailAnalysisTab`, `CoachingTipsView`, `WPMChartView`, `ListenBackEncouragementView`, `ScoreCardPreview`, `FirstRecordingSetupSheet` | Post-recording analysis; tabbed scores / transcript / waveform / tips |
| `History/` | `HistoryView`, `ComparisonView`, `ProgressChartsView` | Contribution graph, streaks, searchable list, first-vs-latest, charted progress |
| `Achievements/` | `AchievementGalleryView`, `AchievementUnlockedView` | Grid + confetti celebrations (presented as sheet) |
| `Goals/` | `GoalsView` | Goal management with templates + `GoalProgressService` |
| `Curriculum/` | `CurriculumView`, `CurriculumProgressCard`, `LessonDetailView`, `LessonContentView`, `LessonCompletionView`, `PracticeResultsCard` | **Learn tab root** — weekly phases, lessons, signal-driven progression |
| `WarmUp/` | `WarmUpListView`, `WarmUpExerciseView`, `BreathingAnimationView` | Breathing / Tongue Twisters / Vocal / Articulation; can be linked to a Story |
| `Drills/` | `DrillSelectionView`, `DrillSessionView`, `DrillResultView` | Filler Elimination / Pace Control / Pause Practice / Impromptu Sprint; can be linked to a Story |
| `Confidence/` | `ConfidenceToolsView`, `ConfidenceExerciseView` | Calming / Visualization / Progressive / Affirmation |
| `Progress/` | `BeforeAfterReplayView`, `JournalExportView`, `JournalSummaryView` | Then-vs-Now replay, PDF journal export |
| `Social/` | `ChallengeShareView`, `ChallengeAcceptView` | Deep-link friend challenges |
| `Settings/` | `SettingsView`, `SessionDefaultsView`, `AnalysisSettingsView`, `AIModelSettingsView`, `FeedbackSettingsView`, `PromptSettingsView`, `ScoreWeightsView`, `VoiceCalibrationView`, `ReminderSettingsView`, `DataManagementView`, `WordBankView` | Fully split settings surfaces |
| `PromptWheel/` | `PromptWheelView` | Spinning random prompt selector |
| `Onboarding/` | `OnboardingView`, `OnboardingPageView` | First-launch flow |
| `Components/` | `GlassCard`, `GlassButton`, `RingStatsView`, `ConfettiView`, `FlowLayout`, `PersistentTextField`, `RichTextEditor`, `PracticeHistoryChart` | Shared glass-styled building blocks |

### Entry point

`SpeakUpApp.swift` — builds `ModelContainer` over `Recording`, `Prompt`, `UserGoal`, `UserSettings`, `Achievement`, `CurriculumProgress`, `RecordingGroup`, `Story`, `StoryFolder`. CloudKit sync toggled via `ICloudStorageService.resolvedSyncEnabledPreference`; falls back to local-only then in-memory if container creation fails. Injects `SpeechService`, `AudioService`, `LLMService` via `@Environment`. Seeds prompts, settings, achievements, curriculum progress, story folders concurrently. Background tasks: legacy URL migration, iCloud file migration, Whisper preload, local LLM auto-load.

### Navigation

5-tab layout in `ContentView.swift` (iOS 17 `Tab { }` API). `AppTab` enum owns titles + SF Symbols:

| Tab | Icon | Root View |
|-----|------|-----------|
| Today | `mic.badge.plus` | `TodayView` |
| Library | `books.vertical.fill` | `PracticeHubView` |
| History | `clock.fill` | `HistoryView` → `RecordingDetailView` |
| Learn | `book` | `CurriculumView` |
| Settings | `gearshape` | `SettingsView` |

Achievements moved off the tab bar — presented as a sheet from Today. Global overlays/sheets at `ContentView`: countdown, recording `fullScreenCover`, prompt wheel, goals, warm-ups (optionally with `sourceStory`), drills (optionally with `sourceStory`), confidence tools, before/after replay, journal export, read-aloud selection, story editor, achievement unlock, onboarding `fullScreenCover`, challenge accept `fullScreenCover`.

Deep link schemes:
- `speakup://record?prompt=<id>` — start recording, optionally pre-fill prompt
- `speakup://challenge?...` — accept incoming social challenge
- `speakup://story` / `speakup://story/new` — open Library / story editor

## Speak Algorithm (speech scoring pipeline)

Source-of-truth file: `SPEECH_ANALYSIS_DEEP_DIVE.md`. Summary below for context injection.

### Design philosophy
Scores are progressive and achievable. 20s casual speech → 50-65. Solid 60s speech → 75-90. Only gibberish, silence, or near-empty speech scores below 20.

### Canonical files
`SpeechService.swift`, `SpeechScoringEngine.swift`, `TextAnalysisService.swift`, `PromptRelevanceService.swift`, `SpeechIsolationService.swift`, `ConversationIsolationService.swift`, `FillerDetectionPipeline.swift`, `PitchAnalysisService.swift`, `LLMService.swift`, `RecordingProcessingCoordinator.swift`, `Models/SpeechAnalysis.swift`. Runtime wiring in `RecordingDetailView`.

### Runtime sequence
1. `RecordingDetailView.task` loads recording + settings.
2. `transcribeIfNeeded()` runs only when `transcriptionText == nil && analysis == nil`.
3. Transcription backend order: speech isolation → WhisperKit → reload retry → Apple Speech fallback.
4. `ConversationIsolationService` labels primary-speaker words.
5. `SpeechService.analyze(...)` computes base analysis + enhanced metrics + subscores + overall.
6. `enhanceCoherenceIfNeeded()` runs optional LLM post-pass (Apple Intelligence → local llama → skip).
7. `RecordingProcessingCoordinator` guards against duplicate concurrent jobs per `recordingID`.

### Hard gates (applied in order)
1. **Zero-score gate:** `totalWords == 0 || nonFillerWordCount == 0` → overall `0`.
2. **Substance multiplier:** graduated 0.10× – 1.0× based on substance score.
3. **Gibberish gate:** graduated cap at ≤8 / ≤15 / ≤30 based on 5-signal confidence.

### Enhanced metrics (`SpeechScoringEngine.computeEnhancedMetrics`)
- **PTR** (voiced time / duration), ideal 0.45–0.80.
- **Articulation Rate** (WPM during voiced time), ideal 100–200.
- **MLR** (avg words between pauses), MLR ≥ 8 = fluent.
- **MATTR** (50-word sliding TTR), 0.72+ = full marks.
- **Substance Score** (word count + duration + MATTR + density + MLR).
- **Fluency Score** (PTR + MLR + articulation rate).
- **Lexical Sophistication** (MATTR + word length + NLEmbedding rarity).
- **Gibberish Confidence** (5-signal graduated 0–1).

### Substance multiplier curve
| Substance | Multiplier | Effect |
|-----------|-----------|--------|
| 0–10 | 0.10–0.25 | Gibberish / empty collapse |
| 10–30 | 0.25–0.65 | Very short, penalized |
| 30–50 | 0.65–0.88 | Short speech, moderate penalty |
| 50–75 | 0.88–0.97 | Adequate, slight penalty |
| 75–100 | 0.97–1.00 | Full-length, near-full score |

### Subscores (`calculateSubscores`)
Four required + up to five optional.

1. **Clarity** — blend VFR articulation + ASR confidence + duration consistency + authority + hedge penalty + pace alignment. Weights redistribute when one articulation source is absent. Neutral anchor 65 under degraded reliability.
2. **Pace** — Gaussian around target WPM (sigma 55). Adaptive weighting with rate variation + fluency when present.
3. **Filler Usage** — effective ratio = fillerRatio + hedge + weak phrase. Curve `100 × max(0, 1 − log₂(1 + ratio × 8))`.
4. **Pause Quality** — base 72, rewards strategic medium/long pauses, penalizes long hesitations (capped at 4), low-filler bonus, frequency band 3–18 pauses/min.
5. **Delivery** *(optional)* — energy + monotone + content density + emphasis + arc + engagement.
6. **Vocal Variety** *(optional)* — pitch + volume + rate + pitch-energy correlation (from `PitchAnalysisService`).
7. **Vocabulary** *(optional)* — complexity score + word bank bonus + power words bonus + MATTR blend.
8. **Structure** *(optional)* — sentence analysis + rhetoric / transition / conciseness / engagement.
9. **Relevance** *(optional)* — prompt mode uses keyword + semantic + sentence alignment; free-practice uses 5-signal coherence. Story-linked recordings feed `Story.content` as promptText instead of `Prompt.text`, so relevance reflects script fidelity.

### Overall score
Weighted average of included subscores (weights normalized to 1.0) → substance multiplier → gibberish gate → optional LLM coherence post-pass.

### Default weights (`ScoreWeights.defaults`)
clarity 0.18, pace 0.12, filler 0.14, pause 0.12, vocalVariety 0.12, delivery 0.10, vocabulary 0.08, structure 0.08, relevance 0.06. User-tunable in `ScoreWeightsView`.

### Filler detection (`FillerDetectionPipeline`)
Shared between WhisperService, SpeechService, LiveTranscriptionService. Pause threshold 0.3s, sentence boundary 0.8s. Converts `RawWordTiming` → `TranscriptionWord` with filler flags. Consumes `FillerWordList` (default + user word bank).

### LLM post-pass
`LLMService` picks backend: Apple Intelligence (FoundationModels) → `LocalLLMService` (LlamaSwift, GGUF model download) → none. Monitors memory pressure and cancels generation on warning/critical. Output: `CoherenceResult { score, topicFocus, logicalFlow, reason }` folded into the relevance subscore when available.

## UI Design System (follow this for all new views)

### Aesthetic philosophy
Deep-navy glassmorphism, layered depth, subtle light. Every surface is translucent frosted glass over a dark gradient — no opaque cards, no flat fills, no system backgrounds. Cards float above radial ambient light (teal top-right, indigo bottom-left, cyan center-ish). Content is primarily white on glass; tint comes through material, not opaque fills. On iOS 26+ the system's Liquid Glass effect (`.glassEffect`) is adopted where supported; iOS 17–25 falls back to `.ultraThinMaterial` with inner glow + fine white stroke at the top edge. Motion is restrained: `.spring(response: 0.3)` or `.easeInOut(duration: 0.2)`.

Tab bar is tinted white (`.tint(.white)`), navigation titles inline, color scheme locked to `.dark` (`preferredColorScheme(.dark)`).

### Background — `AppBackground`
Layered `ZStack` with radial gradient orbs on a near-black navy base (`rgb: 0.035, 0.04, 0.09`) + a primary navy gradient wash:
- **`.primary`** — default for all tabs. Teal orb top-right (12%), indigo orb bottom-left (9%), cyan glow center (4%).
- **`.recording`** — darker navy, stronger teal (18%) and cyan (6%) for focused recording sessions.
- **`.subtle`** — slightly lighter navy for sheets and detail views.

Apply via `.appBackground(.primary)`. Every screen must have an `AppBackground` — never use plain `Color` or system backgrounds.

### Glass surfaces — `GlassStyles`
All cards, buttons, and containers use `.ultraThinMaterial` as the base. Never use opaque backgrounds.

**Cards:**
- `.glassCard(cornerRadius:tint:)` — standard card. `ultraThinMaterial` + optional color tint + white inner glow at top edge + subtle top stroke + shadow (`black 20%, radius 8, y:3`). Default corner radius: 16.
- `GlassCard { }` — wrapper view applying the glass card modifier. Use this for most content blocks.
- `FeaturedGlassCard` — hero/highlight card with a gradient tint overlay. Use for primary CTAs and featured content.
- `StatCard` — compact stat display card.
- `ScoreDisplayCard` — score presentation with colored accents.
- `EmptyStateCard` — centered icon + message for empty lists.

**Buttons:**
- `GlassButton(title:icon:style:size:action:)` — 5 styles:
  - `.primary` — teal gradient capsule (main CTAs)
  - `.secondary` — `ultraThinMaterial` capsule (secondary actions)
  - `.outline` — teal border, clear fill
  - `.ghost` — clear fill, no border (tertiary)
  - `.danger` — red fill (destructive actions)
- `GlassIconButton` — circular icon-only button.
- Sizes: `.small`, `.medium`, `.large`.

**Modifiers:**
- `.glassCard(cornerRadius:tint:)` — apply glass card styling to any view
- `.glassBackground(cornerRadius:)` — simple `ultraThinMaterial` background
- `.glassSegmented()` — segmented control background
- `.animatedGlassBorder(cornerRadius:lineWidth:)` — rotating angular gradient border
- `.shimmer()` — sweep highlight animation for loading states
- `.glow(color:radius:)` — static double-shadow glow
- `.pulsingGlow(color:isActive:)` — animated pulsing shadow
- `.liquidGlass(tint:)` — native `.glassEffect()` on iOS 26+, falls back to `ultraThinMaterial`
- `.prominentGlass()` — interactive glass effect on iOS 26+

### Colors — `AppColors`
All colors come from `AppColors`. Never use raw `Color.blue`, `Color.gray`, etc.

| Token | Value | Usage |
|-------|-------|-------|
| `.primary` | Muted teal `#0D8488` | Brand color, primary buttons, progress rings, active states |
| `.accent` | Warm gray `#64748B` | Secondary text, subtle UI elements |
| `.success` | Green | Positive scores, completed states |
| `.warning` | Orange | Filler words, medium scores, streaks |
| `.error` | Red | Recording indicator, danger actions, low scores |
| `.info` | Blue | Informational badges |
| `.recording` | Red | Active recording states |
| `.recordingPulse` | Red 30% | Recording button pulse ring |

**Score colors** — `AppColors.scoreColor(for:)`: red (0-39), orange (40-59), yellow (60-79), green (80-100). Also `scoreGradient(for:)` for linear gradient fills.

**Glass tints** — used as card tint overlays:
- `.glassTintPrimary` — teal 10% (default cards)
- `.glassTintAccent` — white 5% (neutral cards)
- `.glassTintWarning` — orange 10% (warning/filler cards)
- `.glassTintError` — red 10% (error/danger cards)
- `.glassTintSuccess` — green 10% (success/completed cards)

**Other color functions:**
- `difficultyColor(_:)` — easy=green, medium=orange, hard=red
- `categoryColor(_:)` — maps prompt categories to distinct colors
- `contributionColor(intensity:)` — gray-to-green for the activity heatmap
- `Color(hex:)` — hex string initializer

### Typography patterns
Use system fonts with these conventions:
- Screen titles: `.title2.bold()` or `.title3.bold()`
- Section headers: `.headline` via `GlassSectionHeader(icon:title:)`
- Body text: `.body` or `.subheadline`
- Captions/metadata: `.caption` or `.footnote` with `.secondary` foreground
- Metric values: `.system(size: 28-36, weight: .bold, design: .rounded)` for large numbers
- Always `.foregroundStyle(.white)` for primary text on glass surfaces

### Spacing & layout conventions
- Card padding: 16-20pt internal padding
- Card spacing: 16pt between cards in scroll views
- Section spacing: 24pt between major sections
- Screen edge padding: `.padding(.horizontal, 20)` on scroll content
- Corner radii: 16pt for cards, 12pt for inner elements, 25pt+ for capsule buttons
- Use `LazyVStack(spacing: 16)` for scrolling card lists inside `ScrollView`

### Haptics — `Haptics`
Use typed haptic feedback for interactions:
- `Haptics.light()` — subtle taps (pill selection, toggles)
- `Haptics.medium()` — button presses
- `Haptics.heavy()` — significant actions (start recording)
- `Haptics.success()` — completion, unlock
- `Haptics.warning()` — caution states
- `Haptics.error()` — failures
- `Haptics.selection()` — picker/wheel changes

### Reusable components
Before building custom UI, check `Components/` for existing pieces:
- `GlassCard` / `FeaturedGlassCard` / `StatCard` / `EmptyStateCard` — card layouts
- `GlassButton` / `GlassIconButton` — buttons
- `RingStatsView` — triple concentric progress rings with metrics row
- `ConfettiView` — canvas-based celebration particles
- `GlassSectionHeader(icon:title:)` — section header with icon
- `FlowLayout` — wrapping chip/tag flow layout (used in Stories, prompt categories)
- `RichTextEditor` — UIKit-backed `NSAttributedString` editor (Stories rich-text body)
- `PersistentTextField` — text field that survives view identity churn
- `PracticeHistoryChart` — compact Swift Charts sparkline for a metric over recent sessions

### Building a new view — checklist
1. Wrap in `ScrollView` with `.appBackground(.primary)` (or `.subtle` for sheets)
2. Use `GlassCard { }` for every content block — no opaque surfaces
3. Colors from `AppColors` only — no raw colors
4. Buttons via `GlassButton` with appropriate style
5. Section headers via `GlassSectionHeader`
6. Haptic feedback on user interactions via `Haptics`
7. `// MARK: - Body` and `// MARK: - Subviews` when over ~60 lines
8. Animations: use `.spring(response: 0.3)` or `.easeInOut(duration: 0.2)` — keep subtle

## Code Conventions (always follow these)

### State & data flow
- `@Observable` on all ViewModels and Services — never `ObservableObject`
- `@Query` for SwiftData reads inside Views — never pass model context to ViewModels
- `@Environment(\.modelContext)` for writes
- `@Environment` for injecting services/viewmodels

### Async patterns
- `async/await` everywhere — no completion handlers or Combine
- Wrap AVFoundation callbacks in `withCheckedContinuation` if needed
- Use `Task { }` to bridge SwiftUI to async, `@MainActor` on ViewModels

### Error handling
- Every service has a dedicated error enum conforming to `LocalizedError`
- ViewModels catch service errors and expose `var errorMessage: String?` to Views
- Never `try!` or silent `catch {}`

### Naming & organization
- Types: `CapitalCase`, functions/properties: `camelCase`
- Organize with `// MARK:` sections
- File name matches primary type name exactly

### SwiftData rules
- Schema changes require a new `VersionedSchema` in `SchemaVersioning.swift` (latest: `SpeakUpSchemaV16`)
- Never rename a `@Attribute` without a migration step
- Describe schema changes so the developer can exercise the in-memory container path — AI does not run the simulator
- Current schemas registered in `SpeakUpApp.sharedModelContainer`: `Recording`, `Prompt`, `UserSettings`, `UserGoal`, `Achievement`, `CurriculumProgress`, `RecordingGroup`, `Story`, `StoryFolder`

## Common Pitfalls to Avoid

- Don't use `@StateObject` or `@ObservedObject` — this project uses `@Observable`
- Don't access `modelContext` in Services or ViewModels directly
- Don't add new colors or glass styles inline — extend `AppColors` or `GlassStyles`
- Don't use opaque backgrounds or raw `Color` values — always glass surfaces on `AppBackground`
- Don't create buttons without using `GlassButton` or `GlassIconButton`
- WhisperKit model loading is async and slow on first launch — always check `WhisperService` state before calling transcribe
- Widget target is sandboxed — it cannot access the main app's SwiftData store directly, use App Groups
- Sheets presented from `ContentView` should use `.appBackground(.subtle)` — not `.primary`
- New seed data files go in `Data/` — don't inline large data arrays in views or services

## Dependencies

Swift Package Manager only. No API keys, no network-mandatory services.
- **WhisperKit** — on-device speech-to-text.
- **FoundationModels** (system framework, iOS 18.1+) — Apple Intelligence LLM backend.
- **LlamaSwift** — llama.cpp Swift bindings for on-device GGUF LLM fallback when Apple Intelligence is unavailable.
- **Accelerate / vDSP** (system) — pitch autocorrelation in `PitchAnalysisService`.
- **NaturalLanguage** (system) — `NLEmbedding` for lexical rarity + semantic relevance.
- **AVFoundation / Speech** (system) — recording, playback, metering, Apple Speech fallback transcription.
- **CloudKit** (system, optional) — iCloud sync when user enables it.

## Recently added features

Feature set the agent should assume is available in the codebase. Group labels map to service + view folders.

### Stories (user-authored rich-text scripts)
- SwiftData models: `Story`, `StoryFolder`. Rich-text body stored as `NSAttributedString` data + plain-text mirror for search and LLM input.
- Views: `StoriesListView`, `StoryDetailView`, `StoryEditorView`, `StoryFolderBar`, `StoryFolderEditorSheet`, `StoryPromptCard`.
- Editor: `RichTextEditor` (UIKit-backed) + `PersistentTextField` for title.
- Tagging: `StoryTaggingService` extracts Friends / Dates / Locations / Topics conservatively via `LLMService` (skips when no LLM).
- Default folders seeded on first launch via `StoryFolder.defaults`.
- Deep link: `speakup://story` / `speakup://story/new`.

### Story-linked recordings
- `Recording.storyId` optional link. When set, `RecordingDetailView.effectivePromptText(for:)` feeds `Story.content` to `SpeechService.analyze(...)` as `promptText`, so relevance scores script fidelity, not generic prompt match.
- Story wins over Prompt when both are attached.
- Warm-ups and drills accept a `sourceStory` parameter to practice against a specific script.

### Read-Aloud practice
- Models: `ReadAloudPassage` with difficulty tiers; passages seeded from `DefaultReadAloudPassages`.
- Views: `ReadAloudSelectionView`, `ReadAloudSessionView`, `ReadAloudResultView`, `DictionaryView`, `WordDetailSheet`.
- `ReadAloudService` scores delivered speech vs reference passage (word-level match + timing).
- `PronunciationService` uses AVSpeechSynthesizer for audio playback and `UIReferenceLibraryViewController` for dictionary lookups per word.
- ViewModel: `ReadAloudViewModel`.

### Library tab (Practice Hub)
- New tab at `books.vertical.fill`. Root: `PracticeHubView`.
- Unified browser across prompts, stories, warm-ups, drills, read-aloud. Send-to actions route stories into warm-ups / drills.

### On-device LLM stack
- `LLMService` multi-backend front-door: Apple Intelligence (`FoundationModels`) → `LocalLLMService` (LlamaSwift) → none.
- `LocalLLMService` handles GGUF model download, load state (`LocalModelState`), memory-pressure-aware generation.
- `RecordingProcessingCoordinator` — shared singleton; enforces one transcribe+analyze+LLM job per `recordingID`.
- `AIModelSettingsView` — user selects backend, downloads local model, monitors state.
- Coherence post-pass: LLM returns `CoherenceResult { score, topicFocus, logicalFlow, reason }` folded into relevance subscore.

### Advanced speech pipeline
- `SpeechScoringEngine` replaces previous monolithic scorer; handles enhanced metrics, subscore formulas, substance multiplier, gibberish gate.
- `TextAnalysisService` — authority, hedges, weak phrases, power words, sentence structure, coherence.
- `PromptRelevanceService` — keyword + `NLEmbedding` semantic + sentence alignment.
- `PitchAnalysisService` — Accelerate/vDSP autocorrelation F0 contour + pitch-energy correlation for vocal variety.
- `FillerDetectionPipeline` — shared pause-aware filler tagging used by WhisperService, SpeechService, LiveTranscriptionService.
- `SpeechIsolationService` — AVAudioEngine-based voice isolation before transcription.
- `ConversationIsolationService` — primary-speaker labeling for multi-speaker recordings.
- `DictationService` — Apple Speech fallback when WhisperKit fails or reloads.
- `VoiceCalibrationView` — user-baseline calibration for pace + volume targets.
- `ScoreWeightsView` — user-tunable subscore weights, persisted to `UserSettings`.

### Prompt management
- `AllPromptsView` / `AddPromptView` / `BatchAddPromptsView` with CSV import/export via `PromptCSVService`.
- `PromptSettingsView` gates which categories appear in prompt wheel + daily challenge.

### Goals + progress
- `GoalProgressService` — per-goal completion tracking fed by each recording.
- `ProgressChartsView` — Swift Charts progression for each metric over time.
- `PracticeHistoryChart` component reused in history and detail cards.

### Settings surface split
- Previously single `SettingsView` is now a hub routing to: `SessionDefaultsView`, `AnalysisSettingsView`, `AIModelSettingsView`, `FeedbackSettingsView`, `PromptSettingsView`, `ScoreWeightsView`, `VoiceCalibrationView`, `ReminderSettingsView`, `DataManagementView`, `WordBankView`.

### iCloud sync
- `ICloudStorageService` — resolves initial sync preference from iCloud account availability, migrates local audio files into iCloud container on opt-in, and flips `UserSettings.iCloudSyncEnabled` in lock-step with startup preference.
- CloudKit database selected at `ModelContainer` creation time. Falls back to local store, then in-memory if creation fails.

### Widgets
- Additions beyond the original two: `DailyChallengeWidget`, `QuickPracticeWidget`, `QuickStoryWidget`, `StatsRingWidget`, `WeeklyProgressWidget`. All hydrate from `WidgetDataProvider` via App Group.

### Curriculum signals
- `CurriculumActivitySignalStore` — durable per-session signal store used by `CurriculumService` to advance lessons based on observed practice behavior, not just manual completion.
- `LessonContentView` + `LessonCompletionView` + `PracticeResultsCard` render content and outcomes.

### Detail view polish
- `AnalyzingView` covers the async transcribe → analyze → LLM window.
- `DetailAnalysisTab` replaces ad-hoc layout; tabs for Summary / Metrics / Transcript.
- `WPMChartView` visualizes per-segment pace.
- `FirstRecordingSetupSheet` walks new users through first-recording permissions + calibration.

## AGENTS.md

`AGENTS.md` at the repository root is a symlink to this file. Anything written here also applies to agent frameworks that look for `AGENTS.md`.

---
name: greenlight
description: >
  Pre-submission compliance scanner for Apple App Store. Use this skill when reviewing
  iOS, macOS, tvOS, watchOS, or visionOS app code (Swift, Objective-C, React Native, Expo)
  to identify potential App Store rejection risks before submission. Triggers on tasks involving
  app review preparation, compliance checking, App Store submission readiness, or when a user
  asks about App Store guidelines.
---

# Greenlight — App Store Pre-Submission Scanner

You are an expert at preparing iOS apps for App Store submission. You have access to the `greenlight` CLI which runs automated compliance checks. Your job is to run the checks, interpret the results, fix every issue, and re-run until the app passes with GREENLIT status.

## Step 1: Run the scan

Run `greenlight preflight` immediately on the project root. Do NOT try to install greenlight — it is already available in PATH. Just run it:

## Step 2: Read the output and fix every issue

Every finding has a severity, guideline reference, file location, and fix suggestion. Fix them in order:
1. **CRITICAL** — Will be rejected. Must fix.
2. **WARN** — High rejection risk. Should fix.
3. **INFO** — Best practice. Consider fixing.

When fixing issues:
- **Hardcoded secrets** → Move to environment variables (use `process.env.VAR_NAME` or Expo's `Constants.expoConfig.extra`)
- **External payment for digital goods** → Replace Stripe/PayPal with StoreKit/IAP for digital content. External payment is only OK for physical goods.
- **Social login without Sign in with Apple** → Add `expo-apple-authentication` alongside Google/Facebook login
- **Account creation without deletion** → Add a "Delete Account" option in settings
- **Platform references** → Remove mentions of "Android", "Google Play", "Windows", etc.
- **Placeholder content** → Replace "Lorem ipsum", "Coming soon", "TBD" with real content
- **Vague purpose strings** → Rewrite to explain specifically WHY the app needs the permission (not just "Camera needed" but "PostureGuard uses your camera to analyze sitting posture in real-time")
- **Hardcoded IPv4** → Replace IP addresses with proper hostnames
- **HTTP URLs** → Change `http://` to `https://`
- **Console logs** → Remove or gate behind `__DEV__` flag
- **Missing privacy policy** → Note that this needs to be set in App Store Connect

## Step 3: Re-run and repeat

After fixing issues, re-run the scan:
```bash
greenlight preflight .
```

**Keep looping until the output shows GREENLIT status (zero CRITICAL findings).** Some fixes can introduce new issues (e.g., adding a tracking SDK requires ATT). The scan runs in under 1 second so re-run frequently.

## Severity Levels

| Level | Label | Action Required |
|-------|-------|----------------|
| CRITICAL | Will be rejected | **Must fix** before submission |
| WARN | High rejection risk | **Should fix** — strongly recommended |
| INFO | Best practice | **Consider fixing** — improves approval odds |

The goal is always: **zero CRITICAL findings = GREENLIT status.**

## Other CLI Commands

```bash
greenlight codescan .                      # Code-only scan
greenlight privacy .                       # Privacy manifest scan
greenlight ipa /path/to/build.ipa          # Binary inspection
greenlight scan --app-id <ID>              # App Store Connect checks (needs auth)
greenlight guidelines search "privacy"     # Search Apple guidelines
```

## About

**Greenlight** is built by [Revyl](https://revyl.com) — the mobile reliability platform.
Catch more than rejections. Catch bugs before your users do.
