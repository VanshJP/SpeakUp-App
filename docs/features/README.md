# Feature docs — agent index

Progressive disclosure for Big Talk / SpeakUp. **Read only the docs for the feature you are changing.** Root `AGENTS.md` holds always-on rules; these files hold domain context.

**Cross-cutting (read when relevant, not every turn):**

| Doc | When |
|-----|------|
| [`../AGENT_GOTCHAS.md`](../AGENT_GOTCHAS.md) | MainActor default, `#Predicate` blobs, background fetches, DI, shares, widgets |
| [`../AGENT_PLAYBOOK.md`](../AGENT_PLAYBOOK.md) | Add setting / paid gate / SwiftData field / widget / test / practice surface |

Canonical contracts that are *not* duplicated here:

| Contract | Path | When |
|----------|------|------|
| Speech scoring pipeline | `/SPEECH.md` | Any transcription / scoring / LLM coherence change |
| Onboarding invariants | `/ONBOARDING_VISION.md` | Anything under `Views/Onboarding/` or onboarding in `ContentView` |
| Onboarding research | `/ONBOARDING_REDESIGN.md` | Redesign rationale only |
| App Store listing | `/APP_STORE_LISTING.md` | Marketing claims, keywords |
| Product pages / attribution | `/APP_STORE_PRODUCT_PAGES.md` | Custom product pages, UTM |
| Launch checklist | `/RELEASE_CHECKLIST.md` | IAP, free/paid, ASC, measurement |

## Feature map

| Doc | Owns | Primary code |
|-----|------|----------------|
| [architecture.md](./architecture.md) | Boot, tabs, deep links, DI, global sheets | `SpeakUpApp.swift`, `ContentView.swift` |
| [recording.md](./recording.md) | Capture session UI + audio | `Views/Recording/`, `RecordingViewModel*`, `AudioService` |
| [speech-pipeline.md](./speech-pipeline.md) | Pointer into `SPEECH.md` + wiring | `Services/*Speech*`, `RecordingProcessingCoordinator` |
| [recording-detail.md](./recording-detail.md) | Analyzing / score reveal / playback / share + prompt links | `Views/Detail/`, `SharePresenter`, `SharedPromptLink` |
| [stories.md](./stories.md) | Rich-text scripts + story practice | `Views/Stories/`, `Story*`, `StoryTaggingService` |
| [read-aloud.md](./read-aloud.md) | Passage practice + dictionary | `Views/ReadAloud/`, `ReadAloudService` |
| [today-library.md](./today-library.md) | Today home + Practice Hub | `Views/Today/`, `Views/Practice/` |
| [vocab-challenge.md](./vocab-challenge.md) | Daily word workout | `VocabChallengeService`, `Views/Today/VocabChallengeCard.swift` |
| [history-progress.md](./history-progress.md) | History, charts, journal, streak | `Views/History/`, `Views/Progress/`, `Views/Streak/` |
| [curriculum.md](./curriculum.md) | Learn tab, signal progression | `Views/Curriculum/`, `CurriculumService` |
| [practice-tools.md](./practice-tools.md) | Warm-ups, drills, confidence | `Views/WarmUp/`, `Drills/`, `Confidence/` |
| [settings.md](./settings.md) | Settings hub + subpages | `Views/Settings/` |
| [widgets.md](./widgets.md) | WidgetKit + App Group data | `SpeakUpWidget/`, dual `WidgetDataProvider` |
| [icloud.md](./icloud.md) | CloudKit + file migration | `ICloudStorageService` |
| [monetization.md](./monetization.md) | Lifetime, allowance, paywall call sites | `Models/Monetization.swift`, `Views/Paywall/` |
| [analytics-review.md](./analytics-review.md) | Local analytics, attribution, review | `AnalyticsService`, `ReviewRequestService` |
| [ui-design-system.md](./ui-design-system.md) | Theme, glass, components checklist | `Theme/`, `Views/Components/` |
| [achievements-goals.md](./achievements-goals.md) | Achievements gallery + goals | `Views/Achievements/`, `Views/Goals/` |

## How to add a feature doc

1. Create `docs/features/<slug>.md` with: purpose, key files, invariants, cross-links.
2. Add a row to the table above.
3. Add a row to the load table in root `AGENTS.md`.
4. Keep each doc under ~150 lines. Link to code and contracts; do not paste whole algorithms.
5. Silent traps → also add a bullet to `../AGENT_GOTCHAS.md`.
