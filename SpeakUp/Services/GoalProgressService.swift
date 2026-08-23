import Foundation
import SwiftData

/// Per-goal numbers from the background scan — plain values, so the main
/// context only applies diffs (pattern: `HistoryViewModel.RecordingSummary`).
nonisolated struct GoalProgressOutcome: Sendable {
    let current: Int
}

/// What the scanner needs per goal. Built on the main actor; the window is
/// frozen at dispatch (`min(deadline, Date())`), matching when the old inline
/// pass computed it.
nonisolated struct GoalProgressRequest: Sendable {
    let id: UUID
    let type: GoalType
    let startDate: Date
    let effectiveEnd: Date
}

@MainActor
enum GoalProgressService {
    static func refreshGoals(in context: ModelContext) {
        guard let goals = try? context.fetch(FetchDescriptor<UserGoal>()),
              !goals.isEmpty else { return }

        let requests = goals.map { goal in
            GoalProgressRequest(
                id: goal.id,
                type: goal.type,
                startDate: goal.startDate,
                effectiveEnd: min(goal.deadline, Date())
            )
        }

        // The scan decodes one analysis blob per session; doing that on the
        // main context stalled every Today load and GoalsView open.
        let container = context.container
        Task {
            let outcomes = await Self.computeOutcomes(requests: requests, container: container)
            applyOutcomes(outcomes, to: context)
        }
    }

    // MARK: - Apply

    private static func applyOutcomes(_ outcomes: [UUID: GoalProgressOutcome], to context: ModelContext) {
        guard let goals = try? context.fetch(FetchDescriptor<UserGoal>()) else { return }

        var didMutate = false
        for goal in goals {
            guard let outcome = outcomes[goal.id] else { continue }
            let snapshot = goalSnapshot(goal)
            goal.current = max(0, outcome.current)
            goal.isCompleted = goal.current >= goal.target
            if snapshot != goalSnapshot(goal) {
                didMutate = true
            }
        }

        if didMutate {
            try? context.save()
        }
    }

    private static func goalSnapshot(_ goal: UserGoal) -> String {
        "\(goal.id.uuidString)|\(goal.current)|\(goal.isCompleted)"
    }

    // MARK: - Scan

    nonisolated private static func computeOutcomes(
        requests: [GoalProgressRequest],
        container: ModelContainer
    ) async -> [UUID: GoalProgressOutcome] {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.date)])
            guard let recordings = try? context.fetch(descriptor) else { return [:] }

            var sessionCounts: [UUID: Int] = [:]
            var streakDates: [UUID: [Date]] = [:]
            var totalSeconds: [UUID: TimeInterval] = [:]
            var scores: [UUID: [Int]] = [:]
            var fillerRatios: [UUID: [Double]] = [:]

            for recording in recordings {
                // One decode feeds every goal whose window this session falls in.
                let analysis = recording.analysis
                for request in requests where recording.date >= request.startDate && recording.date <= request.effectiveEnd {
                    switch request.type {
                    case .sessionsPerWeek:
                        sessionCounts[request.id, default: 0] += 1
                    case .practiceStreak:
                        streakDates[request.id, default: []].append(recording.date)
                    case .totalMinutes:
                        totalSeconds[request.id, default: 0] += recording.actualDuration
                    case .improveScore:
                        if let score = analysis?.speechScore.overall {
                            scores[request.id, default: []].append(score)
                        }
                    case .reduceFiller:
                        if let analysis, analysis.totalWords > 0 {
                            fillerRatios[request.id, default: []].append(
                                Double(analysis.totalFillerCount) / Double(analysis.totalWords)
                            )
                        }
                    }
                }
            }

            var outcomes: [UUID: GoalProgressOutcome] = [:]
            for request in requests {
                let currentValue: Int
                switch request.type {
                case .sessionsPerWeek:
                    currentValue = sessionCounts[request.id] ?? 0
                case .practiceStreak:
                    currentValue = maxStreakDays(in: streakDates[request.id] ?? [])
                case .totalMinutes:
                    currentValue = Int(((totalSeconds[request.id] ?? 0) / 60.0).rounded())
                case .improveScore:
                    currentValue = scoreImprovement(from: scores[request.id] ?? [])
                case .reduceFiller:
                    currentValue = fillerReductionPercent(from: fillerRatios[request.id] ?? [])
                }
                outcomes[request.id] = GoalProgressOutcome(current: currentValue)
            }
            return outcomes
        }.value
    }

    nonisolated private static func maxStreakDays(in dates: [Date]) -> Int {
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

    nonisolated private static func scoreImprovement(from scores: [Int]) -> Int {
        guard scores.count >= 2 else { return 0 }
        let baselineSample = Array(scores.prefix(min(3, scores.count)))
        let recentSample = Array(scores.suffix(min(3, scores.count)))

        let baseline = Double(baselineSample.reduce(0, +)) / Double(max(1, baselineSample.count))
        let recent = Double(recentSample.reduce(0, +)) / Double(max(1, recentSample.count))
        return max(0, Int((recent - baseline).rounded()))
    }

    nonisolated private static func fillerReductionPercent(from ratios: [Double]) -> Int {
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
}
