import SwiftUI
import SwiftData

@main
struct SpeakUpApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
            Prompt.self,
            UserGoal.self,
            UserSettings.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none  // Disable CloudKit for now - enable later with proper entitlements
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Failed to create ModelContainer: \(error)")

            // Delete the old database and try again
            let fileManager = FileManager.default
            if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeURL = appSupport.appendingPathComponent("default.store")
                let storeShmURL = appSupport.appendingPathComponent("default.store-shm")
                let storeWalURL = appSupport.appendingPathComponent("default.store-wal")

                try? fileManager.removeItem(at: storeURL)
                try? fileManager.removeItem(at: storeShmURL)
                try? fileManager.removeItem(at: storeWalURL)

                print("Deleted old database, recreating...")
            }

            // Try again with fresh database
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                print("Still failed after deleting old store: \(error)")

                // Last resort: in-memory store
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
                .task {
                    await seedPromptsIfNeeded()
                    await ensureSettingsExist()
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    @MainActor
    private func seedPromptsIfNeeded() async {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Prompt>()
        
        do {
            let existingCount = try context.fetchCount(descriptor)
            if existingCount == 0 {
                // Seed default prompts
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
