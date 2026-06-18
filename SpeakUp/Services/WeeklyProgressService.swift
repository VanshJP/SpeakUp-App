import Foundation

nonisolated struct WeeklyProgressData: Sendable {
    let sessionsThisWeek: Int
    let totalMinutes: Double
}

nonisolated enum WeeklyProgressService {
    static func calculate(recordings: [Recording]) -> WeeklyProgressData? {
        let calendar = Calendar.current
        let now = Date()
        guard let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return nil
        }

        let thisWeek = recordings.filter { $0.date >= startOfThisWeek }
        guard !thisWeek.isEmpty else { return nil }

        let totalMinutes = thisWeek.reduce(0) { $0 + $1.actualDuration } / 60

        return WeeklyProgressData(
            sessionsThisWeek: thisWeek.count,
            totalMinutes: totalMinutes
        )
    }
}
