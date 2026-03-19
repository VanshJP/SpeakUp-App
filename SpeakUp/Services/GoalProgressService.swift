import Foundation
import SwiftData

@MainActor
enum GoalProgressService {
    static func refreshGoals(in context: ModelContext) {
        let goalDescriptor = FetchDescriptor<UserGoal>()
        let recordingDescriptor = FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.date)])

        guard let goals = try? context.fetch(goalDescriptor),
              let recordings = try? context.fetch(recordingDescriptor) else { return }

        var didMutate = false
        for goal in goals {
            let snapshot = goalSnapshot(goal)
            applyProgress(for: goal, recordings: recordings)
            if snapshot != goalSnapshot(goal) {
                didMutate = true
            }
        }

        if didMutate {
            try? context.save()
        }
    }

    private static func applyProgress(for goal: UserGoal, recordings: [Recording]) {
        let effectiveEnd = min(goal.deadline, Date())
        let relevant = recordings.filter { $0.date >= goal.startDate && $0.date <= effectiveEnd }

        let currentValue: Int
        switch goal.type {
        case .sessionsPerWeek:
            currentValue = relevant.count

        case .practiceStreak:
            currentValue = maxStreakDays(in: relevant.map(\.date))

        case .totalMinutes:
            let totalMinutes = relevant.reduce(0.0) { $0 + $1.actualDuration } / 60.0
            currentValue = Int(totalMinutes.rounded())

        case .improveScore:
            let scores = relevant
                .compactMap { $0.analysis?.speechScore.overall }
            currentValue = scoreImprovement(from: scores)

        case .reduceFiller:
            let ratios = relevant.compactMap { recording -> Double? in
                guard let analysis = recording.analysis, analysis.totalWords > 0 else { return nil }
                return Double(analysis.totalFillerCount) / Double(analysis.totalWords)
            }
            currentValue = fillerReductionPercent(from: ratios)
        }

        goal.current = max(0, currentValue)
        goal.isCompleted = goal.current >= goal.target
    }

    private static func maxStreakDays(in dates: [Date]) -> Int {
        let startOfDays = Set(dates.map { Calendar.current.startOfDay(for: $0) })
        let sorted = startOfDays.sorted()
        guard !sorted.isEmpty else { return 0 }

        var best = 1
        var streak = 1
        for idx in 1..<sorted.count {
            let previous = sorted[idx - 1]
            let current = sorted[idx]
            let dayDelta = Calendar.current.dateComponents([.day], from: previous, to: current).day ?? 0
            if dayDelta == 1 {
                streak += 1
                best = max(best, streak)
            } else if dayDelta > 1 {
                streak = 1
            }
        }
        return best
    }

    private static func scoreImprovement(from scores: [Int]) -> Int {
        guard scores.count >= 2 else { return 0 }
        let baselineSample = Array(scores.prefix(min(3, scores.count)))
        let recentSample = Array(scores.suffix(min(3, scores.count)))

        let baseline = Double(baselineSample.reduce(0, +)) / Double(max(1, baselineSample.count))
        let recent = Double(recentSample.reduce(0, +)) / Double(max(1, recentSample.count))
        return max(0, Int((recent - baseline).rounded()))
    }

    private static func fillerReductionPercent(from ratios: [Double]) -> Int {
        guard ratios.count >= 2 else { return 0 }

        let midpoint = max(1, ratios.count / 2)
        let firstHalf = Array(ratios.prefix(midpoint))
        let secondHalf = Array(ratios.suffix(ratios.count - midpoint))
        guard !firstHalf.isEmpty, !secondHalf.isEmpty else { return 0 }

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        guard firstAvg > 0 else { return 0 }

        let reduction = max(0, (firstAvg - secondAvg) / firstAvg * 100)
        return Int(reduction.rounded())
    }

    private static func goalSnapshot(_ goal: UserGoal) -> String {
        "\(goal.id.uuidString)|\(goal.current)|\(goal.isCompleted)"
    }
}
