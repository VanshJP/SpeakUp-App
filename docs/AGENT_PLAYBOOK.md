# Agent playbook — workflows

Recipes for frequent changes. After finishing, update the matching `docs/features/*.md` in the same PR. Do **not** run `xcodebuild` / Simulator (root `AGENTS.md`).

Gotchas first: [AGENT_GOTCHAS.md](./AGENT_GOTCHAS.md). Index: [features/README.md](./features/README.md).

---

## Verify without Xcode

Agents cannot build. Before handing off, grep the **diff** for landmines. A hit in new code → stop, open the matching gotcha.

```bash
# Isolation / UIKit-era state
rg -n '@StateObject|@ObservedObject' SpeakUp SpeakUpWidget --glob '*.swift'

# Design-system leaks
rg -n 'Color\.(blue|red|green|orange|purple|yellow)\b' SpeakUp --glob '*.swift'

# SwiftData blob predicates
rg -n '#Predicate' SpeakUp --glob '*.swift'

# Membership scatter
rg -n 'isLifetime' SpeakUp --glob '*.swift'

# Widget / audio-thread
rg -n 'reloadAllTimelines\(' SpeakUp --glob '*.swift'
rg -n 'installTap|removeTap' SpeakUp --glob '*.swift'
rg -n 'requiresOnDeviceRecognition' SpeakUp --glob '*.swift'
rg -n 'noSpeechThreshold' SpeakUp --glob '*.swift'
```

Known-good hits exist (`EntitlementStore.isLifetime`, tap install *before* `engine.start()`, unconditional `requiresOnDeviceRecognition = true`). New call sites outside those files are the bug. Add or extend a test under `SpeakUpTests/` when the change is pure policy / scoring / links — do not execute it; suggest the handoff command.

---

## Add a settings page

1. `SpeakUp/Views/Settings/<Name>SettingsView.swift`.
2. `PageScrollView` + `.appBackground(.subtle)`.
3. `GlassCard` / `GlassButton` / `AppColors` only ([features/ui-design-system.md](./features/ui-design-system.md)).
4. Hub row in `SettingsView`.
5. Persist on `UserSettings` only with **additive** optional/default fields.
6. Update [features/settings.md](./features/settings.md).

Nothing in Settings is gated during the beta ([features/monetization.md](./features/monetization.md)).

---

## Add or change a paid gate

1. New `PaidFeature` case or reuse (`Monetization.swift`).
2. Membership in `FreeTierPolicy.trial` / `.expired` `gatedFeatures` — **one place**.
3. Restore the paywall UI first — it is deleted for the beta. A gate with no unlock path is a dead end.
4. Do **not** gate `progressCards` unless launch measurement + tests change policy.
5. Add / extend `SpeakUpTests/MonetizationTests.swift` (pure policy + injected clock).
6. Update [features/monetization.md](./features/monetization.md) + `RELEASE_CHECKLIST.md` if the boundary ships.
7. Hand off: developer runs unit tests.

---

## Add a SwiftData field

1. Additive only: optional **or** default. Never rename/remove/`!` an existing stored `@Attribute`.
2. New `@Model` type → register in `SpeakUpApp` `ModelContainer` schema list.
3. CloudKit + lightweight migration assume additive shapes — no `VersionedSchema`.
4. Avoid `#Predicate` on Codable/blob columns ([gotchas §2](./AGENT_GOTCHAS.md)).
5. Describe the field so the developer can exercise the in-memory container fallback.
6. Update the feature doc + schema note in [features/architecture.md](./features/architecture.md) if a new entity.

---

## Add a widget

1. TimelineProvider + view in `SpeakUpWidget/`.
2. Register in `SpeakUpWidgetBundle`.
3. Extend **both** `WidgetDataProvider`s (app write + widget read) with matching keys.
4. Deep link hits the same router as `ContentView` / `UniversalLink`.
5. Reloads via fingerprint gate in `TodayViewModel` — no unconditional `reloadAllTimelines()`.
6. No SwiftData in the widget target.
7. Update [features/widgets.md](./features/widgets.md). Skill: `widgetkit`.

---

## Add a unit test

Target: `SpeakUpTests/` — **Swift Testing** (`@Test`), `@testable import SpeakUp`.

| Prefer | Avoid |
|--------|--------|
| Pure functions, injected `now` / policy | Live StoreKit, AVAudio, network |
| `nonisolated` types (or `@MainActor` suite if UI-bound) | New `ModelContainer` unless extending an existing pattern |
| Mirror `MonetizationTests` / `ScoringEngineTests` / `UniversalLinkTests` / `SharedPromptLinkTests` | XCTest-style classes for new files |

Agent does **not** execute tests. Suggest:

```bash
xcodebuild -scheme SpeakUp -destination 'platform=iOS Simulator,name=iPhone 16' test
```

---

## Add a practice / Library surface

1. Feature folder `SpeakUp/Views/<Feature>/` + optional ViewModel.
2. Present from `ContentView` sheet **or** Practice Hub tools — no 6th tab without product intent.
3. Story-linked: plumb `sourceStory` / `recordingStoryId` like warm-ups/drills.
4. Seed data → `SpeakUp/Data/`.
5. Colors → `AppColors.tool*` when it is a “tool”.
6. New doc under `docs/features/` + index row in `features/README.md` (not root `AGENTS.md`).

---

## Touch speech scoring

1. Read **`SPEECH.md`** for the subsystem (gates, weights, fillers, LLM).
2. Wiring / allowance / coordinator: [features/speech-pipeline.md](./features/speech-pipeline.md) + [AGENT_GOTCHAS.md](./AGENT_GOTCHAS.md) §5 / §9.
3. Prefer pure changes in `SpeechScoringEngine` / `TextAnalysisService` covered by `ScoringEngineTests` / `FillerPipelineTests`.
4. Do not burn allowance except via coordinator success path.
5. Skill: `axiom-media` if touching `AVAudioEngine` / taps.

---

## Touch onboarding

1. Mandatory: **`ONBOARDING_VISION.md`** (12 invariants). Research-only: `ONBOARDING_REDESIGN.md`.
2. Baseline recording stays **inside** onboarding — no handoff to generic `RecordingView` for first activation.
3. Update the vision doc if you change an invariant.

---

## Share a card / ask for review

1. Render → `SharePresenter.present` only ([gotchas §7](./AGENT_GOTCHAS.md)).
2. Review asks: `ReviewRequestService` + `ReviewEligibility` — never atop paywall; only after first result; respect version / 60-day rules ([features/analytics-review.md](./features/analytics-review.md)).
