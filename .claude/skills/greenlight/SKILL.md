---
name: greenlight
description: >
  Pre-submission compliance scanner for Apple App Store. Use when reviewing iOS /
  macOS / tvOS / watchOS / visionOS app code for App Store rejection risks, app
  review preparation, compliance checking, or App Store guidelines questions.
---

# Greenlight — App Store Pre-Submission Scanner

Expert prep for App Store submission. Use the `greenlight` CLI (already on PATH — do not install). Run checks, fix issues, re-run until GREENLIT (zero CRITICAL).

## Step 1 — Scan

```bash
greenlight preflight .
```

## Step 2 — Fix by severity

1. **CRITICAL** — Will be rejected. Must fix.
2. **WARN** — High rejection risk. Should fix.
3. **INFO** — Best practice. Consider fixing.

Common fixes:
- Hardcoded secrets → env / config (never commit keys)
- External payment for digital goods → StoreKit / IAP (this app: Lifetime via `PurchaseService`)
- Vague purpose strings → explain *why* the permission is needed
- HTTP → HTTPS; remove platform references to Android / Google Play
- Placeholder / TBD copy → real content
- Console logs → gate behind `#if DEBUG` / remove from release paths
- Missing privacy policy → configure in App Store Connect (`SupportLinks` / Info.plist URLs)

## Step 3 — Re-run

```bash
greenlight preflight .
```

Loop until GREENLIT. Other commands:

```bash
greenlight codescan .
greenlight privacy .
greenlight ipa /path/to/build.ipa
greenlight scan --app-id <ID>
greenlight guidelines search "privacy"
```

For Big Talk specifics also read `RELEASE_CHECKLIST.md`, `docs/features/monetization.md`, and `APP_STORE_LISTING.md`.
