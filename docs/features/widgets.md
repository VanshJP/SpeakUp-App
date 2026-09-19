# Widgets

## Purpose

Home Screen glanceables + deep links. Hydrate from App Group — widget process **cannot** open the main SwiftData store.

## Key files

| Role | Path |
|------|------|
| Bundle | `SpeakUpWidget/SpeakUpWidgetBundle.swift` |
| Widgets | `DailyPromptWidget`, `QuickPracticeWidget`, `QuickStoryWidget`, `StatsRingWidget`, `StreakWidget`, `WeeklyProgressWidget` |
| Design tokens | `SpeakUpWidget/WidgetTheme.swift` - `WidgetPalette`, `WidgetType`, `.bigTalkCanvas()` |
| Shared views | `SpeakUpWidget/WidgetComponents.swift` - header, ring, meter, chip, metric, glyph orb |
| Widget read API | `SpeakUpWidget/WidgetDataProvider.swift` |
| App write API | `SpeakUp/Services/WidgetDataProvider.swift` |
| Entitlements | `SpeakUpWidget/SpeakUpWidgetExtension.entitlements` |

## Families

| Widget | Families |
|--------|----------|
| `DailyPromptWidget` | `.systemMedium`, `.accessoryRectangular` |
| `StreakWidget` | `.systemSmall`, `.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline` |
| `QuickPracticeWidget` | `.systemSmall`, `.accessoryCircular` |
| `StatsRingWidget` | `.systemSmall`, `.systemMedium`, `.accessoryCircular`, `.accessoryRectangular` |
| `WeeklyProgressWidget` | `.systemMedium` |
| `QuickStoryWidget` | `.systemSmall`, `.systemMedium` |

**App Group suite:** `group.com.speakup.shared` (also used by `EntitlementStore` cache).

## Invariants

1. Keep **keys and payload shapes in sync** across the two `WidgetDataProvider` files when changing shared data. Current keys include `interviewReadinessScore` (written by `TodayViewModel` from the lexicon engine; `0` = no analyzed history, widgets hide the field rather than show a real 0).
2. Reload timelines via fingerprint gate in `TodayViewModel` — budget WidgetKit refreshes.
3. Deep links from widgets must match `ContentView` / `UniversalLink` routers.
4. Never add SwiftData usage inside the widget target.
5. Entitlement cache lives in the same App Group suite — don’t invent a second suite name.
6. **Coordinator contract:** after each successful analysis, `RecordingProcessingCoordinator` writes the two values an analysis actually changes (`lastScore`, `lastPracticeDate`) directly to the App Group — widgets render from that snapshot, not SwiftData, so a bare reload would re-render stale numbers — then calls `WidgetDataProvider.resetTodayFingerprint()` so the change gate reports a diff on Today's next visit and the full payload is rewritten wholesale, then reloads timelines.
7. **Refresh cadence:** `StreakWidget` uses one calm state ("Still open today"), never an escalating urgency ladder, and refreshes every two hours or at midnight, whichever comes first. `DailyPromptWidget` schedules `.after(nextMidnight)` — intraday payload changes arrive via fingerprint-gated app reloads, not widget polling.
8. Streak copy is invitational, not a loss warning. No red panic state, countdown language, "last chance", or "don't lose it".
9. **Background is `.bigTalkCanvas()`, never a literal color.** It paints the navy gradient plus the brand glow only in `.fullColor`, returns `Color.clear` for `.accented` / `.vibrant` so the system's tint survives, and stays transparent for accessory families. It also scopes the forced dark `colorScheme` to full color - forcing dark unconditionally is what made tinted Home Screens and StandBy render as a dead slab.
10. **Color never carries meaning alone.** Tinted and Lock Screen renders discard hue, so hierarchy comes from the `WidgetPalette` white tiers (`textPrimary` / `textSecondary` / `textTertiary`), and `.widgetAccentable()` marks what belongs in the accent group - headers, ring fills, meter fills, key glyphs.
11. **Widget color lives in `WidgetPalette`, not in the data layer.** `WidgetPalette.score(for:)` mirrors `AppColors.scoreColor(for:)`; the widget target cannot import app types, so the hex values are duplicated and must be kept in sync. Do not reach for `Color.teal` / `.orange` / `.green` - they are off-brand against `AppColors`.
12. `todaysPromptText` reads back empty when the app has never written a prompt. Widgets own the empty-state copy; the data layer does not return instructional text dressed as a prompt.

## Cross-links

[today-library.md](./today-library.md) · [architecture.md](./architecture.md) · [monetization.md](./monetization.md) · [stories.md](./stories.md) · `/docs/AGENT_GOTCHAS.md` · `/docs/AGENT_PLAYBOOK.md`
