# Agent gotchas — silent failures & traps

Read this when touching concurrency, SwiftData queries, media URLs, shares, or widgets. These are the failure modes that **do not announce themselves** until compile, crash, or a bad App Store build.

Companion: [AGENT_PLAYBOOK.md](./AGENT_PLAYBOOK.md) (workflows) · feature index: [features/README.md](./features/README.md).

---

## 1. Default actor isolation is MainActor

**Fact:** `SpeakUp.xcodeproj` sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`.

Every new type without an isolation annotation is **MainActor-isolated by default**. That breaks:

- Pure scoring / monetization / link parsing used from tests or background queues
- `Task.detached` / `DispatchQueue.global` workers that touch those types
- Analytics sinks that must log off the main actor

**Do this:**

| Kind of type | Annotation |
|--------------|------------|
| Pure value / policy / DTO (`SpeechAnalysis`, `FreeTierPolicy`, `UniversalLink`, `RecordingSummary`, …) | `nonisolated struct` / `nonisolated enum` |
| Background sink / helper that must not hop UI | `nonisolated final class` (see `LocalAnalyticsSink`) |
| UI ViewModel / UI service | `@MainActor` (often already implied) |

**Proven fix:** commit `d40543a` — MainActor-default isolation breaking background analytics and pure types.

**Environment keys:** prefer explicit `EnvironmentKey` over `@Entry` under this flag (see comment on `AppTourKey` in `AppTourView.swift`).

---

## 2. Never `#Predicate` on Codable blob columns

`Recording.analysis` is a Codable composite attribute. A predicate like `#Predicate { $0.analysis != nil }` raises an **ObjC exception inside CoreData SQL generation**. It is **not** a Swift `Error` — `try?` cannot catch it; the process terminates.

**Proxy used in code:** count / filter via `transcriptionText != nil` (transcript + analysis persist in the same save). See `RecordingProcessingCoordinator.analyzedRecordingCount`.

Same rule for any other non-Queryable transformed / blob attribute — if unsure, fetch IDs on a simple column and filter in Swift off the main thread.

---

## 3. Background projection recipe (lists & charts)

**Never** `@Query` all `Recording`s into a list body that touches `analysis` or full transcripts.

Canonical pattern (`HistoryViewModel.fetchSummaries`, `ProgressChartsView`):

```swift
nonisolated struct RecordingSummary: Identifiable, Hashable, Sendable { /* POD fields */ }

await Task.detached(priority: .userInitiated) {
    let context = ModelContext(container)
    // fetch → map to POD → return Sendable result
}
```

- Decode analysis **only** on the background context while building the POD.
- Prefer `propertiesToFetch` when you need a few columns (`StreakDetailView`, some `SpeakUpApp` paths).
- Re-fetch by `id` after long jobs (transcription can run ~90s); writing a deleted SwiftData object traps — see `RecordingProcessingCoordinator`.

---

## 4. Media URLs are relative

`Recording` stores `audioURL` / `videoURL` / `thumbnailURL` via `Recording.relativeURL(from:)`. Resolve with `resolvedAudioURL` / `resolvedVideoURL`.

Writing absolute Documents paths breaks after container moves, reinstall, or iCloud migration.

Resolve existence **once** into `@State` — never `FileManager.fileExists` inside `body`.

---

## 5. Monetization call matrix (wrong gate = silent product bug)

| API | When | Call sites (today) |
|-----|------|--------------------|
| `PaywallCoordinator.allow(_:trigger:)` | Feature action: proceed **or** show paywall; **fail-open** if first-result suppressed | Journal export (`ContentView`), iCloud enable (`SettingsView`) |
| `PaywallCoordinator.shared.present(..., userInitiated: true)` | Explicit Unlock / locked CTA | Today allowance, Curriculum phase, deferred analysis, `LifetimeStatusRow` |
| `AllowanceGate.decision` | May we analyze / meter copy | Coordinator enqueue/process, detail deferred UI, status row |
| `AllowanceGate.consume` | **Only after successful analysis persist** | `RecordingProcessingCoordinator` only |
| `EntitlementStore` / `FreeTierPolicy.gates` | Membership checks | Curriculum lock, `allow` internals |

**Do not:**

- Consume allowance on record tap or failed transcribe
- Auto-present paywall before first completed result unless `userInitiated: true`
- Gate `progressCards` by default (`FreeTierPolicy.default` omits it — `MonetizationTests` pins this)
- Scatter `if EntitlementStore.shared.isLifetime` — change membership in `FreeTierPolicy.default.gatedFeatures`

Full policy: [features/monetization.md](./features/monetization.md).

---

## 6. DI: env trio vs singletons

**`.environment` from `SpeakUpApp` (only these three):** `SpeechService`, `AudioService`, `LLMService` → `@Environment(X.self)`.

**Singletons — use `.shared`, do not invent new Environment keys or recreate:**  
`PaywallCoordinator`, `PurchaseService`, `EntitlementStore`, `RecordingProcessingCoordinator`, `AnalyticsService`, `AttributionStore`, `ReviewRequestService`, `ICloudStorageService`, `ChirpPlayer`.

**Custom `EnvironmentKey`s today:** `appTour` (`AppTourKey`), `shimmerPhase` (`ShimmerPhaseKey`).

Local `AudioService()` in onboarding / drills can be **session-scoped on purpose** — do not “fix” by always forcing the app-wide env instance without reading the call site.

---

## 7. Shares go through `SharePresenter`

Both score cards and Then-vs-Now cards must use `SharePresenter.present(...)`. It logs `.shareCompleted` only when the user **completes** the share (dismiss ≠ share). A second `UIActivityViewController` will desync growth analytics. Score-card shares may pass a `message` (prompt quote + try-this-prompt URL) as an extra item on that same call; do not present a second sheet.

---

## 8. Dual `WidgetDataProvider`

| Process | File |
|---------|------|
| App (write) | `SpeakUp/Services/WidgetDataProvider.swift` |
| Widget (read) | `SpeakUpWidget/WidgetDataProvider.swift` |

App Group: `group.com.speakup.shared` (also caches entitlement). Change keys / payload shapes in **both** files. Reload timelines only via fingerprint gate in `TodayViewModel`.

---

## 9. Onboarding & first-run order

Before any `Views/Onboarding/` or onboarding path in `ContentView`: read **`ONBOARDING_VISION.md`**.

Post-onboarding sequence after first score: `FirstRecordingSetupSheet` → `AppTourView` (anchors via `.tourAnchor`; model on `ContentView`). Do not invent a third first-run coach.

---

## Top 10 “you will break production”

1. New pure type without `nonisolated` under MainActor default.  
2. `#Predicate` on `Recording.analysis` (or other Codable blobs).  
3. Decode analysis / huge transcripts in list `body` / unbounded `@Query`.  
4. `AllowanceGate.consume` before success, or gate `progressCards` by default.  
5. Auto-paywall before first result without `userInitiated: true`.  
6. New paid feature via scattered `isLifetime` instead of `FreeTierPolicy`.  
7. Recreate StoreKit / coordinator singletons.  
8. Absolute media paths; skip `resolvedAudioURL`.  
9. Edit only one of the two `WidgetDataProvider`s.  
10. Change onboarding without the vision contract (prompt stays visible, user presses record, first score ≠ grade).
