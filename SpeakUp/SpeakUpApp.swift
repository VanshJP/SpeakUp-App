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

                    // Seed remaining data concurrently — all independent of each other
                    async let p: () = seedPromptsIfNeeded()
                    async let a: () = seedAchievementsIfNeeded()
                    async let c: () = seedCurriculumIfNeeded()
                    async let f: () = seedStoryFoldersIfNeeded()
                    _ = await (p, a, c, f)

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
                    await NotificationService().clearBadge()
                }
            }
        }
    }

    @MainActor
    private func seedPromptsIfNeeded() async {
        let context = sharedModelContainer.mainContext

        do {
            let existing = try context.fetch(FetchDescriptor<Prompt>())
            let existingIDs = Set(existing.map(\.id))

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

            if inserted > 0 {
                try context.save()
            }
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
            }
        } catch {
            print("Error ensuring settings: \(error)")
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
