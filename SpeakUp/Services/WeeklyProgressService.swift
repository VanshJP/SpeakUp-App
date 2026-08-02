import Foundation

nonisolated struct WeeklyProgressData: Sendable {
    let sessionsThisWeek: Int
    let totalMinutes: Double

    // Recap vs the previous week — nil when a week has no analyzed sessions.
    let sessionsLastWeek: Int
    let avgScoreThisWeek: Int?
    let avgScoreLastWeek: Int?
    let fillersPerMinThisWeek: Double?
    let fillersPerMinLastWeek: Double?

    /// Enough signal on both sides for a meaningful comparison.
    var hasRecap: Bool {
        sessionsThisWeek >= 2 && sessionsLastWeek >= 1
            && avgScoreThisWeek != nil && avgScoreLastWeek != nil
    }
}

nonisolated enum WeeklyProgressService {
    static func calculate(recordings: [Recording]) -> WeeklyProgressData? {
        let calendar = Calendar.current
        let now = Date()
        guard let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let startOfLastWeek = calendar.date(byAdding: .day, value: -7, to: startOfThisWeek) else {
            return nil
        }

        let thisWeek = recordings.filter { $0.date >= startOfThisWeek }
        guard !thisWeek.isEmpty else { return nil }

        let lastWeek = recordings.filter { $0.date >= startOfLastWeek && $0.date < startOfThisWeek }

        let totalMinutes = thisWeek.reduce(0) { $0 + $1.actualDuration } / 60

        let thisStats = weekStats(for: thisWeek)
        let lastStats = weekStats(for: lastWeek)

        return WeeklyProgressData(
            sessionsThisWeek: thisWeek.count,
            totalMinutes: totalMinutes,
            sessionsLastWeek: lastWeek.count,
            avgScoreThisWeek: thisStats.avgScore,
            avgScoreLastWeek: lastStats.avgScore,
            fillersPerMinThisWeek: thisStats.fillersPerMin,
            fillersPerMinLastWeek: lastStats.fillersPerMin
        )
    }

    private static func weekStats(for recordings: [Recording]) -> (avgScore: Int?, fillersPerMin: Double?) {
        let analyzed = recordings.compactMap { rec -> (score: Int, fillers: Int, minutes: Double)? in
            guard let analysis = rec.analysis, analysis.speechScore.overall > 0 else { return nil }
            return (analysis.speechScore.overall, analysis.totalFillerCount, rec.actualDuration / 60)
        }
        guard !analyzed.isEmpty else { return (nil, nil) }

        let avgScore = Int((Double(analyzed.map(\.score).reduce(0, +)) / Double(analyzed.count)).rounded())
        let totalMinutes = analyzed.map(\.minutes).reduce(0, +)
        let fillersPerMin = totalMinutes > 0
            ? Double(analyzed.map(\.fillers).reduce(0, +)) / totalMinutes
            : nil
        return (avgScore, fillersPerMin)
    }
}
