import Foundation
import SwiftData

@Observable
class AchievementService {
    var newlyUnlocked: Achievement?

    /// Recording-derived facts computed on a background context so achievement
    /// checks never fetch every Recording or decode `analysis` blobs on the
    /// main thread.
    private struct Signals: Sendable {
        let totalRecordings: Int
        let streak: Int
        let hasScore80: Bool
        let hasScore95: Bool
        let hasZeroFillerRecording: Bool
        let hasWordWorkout: Bool
        let allCategoriesCovered: Bool
    }

    /// Check all achievements against current data and unlock any that are newly earned.
    @MainActor
    func checkAchievements(context: ModelContext, listenBackCount: Int = 0) async {
        let container = context.container
        let signals = await Task.detached(priority: .utility) { () -> Signals? in
            Self.computeSignals(container: container)
        }.value

        guard let signals else { return }

        let achievements: [Achievement]
        do {
            achievements = try context.fetch(FetchDescriptor<Achievement>())
        } catch {
            return
        }

        // Seed achievements if empty
        if achievements.isEmpty {
            for def in AchievementDefinition.allCases {
                context.insert(def.toModel())
            }
            try? context.save()
            // Re-fetch after seeding
            guard let seeded = try? context.fetch(FetchDescriptor<Achievement>()) else { return }
            evaluateAll(achievements: seeded, signals: signals, context: context, listenBackCount: listenBackCount)
            return
        }

        evaluateAll(achievements: achievements, signals: signals, context: context, listenBackCount: listenBackCount)
    }

    nonisolated private static func computeSignals(container: ModelContainer) -> Signals? {
        let context = ModelContext(container)
        let recordings: [Recording]
        do {
            recordings = try context.fetch(
                FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            )
        } catch {
            return nil
        }

        let usedCategories = Set(recordings.compactMap { $0.prompt?.category })
        let allCategories = Set(PromptCategory.allCases.map { $0.rawValue })

        var hasScore80 = false
        var hasScore95 = false
        var hasZeroFiller = false
        var hasWordWorkout = false
        for recording in recordings {
            guard let analysis = recording.analysis else { continue }
            let overall = analysis.speechScore.overall
            if overall >= 80 { hasScore80 = true }
            if overall >= 95 { hasScore95 = true }
            if analysis.totalFillerCount == 0 && analysis.totalWords > 0 { hasZeroFiller = true }
            let usedVocab = analysis.vocabWordsUsed.filter { $0.count > 0 }.count
            if usedVocab >= 3 { hasWordWorkout = true }
            if hasScore80 && hasScore95 && hasZeroFiller && hasWordWorkout { break }
        }

        return Signals(
            totalRecordings: recordings.count,
            streak: Date.calculateStreak(from: recordings.map { $0.date }),
            hasScore80: hasScore80,
            hasScore95: hasScore95,
            hasZeroFillerRecording: hasZeroFiller,
            hasWordWorkout: hasWordWorkout,
            allCategoriesCovered: allCategories.isSubset(of: usedCategories)
        )
    }

    @MainActor
    private func evaluateAll(achievements: [Achievement], signals: Signals, context: ModelContext, listenBackCount: Int = 0) {
        // CloudKit sync can produce duplicate Achievement rows with the same id.
        // Build the lookup tolerating duplicates, and delete extras so we converge
        // on a single row per id over time.
        var lookup: [String: Achievement] = [:]
        var duplicates: [Achievement] = []
        for achievement in achievements {
            if let existing = lookup[achievement.id] {
                // Prefer the unlocked row so we don't lose progress.
                if achievement.isUnlocked && !existing.isUnlocked {
                    duplicates.append(existing)
                    lookup[achievement.id] = achievement
                } else {
                    duplicates.append(achievement)
                }
            } else {
                lookup[achievement.id] = achievement
            }
        }
        for dup in duplicates {
            context.delete(dup)
        }
        for def in AchievementDefinition.allCases {
            if let existing = lookup[def.rawValue] {
                // Definitions own display copy. Keep older rows in sync when
                // wording becomes clearer without touching unlock state.
                def.refreshDisplay(on: existing)
            } else {
                let model = def.toModel()
                context.insert(model)
                lookup[def.rawValue] = model
            }
        }

        let streak = signals.streak

        let checks: [(String, Bool)] = [
            ("first_recording", signals.totalRecordings >= 1),
            ("ten_sessions", signals.totalRecordings >= 10),
            ("fifty_sessions", signals.totalRecordings >= 50),
            ("hundred_sessions", signals.totalRecordings >= 100),
            ("streak_3", streak >= 3),
            ("streak_7", streak >= 7),
            ("streak_30", streak >= 30),
            ("score_80", signals.hasScore80),
            ("score_95", signals.hasScore95),
            ("zero_fillers", signals.hasZeroFillerRecording),
            ("all_categories", signals.allCategoriesCovered),
            ("listen_back", listenBackCount >= 1),
            ("word_workout", signals.hasWordWorkout),
        ]

        for (id, met) in checks {
            guard met, let achievement = lookup[id], !achievement.isUnlocked else { continue }
            achievement.isUnlocked = true
            achievement.unlockedDate = Date()

            // The retention signal the plan reads: how far into the habit
            // people get before they stop. The id is already a fixed slug.
            AnalyticsService.shared.log(.milestone(type: id))

            // Report the first newly unlocked one for celebration
            if newlyUnlocked == nil {
                newlyUnlocked = achievement
            }
        }

        try? context.save()
    }

    func clearNewlyUnlocked() {
        newlyUnlocked = nil
    }
}
