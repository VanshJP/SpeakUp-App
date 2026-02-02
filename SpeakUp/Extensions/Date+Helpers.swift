import Foundation

extension Date {
    // MARK: - Start of Periods
    
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    var startOfWeek: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }
    
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }
    
    // MARK: - End of Periods
    
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }
    
    var endOfWeek: Date {
        var components = DateComponents()
        components.weekOfYear = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfWeek) ?? self
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
    
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }
    
    // MARK: - Date Arithmetic
    
    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
    
    func adding(weeks: Int) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: self) ?? self
    }
    
    func adding(months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }
    
    var daysBetweenNow: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: self.startOfDay, to: Date().startOfDay)
        return components.day ?? 0
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
    
    var shortFormatted: String {
        formatted(.dateTime.month(.abbreviated).day())
    }
    
    var timeFormatted: String {
        formatted(.dateTime.hour().minute())
    }
    
    var weekdayName: String {
        formatted(.dateTime.weekday(.abbreviated))
    }
    
    var dayOfMonth: Int {
        Calendar.current.component(.day, from: self)
    }
    
    // MARK: - Week Helpers
    
    var weekNumber: Int {
        Calendar.current.component(.weekOfYear, from: self)
    }
    
    static func weeksInRange(from startDate: Date, to endDate: Date) -> [Date] {
        var weeks: [Date] = []
        var current = startDate.startOfWeek
        
        while current <= endDate {
            weeks.append(current)
            current = current.adding(weeks: 1)
        }
        
        return weeks
    }
    
    // MARK: - Streak Calculation
    
    static func calculateStreak(from dates: [Date]) -> Int {
        guard !dates.isEmpty else { return 0 }
        
        let sortedDates = dates.map { $0.startOfDay }.sorted(by: >)
        let uniqueDates = Array(Set(sortedDates)).sorted(by: >)
        
        guard let mostRecent = uniqueDates.first else { return 0 }
        
        // Check if the most recent date is today or yesterday
        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        
        guard mostRecent == today || mostRecent == yesterday else {
            return 0
        }
        
        var streak = 1
        var previousDate = mostRecent
        
        for date in uniqueDates.dropFirst() {
            let expectedPrevious = previousDate.adding(days: -1)
            if date == expectedPrevious {
                streak += 1
                previousDate = date
            } else {
                break
            }
        }
        
        return streak
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    var formattedDuration: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedDurationLong: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedMinutes: String {
        let minutes = Int(self) / 60
        return "\(minutes) min"
    }
}
