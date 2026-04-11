import Foundation
import SwiftUI
import SwiftData
import WidgetKit

@Observable
class TodayViewModel {
    var todaysPrompt: Prompt?
    var userStats: UserStats = UserStats()
    var activeGoals: [UserGoal] = []
    var selectedDuration: RecordingDuration = .sixty
    var isLoading = true
    var weeklyProgress: WeeklyProgressData?
    var dailyChallenge: DailyChallenge?
    var hideAnsweredPrompts: Bool = false
    var weeklyGoalSessions: Int = 5
    var storyPracticeEnabled: Bool = false
    var todaysStory: Story?
    var sparklineScores: [DatedScore] = []
    var recentSubscores: [SpeechSubscores] = []
    private var modelContext: ModelContext?
    private var answeredPromptIDs: Set<String> = []
    private var hasRerolledPrompt = false

    nonisolated init() {}

    func configure(with context: ModelContext) {
        self.modelContext = context
        Task { @MainActor in
            await loadData()
        }
    }
    
    @MainActor
    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        guard let context = modelContext else { return }
        let container = context.container

        // Load user settings first (needed for prompt filtering)
        await loadUserSettings(context: context)

        // Heavy fetch + stats computation off main thread
        let heavy = await Self.fetchAndCompute(
            container: container,
            hideAnsweredPrompts: hideAnsweredPrompts,
            weeklyGoalSessions: weeklyGoalSessions
        )

        self.userStats = heavy.userStats
        self.weeklyProgress = heavy.weeklyProgress
        self.sparklineScores = heavy.sparklineScores
        self.recentSubscores = heavy.recentSubscores
        self.answeredPromptIDs = heavy.answeredPromptIDs

        var challenge = DailyChallengeService.todaysChallenge()
        challenge.isCompleted = heavy.dailyChallengeCompleted
        self.dailyChallenge = challenge

        // Load today's prompt (uses answeredPromptIDs populated above)
        await loadTodaysPrompt(context: context)

        // Load today's story if story practice is enabled
        if storyPracticeEnabled {
            await loadTodaysStory(context: context)
        }

        // Load active goals
        await loadActiveGoals(context: context)

        // Schedule streak-at-risk notification if applicable
        await scheduleStreakNotificationIfNeeded()

        // Update widget data
        updateWidgetData(skillMastery: heavy.skillMastery)
    }

    // MARK: - Background fetch

    private static func fetchAndCompute(
        container: ModelContainer,
        hideAnsweredPrompts: Bool,
        weeklyGoalSessions: Int
    ) async -> TodayHeavyResult {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let recordings = (try? context.fetch(descriptor)) ?? []

            let answered: Set<String> = hideAnsweredPrompts
                ? Set(recordings.compactMap { $0.prompt?.id })
                : []

            // Stats
            let totalRecordings = recordings.count
            let totalPracticeTime = recordings.reduce(0) { $0 + $1.actualDuration }
            let recordingDates = recordings.map(\.date)
            let currentStreak = Date.calculateStreak(from: recordingDates)
            let longestStreak = max(currentStreak, recordings.isEmpty ? 0 : 1)

            let scoresWithAnalysis = recordings.compactMap { $0.analysis?.speechScore.overall }
            let averageScore: Double = scoresWithAnalysis.isEmpty
                ? 0
                : Double(scoresWithAnalysis.reduce(0, +)) / Double(scoresWithAnalysis.count)

            let sevenDaysAgo = Date().adding(days: -7)
            let recentRecordings = recordings.filter { $0.date >= sevenDaysAgo }
            let scoreHistory = recentRecordings.compactMap { rec -> ScoreHistoryEntry? in
                guard let score = rec.analysis?.speechScore.overall else { return nil }
                return ScoreHistoryEntry(date: rec.date, score: score)
            }

            var fillerCounts: [String: Int] = [:]
            for r in recordings {
                for f in r.analysis?.fillerWords ?? [] {
                    fillerCounts[f.word, default: 0] += f.count
                }
            }
            let mostUsedFillers = fillerCounts
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { FillerWord(word: $0.key, count: $0.value) }

            // Improvement rate (inline)
            let improvementRate: Double = {
                guard recentRecordings.count >= 2 else { return 0 }
                let sorted = recentRecordings.sorted { $0.date < $1.date }
                let mid = sorted.count / 2
                let firstHalf = Array(sorted.prefix(mid))
                let secondHalf = Array(sorted.suffix(from: mid))
                let firstSum = firstHalf.compactMap { $0.analysis?.speechScore.overall }.reduce(0, +)
                let secondSum = secondHalf.compactMap { $0.analysis?.speechScore.overall }.reduce(0, +)
                guard firstSum > 0 else { return 0 }
                let firstAvg = Double(firstSum) / Double(max(firstHalf.count, 1))
                let secondAvg = Double(secondSum) / Double(max(secondHalf.count, 1))
                return ((secondAvg - firstAvg) / firstAvg) * 100
            }()

            let calendar = Calendar.current
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
            let weeklySessionCount = recordings.filter { $0.date >= weekStart }.count

            let userStats = UserStats(
                totalRecordings: totalRecordings,
                totalPracticeTime: totalPracticeTime,
                currentStreak: currentStreak,
                longestStreak: longestStreak,
                averageScore: averageScore,
                scoreHistory: scoreHistory,
                mostUsedFillers: Array(mostUsedFillers),
                improvementRate: improvementRate,
                weeklySessionCount: weeklySessionCount,
                weeklyGoalSessions: weeklyGoalSessions
            )

            let weeklyProgress = WeeklyProgressService.calculate(recordings: recordings)

            // Daily challenge completion
            let todayStart = calendar.startOfDay(for: Date())
            let todayRecordings = recordings.filter { $0.date >= todayStart }
            let challengeTemplate = DailyChallengeService.todaysChallenge()
            let challengeCompleted = todayRecordings.contains {
                DailyChallengeService.evaluate(challenge: challengeTemplate, recording: $0)
            }

            // Sparkline (last 20 with analysis, oldest-first)
            let sparkline: [DatedScore] = Array(
                recordings
                    .prefix(20)
                    .compactMap { r -> DatedScore? in
                        guard let s = r.analysis?.speechScore.overall else { return nil }
                        return DatedScore(date: r.date, score: s)
                    }
                    .reversed()
            )

            // Recent subscores for weak area (last 10)
            let recentSubscores: [SpeechSubscores] = recordings
                .prefix(10)
                .compactMap { $0.analysis?.speechScore.subscores }

            // Skill mastery from last 5
            let top5 = recordings.prefix(5).compactMap { $0.analysis?.speechScore.subscores }
            let skillMastery: SkillMastery? = top5.isEmpty ? nil : SkillMastery(
                clarity: top5.map(\.clarity).reduce(0, +) / top5.count,
                pace: top5.map(\.pace).reduce(0, +) / top5.count,
                filler: top5.map(\.fillerUsage).reduce(0, +) / top5.count,
                pause: top5.map(\.pauseQuality).reduce(0, +) / top5.count
            )

            return TodayHeavyResult(
                userStats: userStats,
                weeklyProgress: weeklyProgress,
                answeredPromptIDs: answered,
                sparklineScores: sparkline,
                recentSubscores: recentSubscores,
                dailyChallengeCompleted: challengeCompleted,
                skillMastery: skillMastery
            )
        }.value
    }

    private func updateWidgetData(skillMastery: SkillMastery?) {
        WidgetDataProvider.updateStreak(userStats.currentStreak)
        if let prompt = todaysPrompt {
            WidgetDataProvider.updateTodaysPrompt(text: prompt.text, category: prompt.category, id: prompt.id)
        }
        if let lastScore = userStats.scoreHistory.first?.score {
            WidgetDataProvider.updateLastScore(lastScore)
        }

        // Weekly progress
        let recentScores = userStats.scoreHistory.map(\.score)
        let avgScore = recentScores.isEmpty ? 0 : recentScores.reduce(0, +) / recentScores.count
        WidgetDataProvider.updateWeeklyProgress(
            sessionCount: userStats.weeklySessionCount,
            goalSessions: userStats.weeklyGoalSessions,
            averageScore: avgScore,
            practiceMinutes: Int(weeklyProgress?.totalMinutes ?? 0)
        )

        // Daily challenge
        if let challenge = dailyChallenge {
            WidgetDataProvider.updateDailyChallenge(
                title: challenge.title,
                description: challenge.description,
                icon: challenge.icon,
                isCompleted: challenge.isCompleted
            )
        }

        // Track last practice date for streak-at-risk widget
        if let latestRecording = userStats.scoreHistory.first {
            WidgetDataProvider.updateLastPracticeDate(latestRecording.date)
        }

        // Skill mastery (pre-computed off-main)
        if let skillMastery {
            WidgetDataProvider.updateSkillMastery(
                clarity: skillMastery.clarity,
                pace: skillMastery.pace,
                filler: skillMastery.filler,
                pause: skillMastery.pause
            )
        } else {
            WidgetDataProvider.updateSkillMastery(clarity: 0, pace: 0, filler: 0, pause: 0)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    private func scheduleStreakNotificationIfNeeded() async {
        let streak = userStats.currentStreak
        guard streak >= 2 else { return }

        // Check if user has already recorded today
        guard let context = modelContext else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.date >= today }
        )

        let todayCount = (try? context.fetchCount(descriptor)) ?? 0
        let notificationService = NotificationService()
        await notificationService.checkPermission()

        if todayCount == 0 {
            await notificationService.scheduleStreakAtRiskNotification(currentStreak: streak)
        } else {
            notificationService.cancelStreakAtRiskNotification()
        }
    }
    
    @MainActor
    private func loadTodaysPrompt(context: ModelContext) async {
        // If the user has rerolled the prompt this session, keep it
        if hasRerolledPrompt && todaysPrompt != nil { return }

        // Get today's prompt based on date seed
        let todayData = DefaultPrompts.getTodaysPrompt()
        let targetId = todayData.id

        // Fetch all prompts and filter in memory to avoid SwiftData predicate issues
        let descriptor = FetchDescriptor<Prompt>()

        do {
            var allPrompts = try context.fetch(descriptor)
            todaysPrompt = allPrompts.first { $0.id == targetId }

            // If the prompt isn't in the DB yet (new prompts added, seeding hasn't run yet),
            // insert it directly so we don't have to wait for the full seed pass.
            if todaysPrompt == nil {
                let newPrompt = Prompt(
                    id: todayData.id,
                    text: todayData.text,
                    category: todayData.category,
                    difficulty: todayData.difficulty
                )
                context.insert(newPrompt)
                try context.save()
                todaysPrompt = newPrompt
                allPrompts.append(newPrompt)
            }

            // If hiding answered prompts and current prompt was already answered, pick an unanswered one
            if hideAnsweredPrompts, let current = todaysPrompt, answeredPromptIDs.contains(current.id) {
                let unanswered = allPrompts.filter { !answeredPromptIDs.contains($0.id) }
                todaysPrompt = unanswered.randomElement() ?? current
            }
        } catch {
            print("Error loading today's prompt: \(error)")
        }
    }
    
    @MainActor
    private func loadActiveGoals(context: ModelContext) async {
        GoalProgressService.refreshGoals(in: context)
        let descriptor = FetchDescriptor<UserGoal>(
            predicate: #Predicate { $0.isActive && !$0.isCompleted },
            sortBy: [SortDescriptor(\.deadline)]
        )
        
        do {
            activeGoals = try context.fetch(descriptor)
        } catch {
            print("Error loading active goals: \(error)")
        }
    }
    
    @MainActor
    private func loadUserSettings(context: ModelContext) async {
        let descriptor = FetchDescriptor<UserSettings>()

        do {
            if let settings = try context.fetch(descriptor).first {
                selectedDuration = RecordingDuration(rawValue: settings.defaultDuration) ?? .sixty
                hideAnsweredPrompts = settings.hideAnsweredPrompts
                weeklyGoalSessions = settings.weeklyGoalSessions
                storyPracticeEnabled = settings.storyPracticeEnabled
            }
        } catch {
            print("Error loading user settings: \(error)")
        }

    }

    private func loadAnsweredPromptIDs(context: ModelContext) {
        let recordings = (try? context.fetch(FetchDescriptor<Recording>())) ?? []
        answeredPromptIDs = Set(recordings.compactMap { $0.prompt?.id })
    }
    
    @MainActor
    func refreshPrompt() async {
        guard let context = modelContext else { return }

        // Get a random prompt
        let randomData = DefaultPrompts.getRandomPrompt()
        let targetId = randomData.id

        // Fetch all prompts and filter in memory to avoid SwiftData predicate issues
        let descriptor = FetchDescriptor<Prompt>()

        do {
            var allPrompts = try context.fetch(descriptor)
            var candidate = allPrompts.first { $0.id == targetId }

            // If the prompt isn't in the DB yet, insert it directly
            if candidate == nil {
                let newPrompt = Prompt(
                    id: randomData.id,
                    text: randomData.text,
                    category: randomData.category,
                    difficulty: randomData.difficulty
                )
                context.insert(newPrompt)
                try context.save()
                candidate = newPrompt
                allPrompts.append(newPrompt)
            }

            // If hiding answered prompts, prefer an unanswered one
            if hideAnsweredPrompts {
                loadAnsweredPromptIDs(context: context)
                let unanswered = allPrompts.filter { !answeredPromptIDs.contains($0.id) }
                if let pick = unanswered.randomElement() {
                    candidate = pick
                }
            }

            withAnimation {
                todaysPrompt = candidate
            }
            hasRerolledPrompt = true
        } catch {
            print("Error refreshing prompt: \(error)")
        }
    }
    
    // MARK: - Story Practice

    @MainActor
    private func loadTodaysStory(context: ModelContext) async {
        let descriptor = FetchDescriptor<Story>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        do {
            let stories = try context.fetch(descriptor)
            guard !stories.isEmpty else {
                storyPracticeEnabled = false
                return
            }
            let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
            todaysStory = stories[dayOfYear % stories.count]
        } catch {
            print("Error loading today's story: \(error)")
        }
    }

    @MainActor
    func refreshStory() async {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Story>()

        do {
            let stories = try context.fetch(descriptor)
            guard !stories.isEmpty else { return }
            withAnimation {
                todaysStory = stories.randomElement()
            }
        } catch {
            print("Error refreshing story: \(error)")
        }
    }

}

// MARK: - Sendable result types

nonisolated struct DatedScore: Sendable, Hashable {
    let date: Date
    let score: Int
}

nonisolated struct SkillMastery: Sendable {
    let clarity: Int
    let pace: Int
    let filler: Int
    let pause: Int
}

nonisolated private struct TodayHeavyResult: Sendable {
    let userStats: UserStats
    let weeklyProgress: WeeklyProgressData?
    let answeredPromptIDs: Set<String>
    let sparklineScores: [DatedScore]
    let recentSubscores: [SpeechSubscores]
    let dailyChallengeCompleted: Bool
    let skillMastery: SkillMastery?
}
