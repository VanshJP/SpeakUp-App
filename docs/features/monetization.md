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

## Free tier (`FreeTierPolicy.default`)

- **3** intro analyses, then **3** per rolling 30-day cycle.
- Gated: `unlimitedAnalyses`, `fullCurriculum`, `journalExport`, `iCloudSync`.
- **Not gated:** `progressCards` (Then-vs-Now / share loop must stay free for acquisition).

## Invariants

1. Consume allowance **only after successful analysis** (`AllowanceGate.consume`). Fail open if settings row missing.
2. Exhausted allowance → defer analysis (`analysisBlockedByAllowance`); resume on foreground / entitlement (serial, capped ~20).
3. `PaywallCoordinator`: no auto-paywall before first completed result; user-initiated Unlock always works; fail-open if suppressed.
4. Entitlement mirrored to App Group for widget/offline; `Transaction.updates` + restore + offer codes keep `EntitlementStore` honest.
5. iCloud once enabled is never revoked as a product rule (gate enable, not ongoing use).
6. FAQ / marketing claims must match `APP_STORE_LISTING.md` ownership scope.
7. Never ask for App Store review on top of the paywall (`ReviewRequestService`).

## Cross-links

[recording-detail.md](./recording-detail.md) · [curriculum.md](./curriculum.md) · [history-progress.md](./history-progress.md) · [icloud.md](./icloud.md) · [analytics-review.md](./analytics-review.md) · `/RELEASE_CHECKLIST.md`
