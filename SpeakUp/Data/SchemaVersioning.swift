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

enum SpeakUpSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self]
    }
}

enum SpeakUpSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self]
    }
}

enum SpeakUpSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self]
    }
}

enum SpeakUpSchemaV7: VersionedSchema {
    static var versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self]
    }
}

enum SpeakUpSchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, SpeakingEvent.self, EventPrepTask.self]
    }
}

enum SpeakUpSchemaV9: VersionedSchema {
    static var versionIdentifier = Schema.Version(9, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, SpeakingEvent.self, EventPrepTask.self]
    }
}

enum SpeakUpSchemaV10: VersionedSchema {
    static var versionIdentifier = Schema.Version(10, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, SpeakingEvent.self, EventPrepTask.self, RecordingGroup.self]
    }
}

enum SpeakUpSchemaV11: VersionedSchema {
    static var versionIdentifier = Schema.Version(11, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, SpeakingEvent.self, EventPrepTask.self, RecordingGroup.self]
    }
}

// MARK: - Migration Plan

enum SpeakUpMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SpeakUpSchemaV1.self, SpeakUpSchemaV2.self, SpeakUpSchemaV3.self, SpeakUpSchemaV4.self, SpeakUpSchemaV5.self, SpeakUpSchemaV6.self, SpeakUpSchemaV7.self, SpeakUpSchemaV8.self, SpeakUpSchemaV9.self, SpeakUpSchemaV10.self, SpeakUpSchemaV11.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6, migrateV6toV7, migrateV7toV8, migrateV8toV9, migrateV9toV10, migrateV10toV11]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV1.self,
        toVersion: SpeakUpSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV2.self,
        toVersion: SpeakUpSchemaV3.self
    )

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV3.self,
        toVersion: SpeakUpSchemaV4.self
    )

    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV4.self,
        toVersion: SpeakUpSchemaV5.self
    )

    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV5.self,
        toVersion: SpeakUpSchemaV6.self
    )

    static let migrateV6toV7 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV6.self,
        toVersion: SpeakUpSchemaV7.self
    )

    static let migrateV7toV8 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV7.self,
        toVersion: SpeakUpSchemaV8.self
    )

    static let migrateV8toV9 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV8.self,
        toVersion: SpeakUpSchemaV9.self
    )

    static let migrateV9toV10 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV9.self,
        toVersion: SpeakUpSchemaV10.self
    )

    static let migrateV10toV11 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV10.self,
        toVersion: SpeakUpSchemaV11.self
    )
}
