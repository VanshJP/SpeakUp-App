import Foundation
import SwiftUI
import SwiftData

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

    private var modelContext: ModelContext?
    private var answeredPromptIDs: Set<String> = []
    private var hasRerolledPrompt = false
    
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
        
        // Load user settings first (needed for prompt filtering)
        await loadUserSettings(context: context)

        // Load today's prompt
        await loadTodaysPrompt(context: context)

        // Load user stats
        await loadUserStats(context: context)

        // Load active goals
        await loadActiveGoals(context: context)

        // Load daily challenge
        loadDailyChallenge(recordings: (try? context.fetch(FetchDescriptor<Recording>())) ?? [])

        // Schedule streak-at-risk notification if applicable
        await scheduleStreakNotificationIfNeeded()

        // Update widget data
        updateWidgetData()
    }

    private func updateWidgetData() {
        WidgetDataProvider.updateStreak(userStats.currentStreak)
        if let prompt = todaysPrompt {
            WidgetDataProvider.updateTodaysPrompt(text: prompt.text, category: prompt.category, id: prompt.id)
        }
        if let lastScore = userStats.scoreHistory.first?.score {
            WidgetDataProvider.updateLastScore(lastScore)
        }
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
    private func loadUserStats(context: ModelContext) async {
        let descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        do {
            let recordings = try context.fetch(descriptor)
            
            // Calculate stats
            let totalRecordings = recordings.count
            let totalPracticeTime = recordings.reduce(0) { $0 + $1.actualDuration }
            
            // Calculate streaks
            let recordingDates = recordings.map { $0.date }
            let currentStreak = Date.calculateStreak(from: recordingDates)
            
            // Calculate longest streak (simplified - would need more logic for accuracy)
            let longestStreak = max(currentStreak, recordings.isEmpty ? 0 : 1)
            
            // Calculate average score
            let scoresWithAnalysis = recordings.compactMap { $0.analysis?.speechScore.overall }
            let averageScore = scoresWithAnalysis.isEmpty ? 0 : Double(scoresWithAnalysis.reduce(0, +)) / Double(scoresWithAnalysis.count)
            
            // Get score history (last 7 days)
            let sevenDaysAgo = Date().adding(days: -7)
            let recentRecordings = recordings.filter { $0.date >= sevenDaysAgo }
            let scoreHistory = recentRecordings.compactMap { recording -> ScoreHistoryEntry? in
                guard let score = recording.analysis?.speechScore.overall else { return nil }
                return ScoreHistoryEntry(date: recording.date, score: score)
            }
            
            // Most used fillers
            var fillerCounts: [String: Int] = [:]
            for recording in recordings {
                for filler in recording.analysis?.fillerWords ?? [] {
                    fillerCounts[filler.word, default: 0] += filler.count
                }
            }
            let mostUsedFillers = fillerCounts
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { FillerWord(word: $0.key, count: $0.value) }
            
            // Calculate improvement rate
            let improvementRate = calculateImprovementRate(from: recentRecordings)

            // Weekly progress
            weeklyProgress = WeeklyProgressService.calculate(recordings: recordings)

            // Sessions this week (Mon-Sun)
            let calendar = Calendar.current
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
            let weeklySessionCount = recordings.filter { $0.date >= weekStart }.count
            
            userStats = UserStats(
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
        } catch {
            print("Error loading user stats: \(error)")
        }
    }
    
    @MainActor
    private func loadActiveGoals(context: ModelContext) async {
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
            }
        } catch {
            print("Error loading user settings: \(error)")
        }

        // Build set of prompt IDs that have recordings
        if hideAnsweredPrompts {
            await loadAnsweredPromptIDs(context: context)
        }
    }

    @MainActor
    private func loadAnsweredPromptIDs(context: ModelContext) async {
        let descriptor = FetchDescriptor<Recording>()
        do {
            let recordings = try context.fetch(descriptor)
            answeredPromptIDs = Set(recordings.compactMap { $0.prompt?.id })
        } catch {
            print("Error loading answered prompts: \(error)")
        }
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
                await loadAnsweredPromptIDs(context: context)
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
    
    private func loadDailyChallenge(recordings: [Recording]) {
        var challenge = DailyChallengeService.todaysChallenge()
        let today = Calendar.current.startOfDay(for: Date())
        let todayRecordings = recordings.filter { $0.date >= today }
        challenge.isCompleted = todayRecordings.contains { DailyChallengeService.evaluate(challenge: challenge, recording: $0) }
        dailyChallenge = challenge
    }

    private func calculateImprovementRate(from recordings: [Recording]) -> Double {
        guard recordings.count >= 2 else { return 0 }
        
        let sortedByDate = recordings.sorted { $0.date < $1.date }
        
        // Get first half and second half averages
        let midpoint = sortedByDate.count / 2
        let firstHalf = Array(sortedByDate.prefix(midpoint))
        let secondHalf = Array(sortedByDate.suffix(from: midpoint))
        
        let firstAvg = firstHalf.compactMap { $0.analysis?.speechScore.overall }.reduce(0, +)
        let secondAvg = secondHalf.compactMap { $0.analysis?.speechScore.overall }.reduce(0, +)
        
        guard firstAvg > 0 else { return 0 }
        
        let firstAvgDouble = Double(firstAvg) / Double(max(firstHalf.count, 1))
        let secondAvgDouble = Double(secondAvg) / Double(max(secondHalf.count, 1))
        
        return ((secondAvgDouble - firstAvgDouble) / firstAvgDouble) * 100
    }
}
