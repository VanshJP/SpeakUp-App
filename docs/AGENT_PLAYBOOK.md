# Agent playbook — common workflows

Step recipes for frequent changes. After finishing, update the matching `docs/features/*.md` in the same PR. Do **not** run `xcodebuild` / Simulator (see root `AGENTS.md`).

Gotchas first: [AGENT_GOTCHAS.md](./AGENT_GOTCHAS.md).

---

## Add a settings page

1. Create `SpeakUp/Views/Settings/<Name>SettingsView.swift`.
2. Wrap in `ScrollView` + `.appBackground(.subtle)`.
3. Use `GlassCard` / `GlassButton` / `AppColors` only ([features/ui-design-system.md](./features/ui-design-system.md)).
4. Add a hub row in `SettingsView` that navigates to it.
5. Persist on `UserSettings` only with **additive** optional/default fields.
6. Update [features/settings.md](./features/settings.md).

If the row enables a paid capability (e.g. iCloud), call `PaywallCoordinator.allow` **before** flipping preference.

---

## Add or change a paid gate

1. Decide if this is a new `PaidFeature` case or reuse an existing one (`Monetization.swift`).
2. Put membership in `FreeTierPolicy.trial` / `.expired` `gatedFeatures` — **one place**, not call-site `if isLifetime`.
3. Choose API ([gotchas §5](./AGENT_GOTCHAS.md)):
   - Action that must proceed-or-paywall → `PaywallCoordinator.allow(_:trigger:)`
   - Explicit Unlock / locked cell → `present(..., userInitiated: true)`
4. Do **not** gate `progressCards` unless launch measurement + tests explicitly change policy.
5. Add / extend `SpeakUpTests/MonetizationTests.swift` (pure policy + injected clock).
6. Update [features/monetization.md](./features/monetization.md) + `RELEASE_CHECKLIST.md` if the boundary ships to users.
7. Hand off: developer runs unit tests.

---

## Add a SwiftData field

1. Additive only: optional **or** default value. Never rename/remove/`!` an existing stored `@Attribute`.
2. If adding a **new `@Model` type**, register it in `SpeakUpApp` `ModelContainer` schema list.
3. CloudKit + lightweight migration both assume additive shapes — no `VersionedSchema` ceremony.
4. Avoid `#Predicate` on Codable/blob columns ([gotchas §2](./AGENT_GOTCHAS.md)).
5. Describe the field so the developer can exercise the in-memory container fallback path.
6. Update the relevant feature doc + schema note in [features/architecture.md](./features/architecture.md) if a new entity.

---

## Add a widget

1. New TimelineProvider + view in `SpeakUpWidget/`.
2. Register in `SpeakUpWidgetBundle`.
3. Extend **both** `WidgetDataProvider`s (app write + widget read) with matching keys.
4. Deep link must hit the same router as `ContentView` / `UniversalLink`.
5. Trigger reloads via fingerprint gate in `TodayViewModel` — no unconditional `reloadAllTimelines()`.
6. No SwiftData in the widget target.
7. Update [features/widgets.md](./features/widgets.md).

---

## Add a unit test

Existing target: `SpeakUpTests/` — **Swift Testing** (`@Test`), `@testable import SpeakUp`.

| Prefer | Avoid |
|--------|--------|
| Pure functions, injected `now` / policy | Live StoreKit, AVAudio, network |
| `nonisolated` types under test (or `@MainActor` suite if type is UI-bound) | Spawning `ModelContainer` unless extending an existing pattern |
| Mirror `MonetizationTests` / `ScoringEngineTests` / `UniversalLinkTests` | XCTest-style classes for new files |

Agent does **not** execute tests. Suggest:

```bash
xcodebuild -scheme SpeakUp -destination 'platform=iOS Simulator,name=iPhone 16' test
```

---

## Add a practice / Library surface

1. Prefer a feature folder under `SpeakUp/Views/<Feature>/` + optional ViewModel.
2. Present from `ContentView` sheet **or** Practice Hub tools section — don’t invent a 6th tab without product intent.
3. If Story-linked, plumb `sourceStory` / `recordingStoryId` like warm-ups/drills.
4. Seed data → `SpeakUp/Data/`.
5. Colors → `AppColors.tool*` family when it is a “tool”.
6. New doc under `docs/features/` + index rows in `features/README.md` and root `AGENTS.md` load table.

---

## Touch speech scoring

1. Read **`SPEECH.md`** end-to-end for the subsystem you change (gates, weights, fillers, LLM).
2. Wiring / allowance / coordinator: [features/speech-pipeline.md](./features/speech-pipeline.md) + [AGENT_GOTCHAS.md](./AGENT_GOTCHAS.md).
3. Prefer pure changes in `SpeechScoringEngine` / `TextAnalysisService` covered by `ScoringEngineTests` / `FillerPipelineTests`.
4. Do not burn allowance except via coordinator success path.

---

## Touch onboarding

1. Mandatory: **`ONBOARDING_VISION.md`** (12 invariants). Research-only: `ONBOARDING_REDESIGN.md`.
2. Baseline recording stays **inside** onboarding — no handoff to generic `RecordingView` for first activation.
3. Update vision doc if you change an invariant; don’t silently diverge.

---

## Share a card / ask for review

1. Render → `SharePresenter.present` only ([gotchas §7](./AGENT_GOTCHAS.md)).
2. Review asks: `ReviewRequestService` + `ReviewEligibility` — never atop paywall; only after first result; respect version / 60-day rules ([features/analytics-review.md](./features/analytics-review.md)).
