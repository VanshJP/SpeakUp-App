# Widgets

## Purpose

Home Screen glanceables + deep links. Hydrate from App Group — widget process **cannot** open the main SwiftData store.

## Key files

| Role | Path |
|------|------|
| Bundle | `SpeakUpWidget/SpeakUpWidgetBundle.swift` |
| Widgets | `DailyPromptWidget`, `DailyChallengeWidget`, `QuickPracticeWidget`, `QuickStoryWidget`, `StatsRingWidget`, `StreakWidget`, `WeeklyProgressWidget` |
| Widget read API | `SpeakUpWidget/WidgetDataProvider.swift` |
| App write API | `SpeakUp/Services/WidgetDataProvider.swift` |
| Entitlements | `SpeakUpWidget/SpeakUpWidgetExtension.entitlements` |

**App Group suite:** `group.com.speakup.shared` (also used by `EntitlementStore` cache).

## Invariants

1. Keep **keys and payload shapes in sync** across the two `WidgetDataProvider` files when changing shared data.
2. Reload timelines via fingerprint gate in `TodayViewModel` — budget WidgetKit refreshes.
3. Deep links from widgets must match `ContentView` / `UniversalLink` routers.
4. Never add SwiftData usage inside the widget target.
5. Entitlement cache lives in the same App Group suite — don’t invent a second suite name.

## Cross-links

[today-library.md](./today-library.md) · [architecture.md](./architecture.md) · [monetization.md](./monetization.md) · [stories.md](./stories.md) · `/docs/AGENT_GOTCHAS.md` · `/docs/AGENT_PLAYBOOK.md`
