# Architecture — boot, navigation, deep links

## Purpose

Start the app: build SwiftData `ModelContainer`, inject services, seed defaults, present the 5-tab shell and global sheets, route deep links / universal links.

## Key files

| Role | Path |
|------|------|
| Entry | `SpeakUp/SpeakUpApp.swift` |
| Shell / tabs | `SpeakUp/Views/ContentView.swift` (`AppTab`) |
| Universal links | `SpeakUp/Models/UniversalLink.swift` |
| AASA | `Config/apple-app-site-association` |
| Entitlements | `SpeakUp/SpeakUp.entitlements` |

**Injected services (Environment):** `SpeechService`, `AudioService`, `LLMService`.  
**Also started at launch:** `PurchaseService.shared.start()`, entitlement refresh on foreground, deferred recording resume.

**Schema:** `Recording`, `Prompt`, `UserGoal`, `UserSettings`, `Achievement`, `CurriculumProgress`, `RecordingGroup`, `Story`, `StoryFolder`.

## Tabs

| Tab | Symbol | Root |
|-----|--------|------|
| Today | `mic.badge.plus` | `TodayView` |
| Library | `books.vertical.fill` | `PracticeHubView` |
| History | `clock.fill` | `HistoryView` → detail |
| Learn | `book` | `CurriculumView` |
| Settings | `gearshape` | `SettingsView` |

Achievements are a **sheet**, not a tab. Global covers/sheets owned by `ContentView`: countdown, recording, paywall, onboarding, prompt wheel, goals, warm-ups/drills (optional `sourceStory`), confidence, before/after, journal, read-aloud, story editor, achievement unlock, app tour (`AppTourModel`).

## Deep links

- `speakup://record?prompt=<id>` — start recording (clears prior prompt/story/goal context as coded)
- `speakup://story` / `speakup://story/new` — Library / new story
- HTTPS universal links → same router; capture attribution **before** routing (`AttributionStore`)

## Invariants

1. CloudKit vs local store decided **before** container creation via `ICloudStorageService.resolvedSyncEnabledPreference`. Fallback: CloudKit → local → in-memory.
2. Onboarding cover: wait for `@Query` settings so returning users never flash the cover.
3. Seeding (prompts, settings, achievements, curriculum, story folders) runs concurrently; prompt seed is fingerprint-gated.
4. Background launch work: legacy URL migration, iCloud file migration, Whisper preload, local LLM auto-load — do not block first paint on these.

## Cross-links

[monetization.md](./monetization.md) · [icloud.md](./icloud.md) · [recording.md](./recording.md) · [widgets.md](./widgets.md) · [analytics-review.md](./analytics-review.md) · `/ONBOARDING_VISION.md`
