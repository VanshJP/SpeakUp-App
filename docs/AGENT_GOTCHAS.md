# Agent gotchas — silent failures

Open this for concurrency, SwiftData queries, media URLs, shares, widgets, or audio-thread work. These fail at compile, crash, or App Store — they do not announce themselves.

Companion: [AGENT_PLAYBOOK.md](./AGENT_PLAYBOOK.md) · index: [features/README.md](./features/README.md).

## Jump

| Symptom / intent | § |
|------------------|---|
| Background type / test / `Task.detached` won't compile or deadlocks | 1 |
| Crash inside CoreData SQL, `#Predicate`, `analysis != nil` | 2 |
| Advanced analysis metrics nil after reopen; stale mirror | 2b |
| History/charts hitch; decode in `body` | 3 |
| Audio/video 404 after reinstall or iCloud | 4 |
| Allowance leak, paywall, `isLifetime` | 5 |
| New `@Environment` for StoreKit / coordinator | 6 |
| Share sheet / analytics desync | 7 |
| Widget stale or missing keys | 8 |
| Missing transcript chunks / audio-thread `EXC_BAD_ACCESS` / audio leaving device | 9 |
| Onboarding / first-run coach | 10 |
| Full-screen page pans sideways | 11 |
| SwiftData fetch traps in unit tests (iOS 26.5 runner) | 12 |
| Fresh simulator runtime: NLP tagger returns nothing | 13 |
| `@Observable` dict literal `[]` won't compile | 14 |
| Giant modifier chain → bogus "no return statements" | 15 |
| Direct `AVAudioFile` decode in scoring consumers | 16 |
| Legacy store + `SchemaV1`: verify before release; CloudKit-strip fallback | 17 |
| New projection column reads nil on legacy rows | 18 |
| CloudKit push warning / cfprefsd "detaching" console noise | 19 |

## Punch list

1. New pure type without `nonisolated` under MainActor default.
2. `#Predicate` on `Recording.analysis` (or any Codable blob).
2b. `recording.analysis = …` instead of `setAnalysis(_:)`, or reading `analysis` where the advanced metrics are needed — they are nil on anything read back from the store.
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

## 2b. SwiftData drops the advanced analysis metrics

`SpeechAnalysis.init(from:)` sets `enhancedMetrics`, `textQuality`, `sentenceAnalysis`, `vocabComplexity`, `pitchMetrics`, `volumeMetrics`, `rateVariation`, `emphasisMetrics`, `energyArc`, `wpmTimeSeries`, the isolation metrics, and `promptRelevanceScore` to **nil** whenever it is not the mirror decoder. That is deliberate and must stay: SwiftData's internal decoder throws `EXC_BREAKPOINT` on those nested optionals, which is an uncatchable trap, not a Swift error.

The consequence is easy to miss because it does not show up in the session that produced the recording — the struct is still in memory there. It shows up on **every read after that**: reopen the app, and an analysis fetched from the store carries only the headline numbers.

`Recording.analysisJSON` is a full-fidelity JSON mirror written beside `analysis`, decoded through `SpeechAnalysis.decodedMirror(_:)` with `fullFidelityKey` set. Foundation's decoder throws rather than trapping, so it can afford to decode what SwiftData cannot.

- **Write** through `Recording.setAnalysis(_:)`, never `recording.analysis = …`. A direct assignment leaves the mirror stale.
- **Read** `Recording.fullAnalysis` anywhere the advanced metrics matter — and never from a view `body`, it decodes JSON. Resolve once into `@State`.
- A read-modify-write cycle (the LLM coherence pass) **must** start from `fullAnalysis`, or it persists a stripped analysis over a good mirror.
- Aggregations that only need `speechScore` (baselines, the coaching plan) should keep using `analysis` — decoding a window of mirrors to reach nine integers each is pure cost.

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

---

## 12. SwiftData traps inside the iOS 26.5 simulator test runner

On Xcode 26.6 / iOS 26.5, **any** `ModelContainer` fetch or insert in a unit test traps `EXC_BREAKPOINT` inside SwiftData — while the shipping app runs the identical code path on the identical runtime. Test-runner regression, not a product bug; do not "fix" the app. The three container tests in `SharedPromptResolverTests` (struct lives in `SpeakUpTests/SharedPromptLinkTests.swift`) are `.disabled("SwiftData traps in iOS 26.5 test runner (Xcode 26.6)")` until the toolchain is fixed — re-enable them then.

---

## 13. Fresh simulator runtimes have no on-device NLP models

A brand-new simulator runtime ships without the NLP assets, so `NLTagger(.lexicalClass)` returns **zero tags** — no error. Every signal downstream of lexical tagging (gibberish recognized-ratio, content-word density) silently degrades to its no-data path, and characterization assertions written against real tags fail for reasons that have nothing to do with the code. Tests gate on the `NLPCapability.lexicalTaggingWorks` probe (`SpeechScoringEngineCharacterizationTests`) instead of assuming tags exist; keep it that way.

---

## 14. Init `@Observable` dictionaries with `[:]`, never `[]`

An `@Observable` type's dictionary-typed stored property initialized with `[]` trips the `ObservationTracked` macro: *"use [:] to get an empty dictionary literal"*. Arrays accept `[]`; dictionaries do not. Always write `[:]`.

---

## 15. Giant SwiftUI builder chains blow the type-checker budget

10+ chained modifiers — especially ones carrying `Binding`s — under MainActor-default isolation can exceed the type-checker's budget and surface as bogus *"no return statements"* errors pointing at a body that plainly returns. Split trailing modifier clusters into `private func` helpers taking a `some View` base with explicit `return` (the pattern used across `Views/`); don't contort the body.

---

## 16. Audio consumers take `MonoPCM`, not `AVAudioFile`

Pre-refactor, one analysis whole-file-decoded the PCM three times (isolation preprocess, speaker labeling, pitch), materializing ~115 MB per 10-minute take each time. Now every consumer takes a `MonoPCM` value and decodes via `MonoPCM.decode(url:)` only where its gating requires samples — short takes that gate out of speaker labeling decode nothing. Do not reintroduce direct `AVAudioFile` reads in scoring consumers.

---

## 17. Opening a pre-`SchemaV1` store through the versioned schema is unverified on device

Every shipped install wrote its store under an *unversioned* schema; the container now opens stores through `Schema(versionedSchema: SchemaV1.self)` with an empty-stage `SpeakUpMigrationPlan`. Lightweight migration is expected to handle this silently, but no test or device run has opened a HEAD-era store through the new plan — SwiftData traps aren't catchable in unit tests on this toolchain (see §12's cousin problem). **Before the next release build: install over a pre-upgrade store and confirm launch + data.** If container creation ever throws, the fallback chain strips CloudKit first (`SpeakUpApp` logs "falling back to local store" — sync dies quietly for that launch) and then goes in-memory (app looks empty).

---

## 18. Legacy rows carry nil denormalized projections until first touch

`Recording.promptId` / `overallScore` are additive columns: rows written before they existed read nil forever unless something writes them. Consumers must fall back to the source of truth (`recording.prompt?.id`, `fullAnalysis`) rather than treating nil as unknown-and-skip — nil means *legacy*, not *missing*. The AllPrompts progress scan backfills `promptId` opportunistically; do the same for any new projection column before shipping a scalar-only reader.

---

## 19. Console noise that is (and is not) a bug

**`BUG IN CLIENT OF CLOUDKIT: … 'remote-notification' background mode`** — real misconfiguration when the sync toggle is on: CloudKit push needs `UIBackgroundModes = [remote-notification]` in the app's Info.plist. It lives in `SpeakUp/Info.plist`; if it ever disappears, subscriptions stop delivering and widgets/notifications silently degrade.

**`CFPrefsPlistSource … kCFPreferencesAnyUser with a container … detaching from cfprefsd`** — fired by touching an App Group suite from a process that does not hold the entitlement (Xcode Previews, some test hosts). Harmless to the shipping app, but don't chase it with re-runs. Both `WidgetDataProvider`s guard on `FileManager.containerURL(forSecurityApplicationGroupIdentifier:) != nil` before touching the suite and return nil otherwise — keep that guard; never "fix" it by falling back to `.standard`, which would write widget data into a domain the widget can never read.
