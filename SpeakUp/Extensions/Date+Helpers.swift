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
