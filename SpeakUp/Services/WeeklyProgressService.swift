import Foundation

struct WeeklyProgressData {
    let sessionsThisWeek: Int
    let sessionsLastWeek: Int
    let scoreChange: Double        // positive = improved
    let fillerReduction: Double    // positive = reduced fillers (good)
    let totalMinutes: Double

    var hasImproved: Bool { scoreChange > 0 }
    var sessionsDelta: Int { sessionsThisWeek - sessionsLastWeek }
}

enum WeeklyProgressService {
    static func calculate(recordings: [Recording]) -> WeeklyProgressData? {
        let calendar = Calendar.current
        let now = Date()
        guard let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek) else {
            return nil
        }

        let thisWeek = recordings.filter { $0.date >= startOfThisWeek }
        let lastWeek = recordings.filter { $0.date >= startOfLastWeek && $0.date < startOfThisWeek }

        guard !thisWeek.isEmpty || !lastWeek.isEmpty else { return nil }

        let thisWeekScores = thisWeek.compactMap { $0.analysis?.speechScore.overall }
        let lastWeekScores = lastWeek.compactMap { $0.analysis?.speechScore.overall }

        let thisWeekAvg = thisWeekScores.isEmpty ? 0 : Double(thisWeekScores.reduce(0, +)) / Double(thisWeekScores.count)
        let lastWeekAvg = lastWeekScores.isEmpty ? 0 : Double(lastWeekScores.reduce(0, +)) / Double(lastWeekScores.count)

        let thisWeekFillers = thisWeek.compactMap { $0.analysis?.fillerPercentage }
        let lastWeekFillers = lastWeek.compactMap { $0.analysis?.fillerPercentage }

        let thisFillerAvg = thisWeekFillers.isEmpty ? 0 : thisWeekFillers.reduce(0, +) / Double(thisWeekFillers.count)
        let lastFillerAvg = lastWeekFillers.isEmpty ? 0 : lastWeekFillers.reduce(0, +) / Double(lastWeekFillers.count)

        let totalMinutes = thisWeek.reduce(0) { $0 + $1.actualDuration } / 60

        return WeeklyProgressData(
            sessionsThisWeek: thisWeek.count,
            sessionsLastWeek: lastWeek.count,
            scoreChange: thisWeekAvg - lastWeekAvg,
            fillerReduction: lastFillerAvg - thisFillerAvg,
            totalMinutes: totalMinutes
        )
    }
}
