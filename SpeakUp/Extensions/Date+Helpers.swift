import Foundation

nonisolated extension Date {
    // MARK: - Start of Periods

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    var startOfWeek: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }

    // MARK: - Date Comparisons
    
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }
    
    var isThisWeek: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    var isThisMonth: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Date Arithmetic

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    // MARK: - Formatting
    
    var relativeFormatted: String {
        if isToday {
            return "Today"
        } else if isYesterday {
            return "Yesterday"
        } else if isThisWeek {
            return formatted(.dateTime.weekday(.wide))
        } else if isThisMonth {
            return formatted(.dateTime.month(.abbreviated).day())
        } else {
            return formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
    
    // MARK: - Streak Calculation
    
    /// Consecutive practice days ending today or yesterday.
    ///
    /// `frozenDays` are days a streak freeze covered (`StreakProtection`). A
    /// frozen day **holds** the chain together but does not **extend** it: the
    /// number stays a count of days the user actually spoke, so the streak
    /// never claims practice that never happened.
    static func calculateStreak(
        from dates: [Date],
        frozenDays: [Date] = [],
        now: Date = Date()
    ) -> Int {
        guard !dates.isEmpty else { return 0 }

        let practice = Set(dates.map { $0.startOfDay })
        // A day cannot be both practised and frozen; practice wins so the day
        // still counts toward the number.
        let frozen = Set(frozenDays.map { $0.startOfDay }).subtracting(practice)

        let today = now.startOfDay
        let isCovered: (Date) -> Bool = { practice.contains($0) || frozen.contains($0) }

        // Anchor: the chain is alive if today or yesterday is covered. Today
        // being empty is not a break yet — the day is not over.
        var cursor = today
        if !isCovered(cursor) {
            cursor = today.adding(days: -1)
            guard isCovered(cursor) else { return 0 }
        }

        var streak = 0
        while isCovered(cursor) {
            if practice.contains(cursor) { streak += 1 }
            cursor = cursor.adding(days: -1)
        }

        return streak
    }
}

nonisolated extension TimeInterval {
    var minutesSeconds: String {
        String(format: "%d:%02d", Int(self) / 60, Int(self) % 60)
    }
}
