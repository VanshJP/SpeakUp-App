# AGENTS.md — Big Talk (SpeakUp)

Kernel only. `CLAUDE.md` → this file. Detail is on-demand — never ingest `docs/features/` wholesale.

**Product:** Big Talk — on-device speech practice (WhisperKit, multi-axis scoring, optional on-device LLM).  
**Code:** `SpeakUp*` / `SpeakUp/` · bundle `com.vansh.SpeakUpMore` · widget `com.vansh.SpeakUpMore.SpeakUpWidget`  
**Stack:** iOS 26.0+ · SwiftUI · SwiftData · SPM · `@Observable` (never `ObservableObject`)

---

## Stance

Senior engineer, repo on disk. Optimize for correct shipped source, not conversation.

- **Code is truth.** Docs are maps. Conflict → follow code, patch the map in the same PR.
- **Load the minimum.** One feature doc. One skill. Gotchas only for concurrency, SwiftData, shares, widgets, or audio-thread work.
- **Search before inventing.** `rg` / Glob on `SpeakUp/`. No semantic index. No whole-tree dumps.
- **Finish the loop.** Implement, sync the matching feature doc, leave no TODO for work you started.
- **High agency.** Do not ask permission for mechanical next steps. Ask only when product intent is ambiguous or a change is destructive.
- **Do not sycophant.** If a request hits NEVER, refuse and propose a legal alternative.
- **No drive-by refactors.** Match local style. One concern per change unless asked.

---

## NEVER

1. Run `xcodebuild`, `xcrun simctl`, `idb`, XCUITest, Simulator, or install SPM/deps. Edit source/docs/config. Hand off exact commands.
2. SwiftData: additive schema only. Do not rename, remove, or make non-optional a stored `@Attribute`.
3. `@StateObject` / `@ObservedObject`. ViewModels never take `ModelContext`. Views: `@Query` / `@Environment(\.modelContext)`.
4. Raw `Color.blue` / opaque cards. UI = `AppColors` / `GlassStyles` / `AppBackground` / `GlassButton`. Sheets: `.appBackground(.subtle)`.
5. Decode `Recording.analysis` on the main thread in `body`. Never `#Predicate` on Codable blob columns (process crash).
6. New pure types without `nonisolated` — default isolation is MainActor (`SWIFT_DEFAULT_ACTOR_ISOLATION`). Background work breaks. See `docs/AGENT_GOTCHAS.md`.
7. Caveman in commits, PRs, or code comments. Chat may be caveman; persisted text is normal English.

---

## Load

| Situation | Open |
|-----------|------|
| Unsure where code lives / new feature | `docs/features/README.md` |
| Concurrency, SwiftData, shares, widgets, audio thread | `docs/AGENT_GOTCHAS.md` |
| Add setting / paid gate / field / widget / test | `docs/AGENT_PLAYBOOK.md` |
| Scoring, transcription, LLM pass | `SPEECH.md` |
| Onboarding / app tour | `ONBOARDING_VISION.md` (not the research file) |
| Any SpeakUp product edit | skill `speakup` |
| Vendor technique (SwiftUI, WidgetKit, a11y, ASO, …) | `.agents/skills/README.md` → one `SKILL.md` |

Canonical skills: `.agents/skills/`. `.claude/skills/` and `agent/skills` are aliases. Load a skill **body** only on match — metadata is enough to decide.

System layout: `agent/README.md`.

---

## Map

```
View → ViewModel (@MainActor @Observable) → Service (@Observable) → SwiftData / files
```

| Layer | Path |
|-------|------|
| Entry | `SpeakUp/SpeakUpApp.swift` |
| Shell | `SpeakUp/Views/ContentView.swift` (5 tabs + global sheets / deep links) |
| Models / Services / ViewModels | `SpeakUp/Models/` · `Services/` · `ViewModels/` |
| Views / Theme / seeds | `SpeakUp/Views/<Feature>/` · `Theme/` · `Data/` |
| Widget | `SpeakUpWidget/` — App Group only, no SwiftData |

Tabs: Today → Library (`PracticeHubView`) → History → Learn (`CurriculumView`) → Settings.  
Schema: `Recording`, `Prompt`, `UserSettings`, `UserGoal`, `Achievement`, `CurriculumProgress`, `RecordingGroup`, `Story`, `StoryFolder`.

---

## Defaults that are wrong here

- New code: `async/await` only. Services throw; ViewModels map to `errorMessage: String?`. File name = primary type. `// MARK:` sections.
- Metering/playback: snapshots into POD subviews; dense draw in one `Canvas`. File existence → `@State`, never `FileManager` in `body`.
- Media: store via `Recording.relativeURL`; read via `resolvedAudioURL` / `resolvedVideoURL`.
- Env-injected: `SpeechService`, `AudioService`, `LLMService` only. Everything else `.shared`.
- Shares: `SharePresenter` only. Widget reloads: fingerprint-gate in `TodayViewModel`. Prompt seed: `seededPromptFingerprint_v1`.
- Paid: `FreeTierPolicy.trial` / `.expired`, not scattered `isLifetime`. **Beta:** `BetaAccess.allFeaturesFree` — read `docs/features/monetization.md` before adding a gate.

---

## Handoff (developer machine)

```bash
xcodebuild -scheme SpeakUp -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme SpeakUp -destination 'platform=iOS Simulator,name=iPhone 16' test
```

StoreKit: `Products.storekit` · SKU `com.vansh.SpeakUpMore.lifetime`. Tests: Swift Testing under `SpeakUpTests/`. Static checks agents *can* run: playbook → “Verify without Xcode”.

---

## Chat

Smart Caveman **full** (skill `caveman`). Pattern: `[thing] [action] [reason]. [next step].`  
`/caveman lite|full|ultra` or `stop caveman`. Drop caveman for destructive warnings, ordered steps, or user confusion.

---

## Doc hygiene

Reshape a feature → update `docs/features/<slug>.md` + the index row in the same PR. New silent trap → `docs/AGENT_GOTCHAS.md`. New recipe → `docs/AGENT_PLAYBOOK.md`. Do not grow this kernel — link out.
