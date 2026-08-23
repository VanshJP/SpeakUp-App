# Widgets

## Purpose

Home Screen glanceables + deep links. Hydrate from App Group — widget process **cannot** open the main SwiftData store.

## Key files

| Role | Path |
|------|------|
| Bundle | `SpeakUpWidget/SpeakUpWidgetBundle.swift` |
| Widgets | `DailyPromptWidget`, `QuickPracticeWidget`, `QuickStoryWidget`, `StatsRingWidget`, `StreakWidget`, `WeeklyProgressWidget` |
| Widget read API | `SpeakUpWidget/WidgetDataProvider.swift` |
| App write API | `SpeakUp/Services/WidgetDataProvider.swift` |
| Entitlements | `SpeakUpWidget/SpeakUpWidgetExtension.entitlements` |

**App Group suite:** `group.com.speakup.shared` (also used by `EntitlementStore` cache).

## Invariants

1. Keep **keys and payload shapes in sync** across the two `WidgetDataProvider` files when changing shared data. Current keys include `interviewReadinessScore` (written by `TodayViewModel` from the lexicon engine; `0` = no analyzed history, widgets hide the field rather than show a real 0).
2. Reload timelines via fingerprint gate in `TodayViewModel` — budget WidgetKit refreshes.
3. Deep links from widgets must match `ContentView` / `UniversalLink` routers.
4. Never add SwiftData usage inside the widget target.
5. Entitlement cache lives in the same App Group suite — don’t invent a second suite name.
6. **Coordinator contract:** after each successful analysis, `RecordingProcessingCoordinator` writes the two values an analysis actually changes (`lastScore`, `lastPracticeDate`) directly to the App Group — widgets render from that snapshot, not SwiftData, so a bare reload would re-render stale numbers — then calls `WidgetDataProvider.resetTodayFingerprint()` so the change gate reports a diff on Today's next visit and the full payload is rewritten wholesale, then reloads timelines.
7. **Refresh cadence:** `StreakWidget` bakes each urgency band's message into its own timeline entry at the local 12:00 / 17:00 / 20:00 rollovers (one entry per band instead of one static entry), and `DailyPromptWidget` schedules `.after(nextMidnight)` — intraday payload changes arrive via fingerprint-gated app reloads, not widget polling.

## Cross-links

[today-library.md](./today-library.md) · [architecture.md](./architecture.md) · [monetization.md](./monetization.md) · [stories.md](./stories.md) · `/docs/AGENT_GOTCHAS.md` · `/docs/AGENT_PLAYBOOK.md`
