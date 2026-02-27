import SwiftData

// MARK: - Schema Versions

enum SpeakUpSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self]
    }
}

enum SpeakUpSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self]
    }
}

enum SpeakUpSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self]
    }
}

// MARK: - Migration Plan

enum SpeakUpMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SpeakUpSchemaV1.self, SpeakUpSchemaV2.self, SpeakUpSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV1.self,
        toVersion: SpeakUpSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV2.self,
        toVersion: SpeakUpSchemaV3.self
    )
}
