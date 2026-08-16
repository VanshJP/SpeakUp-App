# Monetization — Lifetime, allowance, paywall

## Purpose

One non-consumable **Lifetime** purchase. Free users get a small analysis allowance; selected features gate behind Lifetime. Single paywall surface.

## Key files

| Role | Path |
|------|------|
| Policy / types | `SpeakUp/Models/Monetization.swift` — `LifetimeProduct`, `FoundingOffer`, `PaidFeature`, `FreeTierPolicy`, `AllowanceState`, `AllowanceDecision`, `PracticeAllowance` |
| StoreKit | `SpeakUp/Services/PurchaseService.swift` |
| Entitlement cache | `SpeakUp/Services/EntitlementStore.swift` |
| Allowance IO | `SpeakUp/Services/AllowanceGate.swift` |
| UI | `SpeakUp/Views/Paywall/` — `PaywallView`, `PaywallCoordinator`, `LifetimeFAQView`, `LifetimeStatusRow` |
| StoreKit config | `/Products.storekit` |
| Tests | `SpeakUpTests/MonetizationTests.swift` |

## Product

- SKU: `com.vansh.SpeakUpMore.lifetime` — must match App Store Connect + `Products.storekit`.
- **No hardcoded buy-button price** — wait for StoreKit `displayPrice`. Wrong-currency price is worse than empty.
- `FoundingOffer.deadline = nil` by default (no urgency). `$99.99` comparison only when offer active **and** storefront currency is USD.

## Free tier

Two policies, selected by `EntitlementStore.policy`:

| Policy | When | Analyses | Gated |
|--------|------|----------|-------|
| `.trial` | First 14 days | unlimited | `iCloudSync` only |
| `.expired` | After | 3 per rolling 30 days | `unlimitedAnalyses`, `fullCurriculum`, `journalExport`, `iCloudSync` |
| `.unrestricted` | Entitled / debug | unlimited | none |

The 14 days run from the first **completed** analysis — `AllowanceGate.consume` starts the clock, `EntitlementStore.trialStartedAt` holds it (App Group defaults, so a reinstall grants a fresh 14 days by design).

**Not gated in either policy:** `progressCards` (Then-vs-Now / share loop must stay free for acquisition).

## Call-site matrix

| API | Use when | Where today |
|-----|----------|-------------|
| `PaywallCoordinator.allow(_:trigger:)` | Proceed **or** show paywall; fail-open if first-result suppressed | Journal export (`ContentView`), iCloud enable (`SettingsView`) |
| `present(..., userInitiated: true)` | Explicit Unlock / locked CTA | Today allowance, Curriculum phase, deferred analysis detail, `LifetimeStatusRow` |
| `AllowanceGate.decision` | May we analyze / meter copy | `RecordingProcessingCoordinator`, detail deferred UI, status row |
| `AllowanceGate.consume` | After **successful** analysis persist only | `RecordingProcessingCoordinator` only |
| `FreeTierPolicy.gates` / `EntitlementStore` | Membership | Curriculum phase lock; inside `allow` |

New gates: change `gatedFeatures` on `FreeTierPolicy.trial` and/or `.expired`, then call `allow` or `present` — do not scatter `if isLifetime`. Recipe: `/docs/AGENT_PLAYBOOK.md` → “Add or change a paid gate”.

## Invariants

1. Consume allowance **only after successful analysis** (`AllowanceGate.consume`). Fail open if settings row missing.
1a. The gate and the charge are ~90s apart, so `RecordingProcessingCoordinator.reservedAnalyses` holds a claim in between. Any new call site that gates on `AllowanceGate.decision` and charges after an `await` needs the same reservation, or concurrent recordings each see the same `remaining`.
2. Exhausted allowance → defer analysis (`analysisBlockedByAllowance`); resume on foreground / entitlement (serial, capped ~20).
3. `PaywallCoordinator`: no auto-paywall before first completed result; user-initiated Unlock always works; fail-open if suppressed.
4. Entitlement mirrored to App Group for widget/offline; `Transaction.updates` + restore + offer codes keep `EntitlementStore` honest.
5. iCloud once enabled is never revoked as a product rule (gate enable, not ongoing use).
6. FAQ / marketing claims must match `APP_STORE_LISTING.md` ownership scope.
7. Never ask for App Store review on top of the paywall (`ReviewRequestService`).
8. Buy button waits for StoreKit `displayPrice` — never hardcode the Lifetime price in UI.

## Cross-links

[recording-detail.md](./recording-detail.md) · [curriculum.md](./curriculum.md) · [history-progress.md](./history-progress.md) · [icloud.md](./icloud.md) · [analytics-review.md](./analytics-review.md) · `/docs/AGENT_GOTCHAS.md` · `/RELEASE_CHECKLIST.md`
