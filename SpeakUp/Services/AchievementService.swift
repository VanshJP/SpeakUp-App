import Foundation
import SwiftData

@Observable
class AchievementService {
    var newlyUnlocked: Achievement?

    /// Check all achievements against current data and unlock any that are newly earned.
    @MainActor
    func checkAchievements(context: ModelContext) async {
        let recordings: [Recording]
        let achievements: [Achievement]

        do {
            recordings = try context.fetch(FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
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
            evaluateAll(achievements: seeded, recordings: recordings, context: context)
            return
        }

        evaluateAll(achievements: achievements, recordings: recordings, context: context)
    }

    private func evaluateAll(achievements: [Achievement], recordings: [Recording], context: ModelContext) {
        let lookup = Dictionary(uniqueKeysWithValues: achievements.map { ($0.id, $0) })
        let totalRecordings = recordings.count
        let recordingDates = recordings.map { $0.date }
        let streak = Date.calculateStreak(from: recordingDates)

        let checks: [(String, Bool)] = [
            ("first_recording", totalRecordings >= 1),
            ("ten_sessions", totalRecordings >= 10),
            ("fifty_sessions", totalRecordings >= 50),
            ("hundred_sessions", totalRecordings >= 100),
            ("streak_3", streak >= 3),
            ("streak_7", streak >= 7),
            ("streak_30", streak >= 30),
            ("score_80", recordings.contains { ($0.analysis?.speechScore.overall ?? 0) >= 80 }),
            ("score_95", recordings.contains { ($0.analysis?.speechScore.overall ?? 0) >= 95 }),
            ("zero_fillers", recordings.contains { rec in
                guard let analysis = rec.analysis else { return false }
                return analysis.totalFillerCount == 0 && analysis.totalWords > 0
            }),
            ("all_categories", {
                let usedCategories = Set(recordings.compactMap { $0.prompt?.category })
                let allCategories = Set(PromptCategory.allCases.map { $0.rawValue })
                return allCategories.isSubset(of: usedCategories)
            }()),
        ]

        for (id, met) in checks {
            guard met, let achievement = lookup[id], !achievement.isUnlocked else { continue }
            achievement.isUnlocked = true
            achievement.unlockedDate = Date()

            // Report the first newly unlocked one for celebration
            if newlyUnlocked == nil {
                newlyUnlocked = achievement
            }

            // Fire notification for milestone streaks
            if id.hasPrefix("streak_") {
                Task {
                    await NotificationService().sendStreakMilestoneNotification(days: streak)
                }
            }
        }

        try? context.save()
    }

    func clearNewlyUnlocked() {
        newlyUnlocked = nil
    }
}
