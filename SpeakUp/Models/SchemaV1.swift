import Foundation
import SwiftData

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

nonisolated enum SpeakUpMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}
