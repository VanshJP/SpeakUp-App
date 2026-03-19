import Foundation

enum CurriculumActivitySignalStore {
    private static let completedDrillModesKey = "curriculum.completedDrillModes"
    private static let completedExerciseIDsKey = "curriculum.completedExerciseIDs"
    private static let readAloudCompletedKey = "curriculum.readAloudCompleted"

    private static var defaults: UserDefaults { .standard }

    static func markDrillCompleted(_ drillMode: String) {
        var current = Set(defaults.stringArray(forKey: completedDrillModesKey) ?? [])
        current.insert(drillMode)
        defaults.set(Array(current), forKey: completedDrillModesKey)
    }

    static func markExerciseCompleted(_ exerciseID: String) {
        var current = Set(defaults.stringArray(forKey: completedExerciseIDsKey) ?? [])
        current.insert(exerciseID)
        defaults.set(Array(current), forKey: completedExerciseIDsKey)
    }

    static func markReadAloudCompleted() {
        defaults.set(true, forKey: readAloudCompletedKey)
    }

    static var completedDrillModes: Set<String> {
        Set(defaults.stringArray(forKey: completedDrillModesKey) ?? [])
    }

    static var completedExerciseIDs: Set<String> {
        Set(defaults.stringArray(forKey: completedExerciseIDsKey) ?? [])
    }

    static var hasCompletedReadAloud: Bool {
        defaults.bool(forKey: readAloudCompletedKey)
    }
}
