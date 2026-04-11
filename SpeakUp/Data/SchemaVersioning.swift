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
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self]
    }
}

enum SpeakUpSchemaV9: VersionedSchema {
    static var versionIdentifier = Schema.Version(9, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self]
    }
}

enum SpeakUpSchemaV10: VersionedSchema {
    static var versionIdentifier = Schema.Version(10, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, RecordingGroup.self]
    }
}

enum SpeakUpSchemaV11: VersionedSchema {
    static var versionIdentifier = Schema.Version(11, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, RecordingGroup.self]
    }
}

enum SpeakUpSchemaV12: VersionedSchema {
    static var versionIdentifier = Schema.Version(12, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, RecordingGroup.self, Story.self]
    }
}

enum SpeakUpSchemaV13: VersionedSchema {
    static var versionIdentifier = Schema.Version(13, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, RecordingGroup.self, Story.self]
    }
}

enum SpeakUpSchemaV14: VersionedSchema {
    static var versionIdentifier = Schema.Version(14, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, RecordingGroup.self, Story.self]
    }
}

enum SpeakUpSchemaV15: VersionedSchema {
    static var versionIdentifier = Schema.Version(15, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, RecordingGroup.self, Story.self]
    }
}

enum SpeakUpSchemaV16: VersionedSchema {
    static var versionIdentifier = Schema.Version(16, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, RecordingGroup.self, Story.self]
    }
}

enum SpeakUpSchemaV17: VersionedSchema {
    static var versionIdentifier = Schema.Version(17, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, RecordingGroup.self, Story.self]
    }
}

// V18: Added Recording.waveformPeaks ([Float]?) for cached waveform data
enum SpeakUpSchemaV18: VersionedSchema {
    static var versionIdentifier = Schema.Version(18, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, RecordingGroup.self, Story.self]
    }
}

// V19: Added StoryFolder model and Story.folderId + Story.contentAttributed (rich text)
enum SpeakUpSchemaV19: VersionedSchema {
    static var versionIdentifier = Schema.Version(19, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self, CurriculumProgress.self, RecordingGroup.self, Story.self, StoryFolder.self]
    }
}

// MARK: - Migration Plan

enum SpeakUpMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SpeakUpSchemaV1.self, SpeakUpSchemaV2.self, SpeakUpSchemaV3.self, SpeakUpSchemaV4.self, SpeakUpSchemaV5.self, SpeakUpSchemaV6.self, SpeakUpSchemaV7.self, SpeakUpSchemaV8.self, SpeakUpSchemaV9.self, SpeakUpSchemaV10.self, SpeakUpSchemaV11.self, SpeakUpSchemaV12.self, SpeakUpSchemaV13.self, SpeakUpSchemaV14.self, SpeakUpSchemaV15.self, SpeakUpSchemaV16.self, SpeakUpSchemaV17.self, SpeakUpSchemaV18.self, SpeakUpSchemaV19.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6, migrateV6toV7, migrateV7toV8, migrateV8toV9, migrateV9toV10, migrateV10toV11, migrateV11toV12, migrateV12toV13, migrateV13toV14, migrateV14toV15, migrateV15toV16, migrateV16toV17, migrateV17toV18, migrateV18toV19]
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

    static let migrateV11toV12 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV11.self,
        toVersion: SpeakUpSchemaV12.self
    )

    static let migrateV12toV13 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV12.self,
        toVersion: SpeakUpSchemaV13.self
    )

    static let migrateV13toV14 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV13.self,
        toVersion: SpeakUpSchemaV14.self
    )

    static let migrateV14toV15 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV14.self,
        toVersion: SpeakUpSchemaV15.self
    )

    static let migrateV15toV16 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV15.self,
        toVersion: SpeakUpSchemaV16.self
    )

    static let migrateV16toV17 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV16.self,
        toVersion: SpeakUpSchemaV17.self
    )

    static let migrateV17toV18 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV17.self,
        toVersion: SpeakUpSchemaV18.self
    )

    static let migrateV18toV19 = MigrationStage.lightweight(
        fromVersion: SpeakUpSchemaV18.self,
        toVersion: SpeakUpSchemaV19.self
    )
}
