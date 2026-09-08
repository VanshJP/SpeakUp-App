import Foundation
import SwiftData

/// First versioned schema snapshot. Every model shipped unversioned before
/// this, so wrapping the existing types as V1 is a zero-migration bootstrap.
/// Future breaking schema changes copy this into a V2 and add a stage to
/// `SpeakUpMigrationPlan`; lightweight changes (new optional fields with
/// defaults) stay automatic between versions.
nonisolated enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Recording.self,
            Prompt.self,
            UserGoal.self,
            UserSettings.self,
            Achievement.self,
            CurriculumProgress.self,
            RecordingGroup.self,
            Story.self,
            StoryFolder.self,
        ]
    }
}

/// No custom stages yet — declared now so the container is wired for staged
/// migrations when a heavy change eventually lands.
nonisolated enum SpeakUpMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}
