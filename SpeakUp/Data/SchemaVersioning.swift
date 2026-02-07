import SwiftData

// MARK: - Schema Versions

enum SpeakUpSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self]
    }
}

// MARK: - Migration Plan

enum SpeakUpMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SpeakUpSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migrations yet – add lightweight or custom stages here for future versions
        []
    }
}
