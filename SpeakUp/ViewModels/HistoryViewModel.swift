import Foundation
import SwiftUI
import SwiftData

@Observable
class HistoryViewModel {
    var recordings: [Recording] = []
    var weeklyActivity: [WeeklyActivity] = []
    var currentStreak: Int = 0
    var longestStreak: Int = 0
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
        
        await loadRecordings(context: context)
        await calculateWeeklyActivity(context: context)
        await calculateStreaks()
    }
    
    @MainActor
    private func loadRecordings(context: ModelContext) async {
        let descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        do {
            recordings = try context.fetch(descriptor)
        } catch {
            print("Error loading recordings: \(error)")
        }
    }
    
    @MainActor
    private func calculateWeeklyActivity(context: ModelContext) async {
        // Get recordings for last 26 weeks (half year)
        let startDate = Date().adding(weeks: -26)
        
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.date >= startDate },
            sortBy: [SortDescriptor(\.date)]
        )
        
        do {
            let recentRecordings = try context.fetch(descriptor)
            
            // Group by week
            var weeklyData: [Date: WeeklyActivity] = [:]
            
            for recording in recentRecordings {
                let weekStart = recording.date.startOfWeek
                
                if var activity = weeklyData[weekStart] {
                    activity.sessions += 1
                    activity.totalMinutes += recording.actualDuration / 60
                    if let score = recording.analysis?.speechScore.overall {
                        // Recalculate average
                        let previousTotal = activity.averageScore * Double(activity.sessions - 1)
                        activity.averageScore = (previousTotal + Double(score)) / Double(activity.sessions)
                    }
                    weeklyData[weekStart] = activity
                } else {
                    weeklyData[weekStart] = WeeklyActivity(
                        weekStart: weekStart,
                        sessions: 1,
                        totalMinutes: recording.actualDuration / 60,
                        averageScore: Double(recording.analysis?.speechScore.overall ?? 0)
                    )
                }
            }
            
            // Fill in missing weeks with zero activity
            var allWeeks: [WeeklyActivity] = []
            var currentWeek = startDate.startOfWeek
            let today = Date()
            
            while currentWeek <= today {
                if let activity = weeklyData[currentWeek] {
                    allWeeks.append(activity)
                } else {
                    allWeeks.append(WeeklyActivity(
                        weekStart: currentWeek,
                        sessions: 0,
                        totalMinutes: 0,
                        averageScore: 0
                    ))
                }
                currentWeek = currentWeek.adding(weeks: 1)
            }
            
            weeklyActivity = allWeeks
        } catch {
            print("Error calculating weekly activity: \(error)")
        }
    }
    
    @MainActor
    private func calculateStreaks() async {
        let recordingDates = recordings.map { $0.date }
        currentStreak = Date.calculateStreak(from: recordingDates)
        
        // Calculate longest streak (more comprehensive)
        longestStreak = calculateLongestStreak(from: recordingDates)
    }
    
    private func calculateLongestStreak(from dates: [Date]) -> Int {
        guard !dates.isEmpty else { return 0 }
        
        let uniqueDays = Set(dates.map { Calendar.current.startOfDay(for: $0) })
        let sortedDays = uniqueDays.sorted()
        
        var maxStreak = 1
        var currentStreakCount = 1
        
        for i in 1..<sortedDays.count {
            let previousDay = sortedDays[i - 1]
            let currentDay = sortedDays[i]
            
            if Calendar.current.isDate(currentDay, inSameDayAs: previousDay.adding(days: 1)) {
                currentStreakCount += 1
                maxStreak = max(maxStreak, currentStreakCount)
            } else {
                currentStreakCount = 1
            }
        }
        
        return maxStreak
    }
    
    @MainActor
    func deleteRecording(_ recording: Recording) async {
        guard let context = modelContext else { return }
        
        // Delete associated files
        if let audioURL = recording.audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        if let videoURL = recording.videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
        
        context.delete(recording)
        
        do {
            try context.save()
            await loadData()
        } catch {
            print("Error deleting recording: \(error)")
        }
    }
    
    @MainActor
    func toggleFavorite(_ recording: Recording) async {
        recording.isFavorite.toggle()
        
        do {
            try modelContext?.save()
        } catch {
            print("Error toggling favorite: \(error)")
        }
    }
    
    // MARK: - Contribution Graph Helpers
    
    func activityLevel(for date: Date) -> Double {
        let dayRecordings = recordings.filter { $0.date.isSameDay(as: date) }
        let count = dayRecordings.count
        
        switch count {
        case 0: return 0
        case 1: return 0.25
        case 2: return 0.5
        case 3: return 0.75
        default: return 1.0
        }
    }
    
    func recordingsForDate(_ date: Date) -> [Recording] {
        recordings.filter { $0.date.isSameDay(as: date) }
    }
}
