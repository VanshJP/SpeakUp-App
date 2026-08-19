# Agent gotchas — silent failures

Open this for concurrency, SwiftData queries, media URLs, shares, widgets, or audio-thread work. These fail at compile, crash, or App Store — they do not announce themselves.

Companion: [AGENT_PLAYBOOK.md](./AGENT_PLAYBOOK.md) · index: [features/README.md](./features/README.md).

## Jump

| Symptom / intent | § |
|------------------|---|
| Background type / test / `Task.detached` won't compile or deadlocks | 1 |
| Crash inside CoreData SQL, `#Predicate`, `analysis != nil` | 2 |
| History/charts hitch; decode in `body` | 3 |
| Audio/video 404 after reinstall or iCloud | 4 |
| Allowance leak, paywall, `isLifetime` | 5 |
| New `@Environment` for StoreKit / coordinator | 6 |
| Share sheet / analytics desync | 7 |
| Widget stale or missing keys | 8 |
| Missing transcript chunks / audio-thread `EXC_BAD_ACCESS` / audio leaving device | 9 |
| Onboarding / first-run coach | 10 |
| Full-screen page pans sideways | 11 |

## Punch list

1. New pure type without `nonisolated` under MainActor default.
2. `#Predicate` on `Recording.analysis` (or any Codable blob).
3. Decode analysis / huge transcripts in list `body` / unbounded `@Query`.
4. `AllowanceGate.consume` before success, or gate `progressCards` by default.
5. Auto-paywall before first result without `userInitiated: true`.
6. New paid feature via scattered `isLifetime` instead of `FreeTierPolicy`.
7. Recreate StoreKit / coordinator singletons.
8. Absolute media paths; skip `resolvedAudioURL`.
9. Edit only one of the two `WidgetDataProvider`s.
10. Change onboarding without `ONBOARDING_VISION.md`.
11. Lower `noSpeechThreshold` "to catch more speech" — it deletes 30 s windows.
12. Make `requiresOnDeviceRecognition` conditional — audio leaves the device.
13. `installTap` / `removeTap` on a running `AVAudioEngine` — audio-thread segfault, no app frames.
14. Plain `ScrollView` for a full-screen page — use `PageScrollView`.

---

## 1. Default actor isolation is MainActor

`SpeakUp.xcodeproj` sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Unannotated types are MainActor-isolated.

Breaks: pure scoring / monetization / link parsing from tests or background queues; `Task.detached` / `DispatchQueue.global` workers; analytics sinks that must log off the main actor.

| Kind | Annotation |
|------|------------|
| Pure value / policy / DTO (`SpeechAnalysis`, `FreeTierPolicy`, `UniversalLink`, `RecordingSummary`, …) | `nonisolated struct` / `nonisolated enum` |
| Background sink / helper | `nonisolated final class` (see `LocalAnalyticsSink`) |
| UI ViewModel / UI service | `@MainActor` (often already implied) |

Proven fix: commit `d40543a`. Prefer explicit `EnvironmentKey` over `@Entry` (see `AppTourKey` in `AppTourView.swift`).

---

## 2. Never `#Predicate` on Codable blob columns

`Recording.analysis` is a Codable composite. `#Predicate { $0.analysis != nil }` raises an **ObjC exception inside CoreData SQL generation**. Not a Swift `Error` — `try?` cannot catch it; the process dies.

Proxy: filter via `transcriptionText != nil` (transcript + analysis persist in the same save). See `RecordingProcessingCoordinator.analyzedRecordingCount`.

Same rule for any transformed / blob attribute. If unsure: fetch IDs on a simple column, filter in Swift off the main thread.

---

## 3. Background projection (lists & charts)

Never `@Query` all `Recording`s into a list body that touches `analysis` or full transcripts.

Canonical pattern (`HistoryViewModel.fetchSummaries`, `ProgressChartsView`):

```swift
nonisolated struct RecordingSummary: Identifiable, Hashable, Sendable { /* POD fields */ }

await Task.detached(priority: .userInitiated) {
    let context = ModelContext(container)
    // fetch → map to POD → return Sendable result
}
```

Decode analysis **only** on the background context while building the POD. Prefer `propertiesToFetch` for a few columns (`StreakDetailView`, some `SpeakUpApp` paths). Re-fetch by `id` after long jobs (transcription ~90s); writing a deleted SwiftData object traps — see `RecordingProcessingCoordinator`.

---

## 4. Media URLs are relative

`Recording` stores `audioURL` / `videoURL` / `thumbnailURL` via `Recording.relativeURL(from:)`. Resolve with `resolvedAudioURL` / `resolvedVideoURL`.

Absolute Documents paths break after container moves, reinstall, or iCloud migration.

Resolve existence **once** into `@State` — never `FileManager.fileExists` inside `body`.

---

## 5. Monetization call matrix (wrong gate = silent product bug)

| API | When | Call sites |
|-----|------|------------|
| `AllowanceGate.decision` | May we analyze / meter copy | Coordinator enqueue/process, detail deferred UI, status row |
| `AllowanceGate.consume` | **Only after successful analysis persist** | `RecordingProcessingCoordinator` only |
| `EntitlementStore` / `FreeTierPolicy.gates` | Membership | `AllowanceGate` only |

**Beta:** paywall UI is deleted and `BetaAccess.allFeaturesFree` is true, so nothing gates in the UI and `AllowanceGate` always answers `.unlimited`. Read [features/monetization.md](./features/monetization.md) before adding a gate.

Do not: consume on record tap or failed transcribe; auto-present paywall before first completed result unless `userInitiated: true`; gate `progressCards` (both policies omit it — `MonetizationTests` pins this); scatter `if EntitlementStore.shared.isLifetime` — change membership in `FreeTierPolicy.trial` / `.expired`.

### Gate and charge are ~90s apart — reserve in between

`decision` reads counters; `consume` writes them after transcription succeeds. Two concurrent `process` runs can both read the same `remaining`. `RecordingProcessingCoordinator.reservedAnalyses` holds a claim; the gate subtracts it. Any new site that gates on `decision` and charges after an `await` needs the same reservation.

---

## 6. DI: env trio vs singletons

**`.environment` from `SpeakUpApp` (only these three):** `SpeechService`, `AudioService`, `LLMService` → `@Environment(X.self)`.

**Singletons — `.shared`, do not invent Environment keys or recreate:**  
`PurchaseService`, `EntitlementStore`, `RecordingProcessingCoordinator`, `AnalyticsService`, `AttributionStore`, `ReviewRequestService`, `ICloudStorageService`, `ChirpPlayer`.

**Custom `EnvironmentKey`s today:** `appTour` (`AppTourKey`), `shimmerPhase` (`ShimmerPhaseKey`).

Local `AudioService()` in onboarding / drills can be **session-scoped on purpose** — do not "fix" by always forcing the app-wide env instance without reading the call site.

---

## 7. Shares go through `SharePresenter`

Score cards and Then-vs-Now cards use `SharePresenter.present(...)`. It logs `.shareCompleted` only when the user **completes** the share (dismiss ≠ share). A second `UIActivityViewController` desyncs growth analytics. Score-card shares may pass a `message` (prompt quote + try-this-prompt URL) as an extra item on that same call.

---

## 8. Dual `WidgetDataProvider`

| Process | File |
|---------|------|
| App (write) | `SpeakUp/Services/WidgetDataProvider.swift` |
| Widget (read) | `SpeakUpWidget/WidgetDataProvider.swift` |

App Group: `group.com.speakup.shared` (also caches entitlement). Change keys / payload shapes in **both** files. Reload timelines only via fingerprint gate in `TodayViewModel`.

---

## 9. Speech recognition: audio-thread and audio-eater traps

**`DecodingOptions.noSpeechThreshold` is the silence trigger, not a sensitivity dial.** WhisperKit throws away an entire 30 s window — no error, no gap marker, seek jumps forward — when `noSpeechProb >` the threshold and the window also fails `logProbThreshold` (`SegmentSeeker.findSeekPointAndSegments`). **Lowering it drops more audio, not less.** 0.4 vs the 0.6 default deleted quiet stretches in the middle and back half of recordings. Same shape for `temperatureFallbackCount`: cutting it below default writes off marginal windows a retry would have decoded.

**Never `installTap` / `removeTap` on a *running* `AVAudioEngine`.** Installing a tap makes AVAudioEngine set the input node's output format, which reconfigures `AURemoteIO`'s converter while its realtime IO thread is inside `AUHALOutputUnit_InputAvailableCallback` — callback pointer goes null, `EXC_BAD_ACCESS` on the audio thread, backtrace names no app code. `LiveTranscriptionService` hit this ~60 s into every session when SFSpeech auto-finalized and `restartRecognitionPreservingEngine` re-installed the tap. **Install the tap once, before `engine.start()`.** To re-arm recognition, swap the `SFSpeechAudioBufferRecognitionRequest` the tap block appends to (`requestBox`, `OSAllocatedUnfairLock`) and leave the tap alone. Teardown: `engine.stop()` *before* `removeTap`. Same rule for `DictationService` / `ReadAloudService`.

**`requiresOnDeviceRecognition` must be `true` unconditionally** on every `SFSpeech*RecognitionRequest` (`SpeechService`, `DictationService`, `LiveTranscriptionService`, `ReadAloudService`). Unset, the recognizer may stream microphone audio to Apple. `APP_STORE_LISTING.md` §3 claims the app transmits nothing. Do **not** guard with `if recognizer.supportsOnDeviceRecognition` — that reads false while assets install, which is exactly when audio would leave the device. An unavailable recognizer must fail loudly.

---

## 10. Onboarding & first-run order

Before any `Views/Onboarding/` or onboarding path in `ContentView`: read **`ONBOARDING_VISION.md`**.

Post-onboarding after first score: `FirstRecordingSetupSheet` → `AppTourView` (anchors via `.tourAnchor`; model on `ContentView`). Do not invent a third first-run coach.

---

## 11. Full-screen pages use `PageScrollView`

A plain `ScrollView` pans sideways the moment a child measures wider than the viewport. Use `PageScrollView`. Deliberate horizontal rails stay `ScrollView(.horizontal)`. Details: [features/ui-design-system.md](./features/ui-design-system.md).
