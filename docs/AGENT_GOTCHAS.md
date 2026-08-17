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
- Gate `progressCards` in either policy (`.trial` / `.expired` both omit it — `MonetizationTests` pins this)
- Scatter `if EntitlementStore.shared.isLifetime` — change membership in `FreeTierPolicy.trial` / `.expired`

### Gate and charge are ~90s apart — reserve in between

`AllowanceGate.decision` reads persisted counters; `AllowanceGate.consume` writes them only after transcription succeeds. Nothing serialises two different recordings, so two concurrent `process` runs both read the same `remaining` and both pass. `RecordingProcessingCoordinator.reservedAnalyses` holds a claim across that window and the gate subtracts it.

Any new site that gates on `decision` and charges after an `await` needs the same reservation, or the free allowance leaks. Silent — it looks like a generous free tier, not a bug.

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

## 9. Speech recognition: two silent audio-eaters

**`DecodingOptions.noSpeechThreshold` is the silence trigger, not a sensitivity dial.** WhisperKit throws away an entire 30 s window — no error, no gap marker, seek just jumps forward — when `noSpeechProb >` the threshold and the window also fails `logProbThreshold` (`SegmentSeeker.findSeekPointAndSegments`). **Lowering it drops more audio, not less.** A value of 0.4 against the 0.6 default was deleting quiet stretches out of the middle and back half of recordings. Same trap shape for `temperatureFallbackCount`: cutting it below the default writes off marginal windows a retry would have decoded.

**`requiresOnDeviceRecognition` must be set to `true` unconditionally** on every `SFSpeech*RecognitionRequest` (`SpeechService`, `DictationService`, `LiveTranscriptionService`, `ReadAloudService`). Unset, the recognizer may stream microphone audio to Apple's servers; `APP_STORE_LISTING.md` §3 claims the app transmits nothing. Do **not** guard it with `if recognizer.supportsOnDeviceRecognition` — that reads false while assets install, which is exactly when audio would leave the device. An unavailable recognizer must fail loudly.

---

## 10. Onboarding & first-run order

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
9b. Plain `ScrollView` for a full-screen page — it pans sideways the moment a child measures wider than the viewport. Use `PageScrollView`.  
10. Change onboarding without the vision contract (prompt stays visible, user presses record, first score ≠ grade).  
11. Lower `noSpeechThreshold` "to catch more speech" — it silently deletes whole 30 s windows.  
12. Make `requiresOnDeviceRecognition` conditional — audio leaves the device exactly when the flag reads false.
