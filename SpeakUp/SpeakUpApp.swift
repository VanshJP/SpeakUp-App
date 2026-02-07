import SwiftUI
import SwiftData

@main
struct SpeakUpApp: App {
    // Shared services – injected via .environment() so views don't recreate them
    @State private var speechService = SpeechService()
    @State private var audioService = AudioService()

    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
            Prompt.self,
            UserGoal.self,
            UserSettings.self,
            Achievement.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: SpeakUpMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            print("Failed to create ModelContainer with migration plan: \(error)")

            // Attempt without migration plan as fallback
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                print("Failed to create ModelContainer: \(error)")

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
                .environment(speechService)
                .environment(audioService)
                .task {
                    await seedPromptsIfNeeded()
                    await ensureSettingsExist()
                    await seedAchievementsIfNeeded()
                    // Preload Whisper model in background – don't block UI on launch
                    Task.detached(priority: .background) {
                        await speechService.preloadModel()
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
        let descriptor = FetchDescriptor<Prompt>()

        do {
            let existingCount = try context.fetchCount(descriptor)
            if existingCount == 0 {
                for promptData in DefaultPrompts.all {
                    let prompt = Prompt(
                        id: promptData.id,
                        text: promptData.text,
                        category: promptData.category,
                        difficulty: promptData.difficulty
                    )
                    context.insert(prompt)
                }
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
            let existingCount = try context.fetchCount(descriptor)
            if existingCount == 0 {
                for def in AchievementDefinition.allCases {
                    context.insert(def.toModel())
                }
                try context.save()
            }
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
                context.insert(defaultSettings)
                try context.save()
            }
        } catch {
            print("Error ensuring settings: \(error)")
        }
    }
}
