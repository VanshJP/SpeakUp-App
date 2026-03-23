import Foundation

struct WeeklyProgressData {
    let sessionsThisWeek: Int
    let sessionsLastWeek: Int
    let scoreChange: Double        // positive = improved
    let fillerReduction: Double    // positive = reduced fillers (good)
    let totalMinutes: Double
    let dailyScores: [(day: Int, score: Int)]  // day 0=Mon..6=Sun, latest score per day

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

        // Build daily scores for this week (latest score per day)
        var dailyScores: [(day: Int, score: Int)] = []
        let sortedThisWeek = thisWeek.sorted { $0.date < $1.date }
        for recording in sortedThisWeek {
            guard let score = recording.analysis?.speechScore.overall else { continue }
            let weekday = (calendar.component(.weekday, from: recording.date) + 5) % 7 // Mon=0
            // Keep the latest score for each day (overwrite earlier)
            if let existingIdx = dailyScores.firstIndex(where: { $0.day == weekday }) {
                dailyScores[existingIdx] = (day: weekday, score: score)
            } else {
                dailyScores.append((day: weekday, score: score))
            }
        }
        dailyScores.sort { $0.day < $1.day }

        return WeeklyProgressData(
            sessionsThisWeek: thisWeek.count,
            sessionsLastWeek: lastWeek.count,
            scoreChange: thisWeekAvg - lastWeekAvg,
            fillerReduction: lastFillerAvg - thisFillerAvg,
            totalMinutes: totalMinutes,
            dailyScores: dailyScores
        )
    }
}
