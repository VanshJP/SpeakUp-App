# Feature docs — agent index

Progressive disclosure for Big Talk / SpeakUp. **Open only the row you are changing.** Root `AGENTS.md` is the always-on kernel. Landmines: [`../AGENT_GOTCHAS.md`](../AGENT_GOTCHAS.md). Recipes: [`../AGENT_PLAYBOOK.md`](../AGENT_PLAYBOOK.md). Product router skill: `speakup`.

## Contracts (not duplicated here)

| Contract | Path | When |
|----------|------|------|
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
| Analyzing / detail / share | [recording-detail.md](./recording-detail.md) | `Views/Detail/`, `SharePresenter`, `SharedPromptLink` | gotchas §2b, §3, §7 | — |
| Stories | [stories.md](./stories.md) | `Views/Stories/`, `Story*`, `StoryTaggingService` | — | — |
| Read-Aloud | [read-aloud.md](./read-aloud.md) | `Views/ReadAloud/`, `ReadAloudService` | gotchas §9 | `axiom-media` |
| Today / Practice Hub | [today-library.md](./today-library.md) | `Views/Today/`, `Views/Practice/` | — | — |
| Daily word workout | [vocab-challenge.md](./vocab-challenge.md) | `VocabChallengeService`, `Views/Today/VocabChallengeResultCard.swift` | — | — |
| History / trajectory / readiness / journal | [history-progress.md](./history-progress.md) | `Views/History/`, `Views/Progress/`, `Views/Streak/`, `ScenarioReadinessEngine` | gotchas §2b, §3 | — |
| Learn / curriculum | [curriculum.md](./curriculum.md) | `Views/Curriculum/`, `CurriculumService` | monetization.md | — |
| Warm-ups / drills / confidence | [practice-tools.md](./practice-tools.md) | `Views/WarmUp/`, `Drills/`, `Confidence/` | — | — |
| Onboarding / app tour | `/ONBOARDING_VISION.md` | `Views/Onboarding/`, `AppTourView` | gotchas §10 | — |
| Settings | [settings.md](./settings.md) | `Views/Settings/` | playbook | — |
| Widgets / App Group | [widgets.md](./widgets.md) | `SpeakUpWidget/`, dual `WidgetDataProvider` | gotchas §8 | `widgetkit` |
| iCloud / CloudKit | [icloud.md](./icloud.md) | `ICloudStorageService` | gotchas §1 | `swiftdata-pro` |
| Paywall / Lifetime / allowance | [monetization.md](./monetization.md) | `Models/Monetization.swift` | gotchas §5, playbook | `greenlight` (ship) |
| Analytics / attribution / review | [analytics-review.md](./analytics-review.md) | `AnalyticsService`, `ReviewRequestService` | gotchas §7 | — |
| Theme / glass / components | [ui-design-system.md](./ui-design-system.md) | `Theme/`, `Views/Components/` | gotchas §11 | `swiftui-expert-skill` |
| Achievements / goals | [achievements-goals.md](./achievements-goals.md) | `Views/Achievements/`, `Views/Goals/` | — | — |
| App Store listing / launch | `/APP_STORE_LISTING.md`, `/RELEASE_CHECKLIST.md` | metadata | greenlight | `greenlight`, `apple-appstore-reviewer` |

Vendor skill catalog: [`../../.agents/skills/README.md`](../../.agents/skills/README.md). Load **one** skill body per task. Prefer `swiftui-expert-skill` to write SwiftUI; `swiftui-pro` to review it — not both.

## How to add a feature doc

1. Create `docs/features/<slug>.md` with: purpose, key files, invariants, cross-links. Keep under ~150 lines. Link to code and contracts; do not paste algorithms.
2. Add a row to the table above. Do **not** grow root `AGENTS.md`.
3. Silent traps → also a bullet in `../AGENT_GOTCHAS.md`. Repeatable workflow → `../AGENT_PLAYBOOK.md`.
