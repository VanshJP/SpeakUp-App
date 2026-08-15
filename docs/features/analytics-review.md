# Analytics, attribution, review prompts

## Purpose

On-device behavioural logging (no upload by default), install/deep-link attribution, and throttled `SKStoreReviewController` asks.

## Key files

| Role | Path |
|------|------|
| Analytics | `SpeakUp/Services/AnalyticsService.swift` |
| Events | `SpeakUp/Models/AnalyticsEvent.swift` |
| Attribution | `SpeakUp/Services/AttributionStore.swift` |
| Review | `SpeakUp/Services/ReviewRequestService.swift`, `Models/ReviewEligibility.swift` |
| Diagnostics UI | `SpeakUp/Views/Settings/AnalyticsDiagnosticsView.swift` |
| Links | `Models/UniversalLink.swift`, `Config/apple-app-site-association` |
| Tests | `SpeakUpTests/SharingAndReviewTests.swift`, `UniversalLinkTests.swift`, `SharedPromptLinkTests.swift` |

## Invariants

1. Default sink is **local only** (`LocalAnalyticsSink`). Swap via `use(sink:)` — do not ship PII / audio / transcripts / exact scores. Use bucketed dimensions.
2. Attribution is **first-win** from query (`source` / `utm_source` / …). Delay `first_open` briefly (~2s) so deep links can win.
3. Review triggers: `strong_result` / `share_completed` / `achievement_unlocked`. Rules in `ReviewEligibility`: once per launch, after first result, **not on paywall**, once per version, ≥60 days between asks.
4. Shares must go through `SharePresenter` so `.shareCompleted` fires only on **completed** shares (dismiss ≠ share). The score-card caption (prompt quote + try-link) is an extra activity item on that same presenter — do not add a second `UIActivityViewController`.
5. Product-page attribution notes: `APP_STORE_PRODUCT_PAGES.md`.

## Cross-links

[monetization.md](./monetization.md) · [architecture.md](./architecture.md) · [recording-detail.md](./recording-detail.md) · [achievements-goals.md](./achievements-goals.md) · `/docs/AGENT_GOTCHAS.md` · `/RELEASE_CHECKLIST.md`
