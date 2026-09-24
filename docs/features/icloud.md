# iCloud sync

## Purpose

Optional CloudKit-backed SwiftData + audio file migration into the ubiquity container.

## Key files

| Role | Path |
|------|------|
| Service | `SpeakUp/Services/ICloudStorageService.swift` |
| Boot wiring | `SpeakUp/SpeakUpApp.swift` |
| Settings toggle | `SpeakUp/Views/Settings/SettingsView.swift` (ungated during beta — see monetization.md) |
| Entitlements | `SpeakUp/SpeakUp.entitlements` |

Container id (in service): `iCloud.cam.vanshpatel.SpeakUp`.

## Invariants

1. Enabling sync is ungated during the beta ([monetization.md](./monetization.md)). Once on, do not revoke for product reasons.
2. Fresh install defaults **on** when an iCloud account is present (`resolvedSyncEnabledPreference`).
3. CloudKit vs local is chosen at **ModelContainer** creation — mid-session flips need careful preference mirroring to UserDefaults; do not casually rebuild the container.
4. Container creation fallback: CloudKit → local-only → in-memory.
5. File migration runs as background launch work — do not block UI. `migrateLocalFilesToICloud` does its `setUbiquitous` calls in `Task.detached`: the service is main-actor isolated, so a `Task(priority: .background)` alone used to run every move on the main thread.
6. **No iCloud file work on the main actor.** `AudioService.stopRecording` leaves a finished take local; `RecordingProcessingCoordinator.process` promotes it with the async `promoteToICloudIfNeeded` once analysis is done reading it, and launch migration sweeps the rest. Jobs resolve and probe media through the `nonisolated` `Recording.resolveStoredURL(_:ubiquityContainer:)` and `waitUntilReadable(_:)`. Both used to run on the main thread right as the daemon began uploading the take, and froze the self-check screen for seconds. See gotcha §29. Throwaway takes (drills, voice calibration, Stories dictation) never reach the analysis job, so they are read and deleted without ever being promoted. Clear All Data resolves and deletes media in a detached task.

## Cross-links

[monetization.md](./monetization.md) · [architecture.md](./architecture.md) · [settings.md](./settings.md)
