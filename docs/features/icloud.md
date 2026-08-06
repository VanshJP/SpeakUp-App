# iCloud sync

## Purpose

Optional CloudKit-backed SwiftData + audio file migration into the ubiquity container.

## Key files

| Role | Path |
|------|------|
| Service | `SpeakUp/Services/ICloudStorageService.swift` |
| Boot wiring | `SpeakUp/SpeakUpApp.swift` |
| Settings toggle | `SpeakUp/Views/Settings/SettingsView.swift` (via paywall gate) |
| Entitlements | `SpeakUp/SpeakUp.entitlements` |

Container id (in service): `iCloud.cam.vanshpatel.SpeakUp`.

## Invariants

1. Enabling sync is a **paid** action: `PaywallCoordinator.allow(.iCloudSync)`. Once on, do not revoke for product reasons.
2. Fresh install defaults **on** when an iCloud account is present (`resolvedSyncEnabledPreference`).
3. CloudKit vs local is chosen at **ModelContainer** creation — mid-session flips need careful preference mirroring to UserDefaults; do not casually rebuild the container.
4. Container creation fallback: CloudKit → local-only → in-memory.
5. File migration runs as background launch work — do not block UI.

## Cross-links

[monetization.md](./monetization.md) · [architecture.md](./architecture.md) · [settings.md](./settings.md)
