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
    
    private var modelContext: ModelContext?
    
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
        
        // Load today's prompt
        await loadTodaysPrompt(context: context)
        
        // Load user stats
        await loadUserStats(context: context)
        
        // Load active goals
        await loadActiveGoals(context: context)
        
        // Load user settings for defaults
        await loadUserSettings(context: context)
    }
    
    @MainActor
    private func loadTodaysPrompt(context: ModelContext) async {
        // Get today's prompt based on date seed
        let todayData = DefaultPrompts.getTodaysPrompt()
        let targetId = todayData.id

        // Fetch all prompts and filter in memory to avoid SwiftData predicate issues
        let descriptor = FetchDescriptor<Prompt>()

        do {
            let allPrompts = try context.fetch(descriptor)
            todaysPrompt = allPrompts.first { $0.id == targetId }

            // If no prompts found, database may not be seeded yet - retry after short delay
            if todaysPrompt == nil && allPrompts.isEmpty {
                try? await Task.sleep(for: .milliseconds(500))
                let retryPrompts = try context.fetch(descriptor)
                todaysPrompt = retryPrompts.first { $0.id == targetId }
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
            
            userStats = UserStats(
                totalRecordings: totalRecordings,
                totalPracticeTime: totalPracticeTime,
                currentStreak: currentStreak,
                longestStreak: longestStreak,
                averageScore: averageScore,
                scoreHistory: scoreHistory,
                mostUsedFillers: Array(mostUsedFillers),
                improvementRate: improvementRate
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
            }
        } catch {
            print("Error loading user settings: \(error)")
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
            let allPrompts = try context.fetch(descriptor)
            withAnimation {
                todaysPrompt = allPrompts.first { $0.id == targetId }
            }
        } catch {
            print("Error refreshing prompt: \(error)")
        }
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
