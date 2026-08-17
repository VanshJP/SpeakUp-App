import SwiftUI
import SwiftData

@main
struct SpeakUpApp: App {
    // Shared services – injected via .environment() so views don't recreate them
    @State private var speechService = SpeechService()
    @State private var audioService = AudioService()
    @State private var llmService = LLMService()

    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
            Prompt.self,
            UserGoal.self,
            UserSettings.self,
            Achievement.self,
            CurriculumProgress.self,
            RecordingGroup.self,
            Story.self,
            StoryFolder.self,
        ])

        // Respect user's iCloud sync preference (read from UserDefaults since
        // SwiftData isn't available yet at ModelContainer creation time).
        // On fresh installs, infer an initial preference from iCloud account
        // availability so reinstall can restore cloud-backed data immediately.
        let syncEnabled = ICloudStorageService.resolvedSyncEnabledPreference

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: syncEnabled ? .automatic : .none
        )

        do {
            // Lightweight migrations (new models, optional fields, defaults) are automatic
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Failed to create ModelContainer: \(error)")

            // Fallback: try without CloudKit (existing store may not be CloudKit-compatible)
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )

            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                print("Failed to create local ModelContainer: \(error)")

                // Last resort: in-memory store – avoids silent data deletion
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )

                do {
                    return try ModelContainer(for: schema, configurations: [fallbackConfig])
                } catch {
                    fatalError("Could not create ModelContainer: \(error)")
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(speechService)
                .environment(audioService)
                .environment(llmService)
                .task {
                    // Settings must exist before anything else reads them
                    await ensureSettingsExist()

                    // App killed mid-analysis leaves isProcessing stranded true;
                    // clear it so History rows don't spin forever.
                    await resetStaleProcessingFlags()

                    // Upgrade path: an install that already has recordings never
                    // hits the first-analysis start, so it gets its 14 days on
                    // first launch of this build. Same idempotent method.
                    startTrialForExistingInstallIfNeeded()

                    // Seed remaining data concurrently — all independent of each other
                    async let p: () = seedPromptsIfNeeded()
                    async let a: () = seedAchievementsIfNeeded()
                    async let c: () = seedCurriculumIfNeeded()
                    async let f: () = seedStoryFoldersIfNeeded()
                    _ = await (p, a, c, f)

                    #if DEBUG
                    // Runs after prompt/curriculum seeding so the seeded history
                    // sits alongside a fully populated library.
                    ScreenshotSeeder.seedIfRequested(context: sharedModelContainer.mainContext)
                    #endif

                    // Legacy URL migration is one-shot and runs fully off the main
                    // actor so a populated Recording store never delays first frame.
                    let container = sharedModelContainer
                    Task.detached(priority: .background) {
                        await Self.migrateRecordingURLsIfNeeded(container: container)
                    }

                    // Migrate local audio files to iCloud when sync is enabled
                    if ICloudStorageService.shared.isSyncEnabled {
                        Task(priority: .background) {
                            await ICloudStorageService.shared.migrateLocalFilesToICloud()
                        }
                    }

                    // StoreKit listener first, product load second — a purchase
                    // that completes during startup must never be dropped.
                    PurchaseService.shared.start()

                    // Logged once per install, after a grace period so a launch
                    // that arrived through a campaign link has had its source
                    // captured by `onOpenURL` before the event is written.
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        AttributionStore.shared.logFirstOpenIfNeeded()
                    }

                    // Preload Whisper model in background – don't block UI on launch
                    Task.detached(priority: .background) {
                        await speechService.preloadModel()
                    }
                    // Auto-load local LLM if downloaded and Apple Intelligence unavailable
                    Task(priority: .background) {
                        await llmService.loadLocalModelIfNeeded()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    let notifications = NotificationService()
                    await notifications.clearBadge()
                    await notifications.checkPermission()
                    // Re-arms the 3-day lapse timer on every foreground.
                    await notifications.scheduleLapsedUserNudge()
                }
                // Catches a purchase made on another device and a refund
                // processed while the app was backgrounded.
                Task {
                    await PurchaseService.shared.refreshEntitlement()
                    // Entitlement is settled — score anything the free
                    // allowance held back, whether it was unblocked by the
                    // purchase or by the monthly cycle rolling over.
                    RecordingProcessingCoordinator.shared.resumeDeferredRecordings(
                        modelContext: sharedModelContainer.mainContext,
                        speechService: speechService,
                        llmService: llmService
                    )
                }
                AnalyticsService.shared.log(.sessionStart())
            }
        }
    }

    private static let seededPromptCountKey = "seededPromptFingerprint_v1"

    @MainActor
    private func seedPromptsIfNeeded() async {
        let context = sharedModelContainer.mainContext

        do {
            // Cheap gate: the full pass below hydrates every prompt and walks
            // recording relationships. Skip it when nothing has drifted since
            // the last successful pass — fingerprint covers the store row count
            // (CloudKit re-imports, user add/delete) and the shipped defaults
            // count (app update adding new prompts).
            let currentCount = (try? context.fetchCount(FetchDescriptor<Prompt>())) ?? -1
            let fingerprint = "\(currentCount)|\(DefaultPrompts.all.count)"
            if currentCount > 0,
               fingerprint == UserDefaults.standard.string(forKey: Self.seededPromptCountKey) {
                return
            }

            let existing = try context.fetch(FetchDescriptor<Prompt>())

            // Heal duplicate rows: CloudKit sync can re-import prompts that were
            // also seeded locally (unique constraints are unavailable with CloudKit).
            // Keep one copy per id, moving any recordings onto the keeper.
            var byID: [String: Prompt] = [:]
            var duplicates: [Prompt] = []
            for prompt in existing {
                guard let keeper = byID[prompt.id] else {
                    byID[prompt.id] = prompt
                    continue
                }
                let kept = (keeper.recordings?.isEmpty == false || prompt.recordings?.isEmpty != false) ? keeper : prompt
                let dropped = (kept === keeper) ? prompt : keeper
                for recording in dropped.recordings ?? [] {
                    recording.prompt = kept
                }
                byID[prompt.id] = kept
                duplicates.append(dropped)
            }
            for duplicate in duplicates {
                context.delete(duplicate)
            }

            let existingIDs = Set(byID.keys)

            var inserted = 0
            for promptData in DefaultPrompts.all {
                guard !existingIDs.contains(promptData.id) else { continue }
                let prompt = Prompt(
                    id: promptData.id,
                    text: promptData.text,
                    category: promptData.category,
                    difficulty: promptData.difficulty
                )
                context.insert(prompt)
                inserted += 1
            }

            if inserted > 0 || !duplicates.isEmpty {
                try context.save()
            }

            let finalCount = (try? context.fetchCount(FetchDescriptor<Prompt>())) ?? 0
            UserDefaults.standard.set(
                "\(finalCount)|\(DefaultPrompts.all.count)",
                forKey: Self.seededPromptCountKey
            )
        } catch {
            print("Error seeding prompts: \(error)")
        }
    }

    @MainActor
    private func seedAchievementsIfNeeded() async {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Achievement>()

        do {
            let existing = try context.fetch(descriptor)
            let existingIds = Set(existing.map { $0.id })
            let allDefinitions = AchievementDefinition.allCases

            // Seed any missing achievements (handles new cases added over time)
            for def in allDefinitions {
                if !existingIds.contains(def.rawValue) {
                    context.insert(def.toModel())
                }
            }
            try context.save()
        } catch {
            print("Error seeding achievements: \(error)")
        }
    }

    @MainActor
    private func ensureSettingsExist() async {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<UserSettings>()

        do {
            let existingSettings = try context.fetch(descriptor)
            if existingSettings.isEmpty {
                let defaultSettings = UserSettings()
                defaultSettings.iCloudSyncEnabled = ICloudStorageService.shared.isSyncEnabled
                context.insert(defaultSettings)
                try context.save()
            } else if let settings = existingSettings.first {
                // Keep startup sync preference in lock-step with persisted settings.
                ICloudStorageService.shared.isSyncEnabled = settings.iCloudSyncEnabled
                // Audio cue preferences otherwise only land when the Settings
                // tab is opened, so a relaunch would silently revert them.
                ChirpPlayer.shared.isEnabled = settings.chirpSoundEnabled
                ChirpPlayer.shared.pack = SoundPack(rawValue: settings.soundPack) ?? .soft
            }
        } catch {
            print("Error ensuring settings: \(error)")
        }
    }

    /// Existing installs get a fresh 14 days on first launch of the new build.
    /// A store with no recordings is left alone — that clock starts at the first
    /// score, in `AllowanceGate.consume`.
    @MainActor
    private func startTrialForExistingInstallIfNeeded() {
        guard case .notStarted = EntitlementStore.shared.trialState else { return }
        let count = (try? sharedModelContainer.mainContext.fetchCount(FetchDescriptor<Recording>())) ?? 0
        guard count > 0 else { return }
        EntitlementStore.shared.startTrialIfNeeded()
    }

    @MainActor
    private func resetStaleProcessingFlags() async {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.isProcessing == true })
        guard let stuck = try? context.fetch(descriptor), !stuck.isEmpty else { return }
        var changed = false
        for recording in stuck where !RecordingProcessingCoordinator.shared.isProcessing(recording.id) {
            recording.isProcessing = false
            changed = true
        }
        if changed {
            try? context.save()
        }
    }

    private static let urlMigrationFlagKey = "didMigrateRecordingURLs_v1"

    private static func migrateRecordingURLsIfNeeded(container: ModelContainer) async {
        if UserDefaults.standard.bool(forKey: urlMigrationFlagKey) { return }

        // Only fetch the URL fields — avoid hydrating transcript/analysis blobs.
        var descriptor = FetchDescriptor<Recording>()
        descriptor.propertiesToFetch = [\.audioURL, \.videoURL, \.thumbnailURL]

        let context = ModelContext(container)

        do {
            let recordings = try context.fetch(descriptor)
            var migrated = 0

            for recording in recordings {
                var changed = false

                if let url = recording.audioURL, url.path.hasPrefix("/") {
                    recording.audioURL = Recording.relativeURL(from: url)
                    changed = true
                }
                if let url = recording.videoURL, url.path.hasPrefix("/") {
                    recording.videoURL = Recording.relativeURL(from: url)
                    changed = true
                }
                if let url = recording.thumbnailURL, url.path.hasPrefix("/") {
                    recording.thumbnailURL = Recording.relativeURL(from: url)
                    changed = true
                }

                if changed { migrated += 1 }
            }

            if migrated > 0 {
                try context.save()
            }

            UserDefaults.standard.set(true, forKey: urlMigrationFlagKey)
        } catch {
            print("Error migrating recording URLs: \(error)")
        }
    }

    @MainActor
    private func seedStoryFoldersIfNeeded() async {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<StoryFolder>()

        do {
            let existing = try context.fetch(descriptor)
            guard existing.isEmpty else { return }

            for (index, spec) in StoryFolder.defaults.enumerated() {
                let folder = StoryFolder(
                    name: spec.name,
                    systemImage: spec.symbol,
                    colorHex: spec.colorHex,
                    sortOrder: index
                )
                context.insert(folder)
            }
            try context.save()
        } catch {
            print("Error seeding story folders: \(error)")
        }
    }

    @MainActor
    private func seedCurriculumIfNeeded() async {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<CurriculumProgress>()

        do {
            let existing = try context.fetch(descriptor)
            if existing.isEmpty {
                let progress = CurriculumProgress()
                context.insert(progress)
                try context.save()
            }
        } catch {
            print("Error seeding curriculum: \(error)")
        }
    }
}
