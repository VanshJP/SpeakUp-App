# Agent gotchas — silent failures

Open this for concurrency, SwiftData queries, media URLs, shares, widgets, or audio-thread work. These fail at compile, crash, or App Store — they do not announce themselves.

Companion: [AGENT_PLAYBOOK.md](./AGENT_PLAYBOOK.md) · index: [features/README.md](./features/README.md).

## Jump

| Symptom / intent | § |
|------------------|---|
| Background type / test / `Task.detached` won't compile or deadlocks; isolation DSP on MainActor | 1 |
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
| A root tab's toolbar item renders nowhere; a pushed page loses Back | 20 |
| Chart fill bleeds out of its card; marks draw outside the plot | 21 |
| A control inside a glass card reads as a grey band, not a button | 22 |
| A button does nothing until an entrance animation finishes | 23 |
| Layout jumps or insets are wrong on a non-key window | 24 |
| Highlighted text drifts while it updates; long session freezes then the app dies | 25 |
| Mic dies partway through a long session and the screen freezes on "Not listening" | 26 |
| Read Aloud snaps back toward word one after a pause; drill word / filler counts stop growing | 9, 26 |
| Screen dims or locks in the middle of a drill, warm-up or read | 26 |
| A sheet or cover opens blank, closes itself, and works on the second tap | 27 |
| An animation that never plays: confetti invisible, chart draw-in pops | 28 |
| App freezes for seconds right after a take ends (hang HUD on the self-check) | 29 |

## Punch list

1. New pure type without `nonisolated` under MainActor default.
2. `#Predicate` on `Recording.analysis` (or any Codable blob).
2b. `recording.analysis = …` instead of `setAnalysis(_:)`, or reading `analysis` where the advanced metrics are needed — they are nil on anything read back from the store.
3. Decode analysis / huge transcripts in list `body` / unbounded `@Query`.
4. `AllowanceGate.consume` before success, or gate `progressCards` by default.
5. Auto-paywall before first result without `userInitiated: true`.
6. New paid feature via scattered `isLifetime` instead of `FreeTierPolicy`.
7. Recreate StoreKit / coordinator singletons.
8. Absolute media paths; skip `resolvedAudioURL`; unsanitized `../` filenames.
9. Edit only one of the two `WidgetDataProvider`s.
10. Change onboarding without `ONBOARDING_VISION.md`.
11. Lower `noSpeechThreshold` "to catch more speech" — it deletes 30 s windows.
12. Make `requiresOnDeviceRecognition` conditional — audio leaves the device.
13. `installTap` / `removeTap` on a running `AVAudioEngine` — audio-thread segfault, no app frames.
14. Plain `ScrollView` for a full-screen page — use `PageScrollView`.
15. A `topBarTrailing` toolbar item on a root tab (or on any view inside one) — root tabs have no navigation bar.
16. `AreaMark(x:y:)` on a chart whose y-domain does not start at 0 — the fill runs to zero in data space, outside the card.
17. A `glassEffect` surface nested directly inside a `GlassCard`.
18. Vary font weight, size, tracking or padding by live match state — metrics changes re-flow the whole run.
19. A custom `Layout` with `cache: inout ()` over more than a handful of subviews.
20. One `Task { @MainActor }` per speech-recognition callback — they queue without bound behind a busy main actor.
21. Treat `isFinal` or an error from `SFSpeechRecognitionTask` as the end of the session — it is the end of one *request*, which a pause produces.
22. Present a sheet or cover with `isPresented:` and read its content out of a second `@State` — especially with an `onDismiss` that clears that second one.
23. Store a recognition request's newest transcript as the whole request, or count `max` across results — on device the recognizer restarts a request's transcript after a pause and can send a blank final. Feed results through `RecognitionContinuity` / `RequestTranscript`.
24. A timed practice screen without `keepsScreenAwake` — Auto-Lock fires during a hands-free minute and takes the mic with it.
25. File work on a take's media from the main actor — `setUbiquitous`, iCloud status keys, even `fileExists` in the ubiquity container can wait seconds on the iCloud daemon.

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

Also mark pure audio DSP used from GCD / detached workers: `SpeechIsolationService`, `ConversationIsolationService`, `VoiceProfile`, `VoiceProfileUpdate`. Calling MainActor-isolated isolation from `DispatchQueue.global` inside `SpeechService.transcribe` either hitches UI or fails isolation checking. Never construct `SpeechService()` off-main just to reach `SpeechAnalysisPipeline` statics.

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

Basename only: `ICloudStorageService.resolveFile(named:)` and `Recording.resolveStoredURL` run every name through `MediaPath.sanitizedFilename`. A tampered relative path with `../` must not walk out of Documents / the iCloud container. Legacy absolute URLs are honored only when `MediaPath.isUnderAllowedMediaRoot` says they sit under Documents or the ubiquity container — otherwise fall back to the basename. Pin behaviour in `SpeakUpTests/MediaPathTests`.

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

**`isFinal` is the end of a *request*, not the end of the session.** SFSpeech closes a `SFSpeechAudioBufferRecognitionRequest` after a pause in speech, and again at the request's own audio-duration ceiling (~1 min). A passage read at a natural pace triggers both, repeatedly. Every live recognizer here therefore **re-arms**: swap `requestBox` for a fresh request, leave the engine and tap alone, and carry the transcript forward — `ReadAloudService.segments` (joined by `joinTranscripts`, pinned in `ReadAloudAlignmentTests`), `DictationService.committedWords`, `LiveTranscriptionService.segmentTimeOffset` and its committed counts. Each request's transcript restarts at empty, so publishing the live one alone rewinds the user to the first word. Bound the re-arm: `ReadAloudService` / `DictationService` give up after three requests in a row that die inside a second with nothing to show, which is how a device missing its on-device assets fails — otherwise a dead recognizer spins behind a screen that claims to be listening. `ReadAloudService` also rolls over proactively at 45 s, because swapping early loses nothing while hitting the ceiling drops whatever was in flight.

**A request's transcript is not always one growing string either.** With `requiresOnDeviceRecognition` (mandatory here), SFSpeech can start a request's `bestTranscription` over from empty after a pause of a second or two — same request, `isFinal` still false — and can deliver a final that is blank or holds only the last utterance. Developers have reported it from iOS 17 through iOS 26 (Apple Developer Forums threads 762952, 770278). A consumer that stores the newest result as the request's transcript loses everything before the pause: Read Aloud's alignment snapped the reader back toward word one, drills stopped counting words and fillers, dictation dropped words. Every consumer now runs results through the pure `RecognitionContinuity.classify` (revision / restart / whole request / ignore) — `RequestTranscript` for Read Aloud's text, committed-plus-live counts in `LiveTranscriptionService`, `committedWords` in `DictationService`. Two signals settle the ambiguous cases, and both have to be captured where the result arrives: a result carrying `speechRecognitionMetadata` marks the end of an utterance (Read Aloud keeps those in order in `PendingResults.closed` instead of letting latest-wins coalescing drop them), and a partial arriving after `RecognitionContinuity.restartGap` of quiet is new speech. Stamp that time in the recognition callback, not on the main actor, which can hold results back and hide the pause. Without it a one-word utterance - a dictated word, a lone "um" - is indistinguishable from a revision. Pinned in `RecognitionContinuityTests`.

**A live `AVAudioEngine` dies silently in two more ways, and neither throws.** `.AVAudioEngineConfigurationChange` (AirPods connect, headset unplugged, another app reshapes the session) stops the engine and leaves the tap's format stale. `AVAudioSession.interruptionNotification` (call, Siri, alarm) deactivates the session underneath it. Observe both for the lifetime of a capture graph and rebuild — stop, `removeTap`, new engine, install tap, start, re-arm — keeping the accumulated transcript. `ReadAloudService.rebuildCaptureGraph` and `LiveTranscriptionService.rebuildEnginePreservingCounts` are the two copies; a new engine owner needs its own. Re-activate the session off the main actor (`setActive` blocks until the audio server answers) and re-check that the owner is still listening and unheld before building the engine, since a hold or Done can land in the gap.

**A capture session left as `.record` mutes the whole app.** `AVSpeechSynthesizer` plays through the shared session and sets no category of its own, so after dictation it spoke silently until some other screen reconfigured the session. An owner that takes `.record` hands it back on teardown - `DictationService.cleanup()` restores `.ambient`, synchronously and only while the category is still `.record`, so it never overwrites a screen that configured its own.

**`requiresOnDeviceRecognition` must be `true` unconditionally** on every `SFSpeech*RecognitionRequest` (`SpeechService`, `DictationService`, `LiveTranscriptionService`, `ReadAloudService`). Unset, the recognizer may stream microphone audio to Apple. `APP_STORE_LISTING.md` §3 claims the app transmits nothing. Do **not** guard with `if recognizer.supportsOnDeviceRecognition` — that reads false while assets install, which is exactly when audio would leave the device. An unavailable recognizer must fail loudly.

**WhisperKit `download: true` is not offline-safe after the first install.** Config init asks Hugging Face for the file list *before* it opens the local cache, so flaky Wi‑Fi freezes "Analyzing…" even when `openai_whisper-base` is already under `Documents/huggingface/`. After the first successful download, load with `modelFolder` pointing at that cache and `download: false` (set `tokenizerFolder` to the Hub base so the tokenizer stays local too). Time-box first-time downloads so a dead connection fails into on-device Apple Speech instead of hanging. Never implement such a time-box as a task group: the group awaits the stuck child before rethrowing, so the timeout never returns. Race through a continuation (`WhisperService.FirstFinisher`), and wait on a shared build *task* rather than a semaphore so the waiter escalates its priority.
Require both `AudioEncoder` and `TextDecoder` before treating the cache as offline-ready. After any Whisper timeout (`abandonsWhisper`), skip the raw retry and the reload leg and fall through to Apple Speech. Analyzing UI must key "Downloading…" off an in-flight download flag, not `!isModelLoaded`.

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
Pass the post-Whisper buffer into speaker labeling and pitch via `SpeechTranscriptionResult.monoPCM` — do not re-decode the file for each consumer. Isolation may decode separately before Whisper; do not keep that buffer alive across inference.

---

## 17. Opening a pre-`SchemaV1` store through the versioned schema is unverified on device

Every shipped install wrote its store under an *unversioned* schema; the container now opens stores through `Schema(versionedSchema: SchemaV1.self)` with an empty-stage `SpeakUpMigrationPlan`. Lightweight migration is expected to handle this silently, but no test or device run has opened a HEAD-era store through the new plan — SwiftData traps aren't catchable in unit tests on this toolchain (see §12's cousin problem). **Before the next release build: install over a pre-upgrade store and confirm launch + data.** If container creation ever throws, the fallback chain strips CloudKit first (`SpeakUpApp` logs "falling back to local store" — sync dies quietly for that launch) and then goes in-memory (app looks empty).

---

## 18. Legacy rows carry nil denormalized projections until first touch

`Recording.promptId` / `overallScore` are additive columns: rows written before they existed read nil forever unless something writes them. Consumers must fall back to the source of truth (`recording.prompt?.id`, `analysis` / `fullAnalysis`) rather than treating nil as unknown-and-skip — nil means *legacy*, not *missing*. The AllPrompts progress scan backfills `promptId` opportunistically; do the same for any new projection column before shipping a scalar-only reader.

Score aggregations (Today heavy load, History summaries, practice charts) should read `overallScore ?? analysis?.speechScore.overall` and bind `let analysis = recording.analysis` once per row — each property access re-decodes the Codable blob.

---

## 19. Console noise that is (and is not) a bug

**`BUG IN CLIENT OF CLOUDKIT: … 'remote-notification' background mode`** — real misconfiguration when the sync toggle is on: CloudKit push needs `UIBackgroundModes = [remote-notification]` in the app's Info.plist. It lives in `SpeakUp/Info.plist`; if it ever disappears, subscriptions stop delivering and widgets/notifications silently degrade.

**`CFPrefsPlistSource … kCFPreferencesAnyUser with a container … detaching from cfprefsd`** — fired by touching an App Group suite from a process that does not hold the entitlement (Xcode Previews, some test hosts). Harmless to the shipping app, but don't chase it with re-runs. Both `WidgetDataProvider`s guard on `FileManager.containerURL(forSecurityApplicationGroupIdentifier:) != nil` before touching the suite and return nil otherwise — keep that guard; never "fix" it by falling back to `.standard`, which would write widget data into a domain the widget can never read.

---

## 20. Root tabs have no navigation bar

All five root tabs hide it (`.toolbar(.hidden, for: .navigationBar)`): the bar's only content was the tab's own name, repeated from the tab button under it, and `.searchable` hung ~50pt more off it.

Two consequences, both silent:

- **A `topBarTrailing` `ToolbarItem` declared anywhere inside a root tab renders nowhere.** There is no bar to put it in, and nothing warns. `AllPromptsView` and `StoriesListView` both used to declare one from inside Library. Put the control in the page instead, wearing `.headerIconChrome()` — next to the chips or list it acts on.
- **A page pushed from a bar-less root should say `.restoresNavigationBar()`.** SwiftUI resolves toolbar visibility per view in the stack, so a push gets its bar back on its own — but a detail page silently missing its Back button is an expensive thing to be wrong about, so the pushes from these four roots declare it.

Search on a root tab is `InlineSearchField` drawn by the **section**, not by the page, and not `.searchable`; it also needs `.scrollDismissesKeyboard(.interactively)`, which `.searchable` used to supply. Its trailing slot is where that section's filter or sort menu goes — not the end of a chip row or folder bar, where the rail scrolls underneath the button. Full rules: [features/ui-design-system.md](./features/ui-design-system.md) §9.

---

## 21. `AreaMark` fills to zero in *data* space, and Charts does not clip

`AreaMark(x:y:)` with no `yStart` fills from **0**, not from the bottom of the plot. Any chart whose `chartYScale` domain starts above zero therefore draws its gradient below the plot rect — and Swift Charts does not clip marks to the plot area by default, so the fill keeps going straight out of the `GlassCard` and down the page. That is what the blue wash under the Overall Score trend was: its domain is `min(score) - 10 … max(score) + 10`.

Fix is per-mark, not per-chart: pass the domain floor explicitly.

```swift
AreaMark(
    x:      .value("Date", point.date),
    yStart: .value("Baseline", model.yDomain.lowerBound),
    yEnd:   .value("Score", point.score)
)
```

`ScoreProgressChart` (`ProgressChartsView`) and `WPMChartView` both compute a non-zero floor and both needed it. `PracticeHistoryChart` is pinned to `0...100` so its baseline was already right, but `.interpolationMethod(.catmullRom)` overshoots past 100 on a spiky run — it takes `.chartPlotStyle { $0.clipped() }` instead, which is safe **only** because it draws no `PointMark`s for the clip to cut in half at the plot edges. Do not add that modifier to a chart with point symbols.

---

## 22. Glass on glass samples glass

Liquid Glass samples what is behind it. A second `glassEffect` laid straight on a `GlassCard` therefore samples the plate rather than the canvas, and renders as a murky grey band where a control should be. It is worst on tall cards, which is how it showed up on the Today focus card once its CTA moved to `GlassButton.secondary` (a `.glassEffect(…, in: .capsule)`).

`GlassCard`, `FeaturedGlassCard` and `.glassCard()` set `\.isOnGlass` on their content; `GlassButtonChrome` reads it and paints a capsule (white 0.10 fill, 0.16 rim) instead of glassing it. Any new glass surface that can appear inside a card owes the same branch — or wrap both in a `GlassEffectContainer` if two glass surfaces genuinely must share a region. Branch on the environment value, never on animated state (design rule 14: never animate a `glassEffect` on/off).

Symptom without the fix: the control is legible in isolation and in a `#Preview` over `AppBackground`, and only goes grey once it is inside a card — which is why it survived review.

---

## 23. Never gate a control on an appear animation

The pattern is `@State private var ctaOpacity: Double = 0` plus
`withAnimation(…delay(0.15)) { ctaOpacity = 1 }` inside `.onAppear`. The
resting state of that view is *invisible*, and every way of not reaching the
animation — a missed `onAppear`, a cancelled task, a render loop that never
ticks past the delay — leaves the control on screen but transparent, with no
error and nothing in the log.

It has bricked two screens. A fresh install reported the onboarding welcome
cover as the orb on an empty background: "Let's start" was there, at opacity 0,
and it is the one forward action in the app nobody can route around.
`LessonCompletionView` hid both of its exits behind a single shared
`contentOpacity`.

Use `.introReveal(delay:)` (`Theme/AppMotion.swift`). Its resting state is
shown; it only hides once `onAppear` has run, which is the same moment it takes
on responsibility for showing it again, and a backstop task lands the final
state with animations off if the reveal is interrupted. Reduce Motion skips it
entirely. Decoration (a glyph scaling up, a card easing in) can still animate
however it likes — the rule is about anything the user has to tap.

Symptom: the screen renders, nothing is logged, and the user calls it frozen
because from their side it is.

---

## 24. Never read `keyWindow.safeAreaInsets` for layout

`AnalyzingView` carried this, twice:

```swift
private var systemTopSafeAreaInset: CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: \.isKeyWindow)?
        .safeAreaInsets.top ?? 0
}
```

Three things are wrong with it. It is a UIKit read from `body`, so it never
invalidates — during presentation there may be no key window yet and it
returns 0. It is added on top of whatever inset the layout already applied,
and every host in this app insets its content (covers, `NavigationStack`,
`safeAreaInset`), so the usual result is a doubled inset. And the doubling is
device-dependent: +20pt on an SE, +59 on a Pro, +62 on a Pro Max — one screen
that is wrong by a different amount on every iPhone, which reads as "sometimes
it looks fine" and survives review on whatever device the author holds.

Let the layout supply it. `GeometryProxy.safeAreaInsets`, `safeAreaPadding`, or
just a plain constant inside an already-inset container. If the inset really is
being consumed, the bug is the `.ignoresSafeArea()` upstream — fix that instead,
per `features/recording.md` → "Session screens respect the safe area".

Symptom: a close button or header sits a notch too low, and moving to a
different iPhone changes how wrong it is.

## 25. Live-highlight text: state may not change metrics, and `Layout` must cache

Read Aloud highlights the current word as speech recognition advances. Two
traps, both of which look like "the app is slow" rather than like bugs.

**Metrics.** The current word rendered `.bold` while its neighbours stayed
`.regular`. Bold glyphs are wider, so every cursor advance grew one word,
shrank another, and re-flowed everything after them on the line. The passage
squirmed continuously while being read. Draw the whole run at one weight and
carry position with a background fill and colour; never with weight, size,
tracking, or padding that varies by state.

**`Layout` caching.** `WrappingHStack` took `cache: inout ()` and re-measured
every subview in *both* `sizeThatFits` and `placeSubviews`. SwiftUI calls both
on every pass, so a 150-word passage cost ~300 text measurements per pass — and
a pass ran on every partial recognition result, several times a second, on the
main actor. Any `Layout` over a non-trivial number of subviews needs a real
`makeCache` / `updateCache`, keyed on the proposed width plus whatever can
change glyph metrics. A first-subview probe is a cheap tripwire for callers that
do not pass an explicit key.

**What it looked like.** Recognition callbacks each spawned their own
`Task { @MainActor }`. Once the main actor was pinned by the layout thrash those
tasks queued without bound, each retaining an `SFSpeechRecognitionResult`, and
the app froze and was killed roughly twenty seconds into a read. Coalesce
latest-wins with one drain in flight (`ReadAloudService.pendingTranscript` /
`isDrainScheduled`) rather than one task per callback, and lift `String` values
out inside the callback — `SFSpeechRecognitionResult` and `any Error` are not
`Sendable`.

Continuous auto-scroll is part of the same complaint: re-centring every second
word slides the page under the reader. Advance roughly a line at a time.

---

## 26. A long session's mic dies partway through

Every symptom of this is somewhere else. The user sees the read stop advancing
halfway down the passage, the indicator flip to "Not listening", and the Done
button go grey — so the only way out is to abandon the take and start over.

Independent causes, the first three covered in §9, all of which leave the app
*looking* fine:

1. **`isFinal` treated as the end of the session.** A reader pauses between
   sentences, SFSpeech closes the request, and a service that tears down its
   engine there has just turned the mic off mid-passage.
2. **A configuration change** stopping `AVAudioEngine` under a tap that keeps
   being asked for buffers it will never get.
3. **An interruption** deactivating the session, with nothing listening for it
   to end — or never hearing `.ended` at all.
4. **Auto-Lock.** A read, a drill, a breathing round: minutes without a touch.
   The screen locks, the app leaves the foreground, and without a background
   audio mode the engine goes with it. Every runner holds the screen with
   `keepsScreenAwake`, and `ReadAloudService` treats backgrounding as a hold it
   rebuilds from on `didBecomeActive`.

A fifth looks like this bug but is not the mic at all: the recognizer
restarting a request's transcript after a pause (§9). The mic is fine; the
words before the pause vanish from the transcript and the read appears to
start over.

Whatever the cause, nothing about losing the mic may cost the reader their
place. `ReadAloudService` models every loss as a **hold** — model playback,
interruption, background, or a **stall** when automatic recovery fails — that
keeps `segments` and every matched word, stops the clock, and comes back through
`rebuildCaptureGraph`. A stall shows **Resume reading** instead of ending the
session; ending it used to leave Retry, the passage from the top, as the only
way on. The view model still keeps its backstop: if the service is no longer
listening while the session state still says it is, land on the result screen
with the words that were matched. `ReadAloudViewModel.startTimer` holds that
check.

---

## 27. A cover that opens blank, closes itself, and works on the second tap

`fullScreenCover(isPresented:)` / `sheet(isPresented:)` whose content unwraps a
*second* piece of view state is a race, and an `onDismiss` that clears that
second piece makes it a reliable one. SwiftUI runs `onDismiss` **after** the
dismissal animation, so:

```
tap → item = mode, isPresented = true
        ↘ previous dismissal finishes → onDismiss → item = nil
              ↘ cover presents, unwraps nil, draws nothing, closes itself
```

Start a second drill while the first is still animating out and that is exactly
what happens. Tapping again works only because nothing is animating by then.
The same shape without an `onDismiss` still flashes blank whenever the content
state is cleared before the dismissal lands — `viewModel.reset()` before
`dismiss()` is the common one.

**Use `sheet(item:)` / `fullScreenCover(item:)`.** The value is handed to the
content builder, so there is nothing to race and no "nothing selected" branch to
render. Phase inside a presentation (countdown → session) belongs to a view that
the presentation creates, as its own `@State`, not to a flag beside the one that
presents it — see `DrillFlowView` in `DrillSelectionView.swift`.

---

## 28. `withAnimation` cannot animate what a `Canvas` draws

A `Canvas` renderer is a closure; SwiftUI has nothing to interpolate. Raise a
`@State` inside `withAnimation` and read it in the closure, and the canvas
simply redraws once at the final value. Nothing errors, nothing warns, and the
animation that was designed never plays. Three shipped this way at once:

- `ConfettiView` animated start → end positions and opacity 1 → 0. Every piece
  jumped straight to its faded end state, so all five "celebration" screens
  showed no confetti at all.
- `SubscoreRadarChart`'s draw-in: wedges popped to full while only the
  centre number rolled.
- `AnalyzingView`'s orb keyed bar heights on `sin(phase)` and animated `phase`
  0 → 2π, which lands exactly where it started.

**Two fixes, pick by shape.** Continuous motion that is a function of time
(particles, scanners) runs in a `TimelineView` and computes positions from
`timeline.date` - `ConfettiView`, `TakeScanView`. A one-shot draw-in wraps the
canvas in a small `View, Animatable` whose `animatableData` is the progress
value, so SwiftUI calls `body` every frame with the interpolated value -
`SubscoreRadarChart.RadarWedges`, same trick as `CountUpText`. And prefer
animating a transform (`rotationEffect`, `scaleEffect`) over state the canvas
reads whenever the whole drawing moves as one.

---

## 29. iCloud file work on the main actor freezes the app

With iCloud sync on (the default whenever an account is signed in), a finished
take is moved into the ubiquity container with `FileManager.setUbiquitous`.
That is a coordinated write that waits on the iCloud daemon, and Apple's docs
say never to call it from the main thread. It ran inline in
`AudioService.stopRecording`, and the analysis job then polled
`ubiquitousItemDownloadingStatusKey`, `fileExists` and `AVAudioFile` on the same
file from its main-actor task - right as the daemon started uploading it. The
result was a multi-second hang (the system hang HUD read "9000+ ms") on the
post-take self-check. Nothing errors; the main thread just waits.

Rules:

- `ICloudStorageService.promoteToICloudIfNeeded` and `migrateLocalFilesToICloud`
  are `async` and do the move in `Task.detached`. Await them; never add a
  synchronous path back.
- Anything that has to find or probe a take's file off a job reads the stored
  values on the main actor (`recording.audioURL`, the container URL) and calls
  the `nonisolated` `Recording.resolveStoredURL(_:ubiquityContainer:)` /
  `ICloudStorageService.resolveFile(named:ubiquityContainer:)` inside a detached
  task. `ICloudStorageService.waitUntilReadable(_:)` is the off-main download
  wait.
- `resolvedAudioURL` / `resolvedVideoURL` still exist for a user tap (play,
  share), where one check is fine. Do not call them from a job, a `.task` that
  runs as a screen appears, or `body`.
- A take's duration is read from the local file before the move, off the main
  actor (`AudioService.fileDuration(at:)`).

