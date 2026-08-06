# AGENTS.md — Big Talk (SpeakUp)

Cross-tool instructions for AI coding agents. Keep this file short — deep detail lives in `docs/features/` and root contracts (`SPEECH.md`, `ONBOARDING_VISION.md`). `CLAUDE.md` is a symlink to this file.

**Product:** Big Talk — native iOS speech practice. On-device transcription (WhisperKit), multi-dimensional scoring, optional on-device LLM coherence, Stories, Read-Aloud, curriculum, widgets, Lifetime IAP.  
**Code prefix:** `SpeakUp*` / `SpeakUp/` (user-facing name is Big Talk).  
**Bundle:** `com.vansh.SpeakUpMore` · Widget: `com.vansh.SpeakUpMore.SpeakUpWidget` · **iOS 26.0+** · SwiftUI + SwiftData + SPM.

---

## Hard rules

1. **Do not build or test iOS.** Never run `xcodebuild`, `xcrun simctl`, `idb`, XCUITest, Simulator, or emulator loops. Edit source/docs/config only. Hand off exact build/test commands to the developer.
2. **Do not install deps** unless asked (`xcodebuild -resolvePackageDependencies`, SPM, etc.).
3. **SwiftData schema = additive only.** Optional fields or defaults. Never rename/remove stored `@Attribute`s or make existing fields non-optional.
4. **No `@StateObject` / `@ObservedObject`.** Use `@Observable`. ViewModels never take `ModelContext`; Views use `@Query` / `@Environment(\.modelContext)`.
5. **UI = design system only.** `AppColors` / `GlassStyles` / `AppBackground` / `GlassButton`. No raw `Color.blue` / opaque cards. Sheets use `.appBackground(.subtle)`.
6. **Never decode `Recording.analysis` on the main thread in `body`.** Use background `ModelContext` + lightweight projections (`RecordingSummary`, `ChartRecordingPoint`).
7. **Persisted text (commits, PRs, code comments) = normal English.** Chat may use Smart Caveman (see below).

---

## How to load context (progressive disclosure)

Before editing a feature, **read the matching doc** — do not reload all of `docs/features/`.

| Working on… | Read first |
|-------------|------------|
| Any new feature / unsure where code lives | `docs/features/README.md` |
| App boot, tabs, deep links, global sheets | `docs/features/architecture.md` |
| Recording UI / AudioService | `docs/features/recording.md` |
| Transcription, scoring, LLM pass | **`SPEECH.md`** (+ `docs/features/speech-pipeline.md`) |
| Post-recording detail / analyzing UI | `docs/features/recording-detail.md` |
| Stories / story-linked practice | `docs/features/stories.md` |
| Read-Aloud | `docs/features/read-aloud.md` |
| Today / Library (Practice Hub) | `docs/features/today-library.md` |
| History / charts / journal / streak | `docs/features/history-progress.md` |
| Curriculum / Learn | `docs/features/curriculum.md` |
| Warm-ups / drills / confidence | `docs/features/practice-tools.md` |
| Onboarding / app tour | **`ONBOARDING_VISION.md`** (research: `ONBOARDING_REDESIGN.md`) |
| Settings surfaces | `docs/features/settings.md` |
| Widgets / App Group | `docs/features/widgets.md` |
| iCloud / CloudKit | `docs/features/icloud.md` |
| Paywall / Lifetime / allowance | `docs/features/monetization.md` |
| Analytics / attribution / review prompts | `docs/features/analytics-review.md` |
| Theme / glass / colors / components | `docs/features/ui-design-system.md` |
| Achievements / goals | `docs/features/achievements-goals.md` |
| App Store listing / launch | `APP_STORE_LISTING.md`, `RELEASE_CHECKLIST.md` |

**Discovery:** use ripgrep / Glob / Read on `SpeakUp/`. There is no semantic index MCP. Prefer path + type search over whole-repo dumps.

**Skills:** `.claude/skills/` and `.agents/skills/` (SwiftUI, SwiftData, concurrency, WidgetKit, accessibility, ASO, greenlight, etc.). Load a skill when the task matches — do not paste skill bodies into every turn.

---

## Architecture (sketch)

```
View (SwiftUI) → ViewModel (@MainActor @Observable) → Service (@Observable) → SwiftData / files
```

| Layer | Path | Notes |
|-------|------|--------|
| Entry | `SpeakUp/SpeakUpApp.swift` | `ModelContainer`, service inject, seeding, migrations |
| Shell | `SpeakUp/Views/ContentView.swift` | 5 tabs + global sheets / deep links |
| Models | `SpeakUp/Models/` | SwiftData entities + value types |
| Services | `SpeakUp/Services/` | No UI; own `LocalizedError` enums |
| ViewModels | `SpeakUp/ViewModels/` | UI state; call services |
| Views | `SpeakUp/Views/<Feature>/` | Feature folders |
| Theme | `SpeakUp/Theme/` | Colors, glass, background, type, motion |
| Data seeds | `SpeakUp/Data/` | Default prompts, curriculum, passages, … |
| Widget | `SpeakUpWidget/` | WidgetKit; App Group only — no SwiftData |

**Tabs:** Today → Library (`PracticeHubView`) → History → Learn (`CurriculumView`) → Settings.

**Schema types:** `Recording`, `Prompt`, `UserSettings`, `UserGoal`, `Achievement`, `CurriculumProgress`, `RecordingGroup`, `Story`, `StoryFolder`.

---

## Conventions that differ from defaults

- `async/await` only — no Combine completion handlers for new code.
- Services expose errors; ViewModels map to `errorMessage: String?`.
- File name = primary type. Use `// MARK:` sections.
- High-frequency metering/playback: pass snapshots into small POD subviews; draw dense visuals in one `Canvas`.
- Resolve file existence once into `@State` — never `FileManager` in `body`.
- Widget timeline reloads: fingerprint-gate via `TodayViewModel` — no unconditional `reloadAllTimelines()`.
- Prompt seeding: fingerprint-gated (`seededPromptFingerprint_v1`).

---

## Developer handoff (build / test)

Agent never runs these. Suggest when relevant:

```bash
# Open in Xcode, then:
xcodebuild -scheme SpeakUp -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme SpeakUp -destination 'platform=iOS Simulator,name=iPhone 16' test
```

StoreKit config: `Products.storekit` (Lifetime SKU `com.vansh.SpeakUpMore.lifetime`).

---

## Persona — Smart Caveman (chat only)

Default chat style: **Smart Caveman, full**. Drop articles/filler/pleasantries/hedging. Fragments OK. Pattern: `[thing] [action] [reason]. [next step].`  
Exceptions: destructive warnings, multi-step clarity, user confusion.  
`/caveman lite|full|ultra` or `stop caveman` — level persists.  
**Never** caveman in commits, PRs, or code comments.

---

## Doc maintenance

When you add or reshape a feature: update the matching `docs/features/*.md` and the index row in `docs/features/README.md` in the same PR. Do not grow this file with feature encyclopedias — link out.
