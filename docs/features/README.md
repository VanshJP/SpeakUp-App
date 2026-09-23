# Feature docs — agent index

Progressive disclosure for Big Talk / SpeakUp. **Open only the row you are changing.** Root `AGENTS.md` is the always-on kernel. Landmines: [`../AGENT_GOTCHAS.md`](../AGENT_GOTCHAS.md). Recipes: [`../AGENT_PLAYBOOK.md`](../AGENT_PLAYBOOK.md). Product router skill: `speakup`. After edits: `scripts/agent-verify.sh`; if this index or a brief changed: `scripts/agent-doc-drift.sh`. Typed entry points: [`../SURFACE_MAP.md`](../SURFACE_MAP.md).

## Contracts (not duplicated here)

| Contract | Path | When |
|----------|------|------|
| User journeys | `/docs/USER_JOURNEYS.md` | Cross-feature flow audits and prioritization |
| Speech scoring | `/SPEECH.md` | Transcription / scoring / LLM coherence |
| Onboarding invariants | `/ONBOARDING_VISION.md` | `Views/Onboarding/` or onboarding in `ContentView` |
| Onboarding research | `/ONBOARDING_REDESIGN.md` | Redesign rationale only — do not load by default |
| Store listing | `/APP_STORE_LISTING.md` | Marketing claims, keywords |
| Product pages / attribution | `/APP_STORE_PRODUCT_PAGES.md` | Custom product pages, UTM |
| Launch | `/RELEASE_CHECKLIST.md` | IAP, free/paid, ASC, measurement |

## Feature map

| When | Read | Code | Also | Skill |
|------|------|------|------|-------|
| Boot, tabs, deep links, DI | [architecture.md](./architecture.md) | `SpeakUpApp.swift`, `ContentView.swift` | gotchas §1, §6 | — |
| Recording session / audio | [recording.md](./recording.md) | `Views/Recording/`, `RecordingViewModel*`, `AudioService` | gotchas §4, §9 | `axiom-media` |
| Transcription / scoring wiring | [speech-pipeline.md](./speech-pipeline.md) | `Services/*Speech*`, `RecordingProcessingCoordinator` | **`SPEECH.md`**, gotchas §2, §5, §9 | `axiom-media` |
| Analyzing / detail / share | [recording-detail.md](./recording-detail.md) | `Views/Detail/`, `SharePresenter`, `SharedPromptLink` · self-check wait screen (`AnalyzingView`, `FeelingSlider`) | gotchas §2b, §3, §7, §29 | — |
| Stories | [stories.md](./stories.md) | `Views/Stories/`, `Story*`, `StoryFolderHealing` (+ `StoryFolderSeedService`), `StoryTaggingService` | — | — |
| Read-Aloud | [read-aloud.md](./read-aloud.md) | `Views/ReadAloud/`, `ReadAloudService`, `RecognitionContinuity`, `ReadAloudDocumentImporter`, `PronunciationService` · toolbar add action / paste + import / saved rail / focus-grouped catalog / hear-it / holds + stalls / drill what you missed / minimal pairs / sounds to check (`ConsonantAnalyzer`) | gotchas §9, §25, §26 | `axiom-media` |
| Today / Practice Hub | [today-library.md](./today-library.md) | `Views/Today/`, `Views/Practice/`, `TodayHomeModule`, `PracticeToolKind` | — | — |
| Daily word workout / word library | [vocab-challenge.md](./vocab-challenge.md) | `VocabChallengeService`, `Views/Today/VocabChallengeResultCard.swift`, `Views/Words/WordLibraryView.swift` | — | — |
| History / trajectory / readiness / journal | [history-progress.md](./history-progress.md) | `Views/History/`, `Views/Progress/`, `Views/Streak/`, `ScenarioReadinessEngine` | gotchas §2b, §3 | — |
| Learn / curriculum | [curriculum.md](./curriculum.md) | Skill studio (`CurriculumView` list + modalities), `LessonIdentity`, `CurriculumService` | monetization.md · ui-design-system.md | — |
| Practice routine / step chaining | [routine.md](./routine.md) | `Models/PracticeRoutine.swift`, `PracticeRoutineService`, `Views/Today/RoutineCard.swift` | today-library.md · practice-tools.md | — |
| Warm-ups / drills / confidence | [practice-tools.md](./practice-tools.md) | `Views/WarmUp/`, `Drills/`, `Confidence/`, `Views/Practice/PracticeFocusView` · `DrillMode` (duration ladders) · `DrillProgressStore` · `DefaultDrillPrompts` · **`PracticeFocus`** (shared outcome axis, all four tools group by it) | gotchas §26 | — |
| Onboarding / app tour | `/ONBOARDING_VISION.md` | `Views/Onboarding/`, `AppTourOverlay` | gotchas §10 | — |
| Settings | [settings.md](./settings.md) | `Views/Settings/` | playbook | — |
| Widgets / App Group | [widgets.md](./widgets.md) | `SpeakUpWidget/`, dual `WidgetDataProvider` | gotchas §8 | `widgetkit` |
| iCloud / CloudKit | [icloud.md](./icloud.md) | `ICloudStorageService` | gotchas §1 | `swiftdata-pro` |
| Paywall / Lifetime / allowance | [monetization.md](./monetization.md) | `Models/Monetization.swift` | gotchas §5, playbook | `greenlight` (ship) |
| Analytics / attribution / review | [analytics-review.md](./analytics-review.md) | `AnalyticsService`, `ReviewRequestService` | gotchas §7 | — |
| Retention / notifications / streak freeze | [retention.md](./retention.md) | `RetentionScheduler`, `RetentionNotificationPlanner`, `PracticeRhythm`, `NotificationService`, `StreakProtection` | settings.md · `/ONBOARDING_VISION.md` | — |
| Theme / glass / components | [ui-design-system.md](./ui-design-system.md) | `Theme/`, `Views/Components/` | gotchas §11 | `swiftui-expert-skill` |
| Achievements / goals | [achievements-goals.md](./achievements-goals.md) | `Views/Achievements/`, `Views/Goals/` | — | — |
| Coach notes (rare asides) | [coach-moments.md](./coach-moments.md) | `Models/CoachMoment.swift`, `CoachMomentService`, `Views/CoachMoment/` | — | — |
| App Store listing / launch | `/APP_STORE_LISTING.md`, `/RELEASE_CHECKLIST.md` | metadata | greenlight | `greenlight`, `apple-appstore-reviewer` |

Vendor skill catalog: [`../../.agents/skills/README.md`](../../.agents/skills/README.md). Load **one** skill body per task. Prefer `swiftui-expert-skill` to write SwiftUI; `swiftui-pro` to review it — not both.

## How to add a feature doc

1. Create `docs/features/<slug>.md` with: purpose, key files, invariants, cross-links. Keep under ~150 lines. Link to code and contracts; do not paste algorithms.
2. Add a row to the table above. Do **not** grow root `AGENTS.md`.
3. Silent traps → also a bullet in `../AGENT_GOTCHAS.md`. Repeatable workflow → `../AGENT_PLAYBOOK.md`.
