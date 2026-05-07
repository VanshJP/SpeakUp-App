import SwiftUI
import SwiftData

struct StreakDetailView: View {
    @Query(sort: \Recording.date, order: .reverse) private var recordings: [Recording]
    @Query private var achievements: [Achievement]

    private var streakAchievements: [Achievement] {
        achievements
            .filter { $0.id.hasPrefix("streak_") }
            .sorted { lhs, rhs in
                (Self.streakAchievementThreshold(id: lhs.id) ?? .max)
                    < (Self.streakAchievementThreshold(id: rhs.id) ?? .max)
            }
    }

    private var streakAchievementsUnlocked: Int {
        streakAchievements.filter(\.isUnlocked).count
    }

    private static func streakAchievementThreshold(id: String) -> Int? {
        Int(id.replacingOccurrences(of: "streak_", with: ""))
    }

    private var currentStreak: Int {
        Date.calculateStreak(from: recordings.map(\.date))
    }

    private var longestStreak: Int {
        Self.calculateLongestStreak(from: recordings.map(\.date))
    }

    private var lastFourteenDays: [DayCell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let practiced: Set<Date> = Set(
            recordings.map { calendar.startOfDay(for: $0.date) }
        )
        return (0..<14).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return DayCell(
                date: date,
                practiced: practiced.contains(date),
                isToday: calendar.isDateInToday(date)
            )
        }
    }

    private var nextMilestone: Int {
        let milestones = [3, 7, 14, 30, 60, 100, 180, 365, 500, 1000]
        return milestones.first { $0 > currentStreak } ?? (currentStreak + 100)
    }

    private var milestoneProgress: Double {
        let prev = lastMilestone
        let span = max(1, nextMilestone - prev)
        return Double(currentStreak - prev) / Double(span)
    }

    private var lastMilestone: Int {
        let milestones = [0, 3, 7, 14, 30, 60, 100, 180, 365, 500, 1000]
        return milestones.last { $0 <= currentStreak } ?? 0
    }

    private var encouragement: String {
        switch currentStreak {
        case 0: return "Today is day one. Tap the mic and light the flame."
        case 1: return "First spark. Keep showing up tomorrow and it grows."
        case 2...3: return "The fire is catching. Don't let it die."
        case 4...6: return "Four days in, almost a week. You're building a habit."
        case 7...13: return "A full week strong. The flame is steady now."
        case 14...29: return "Two weeks. This is real momentum."
        case 30...59: return "A month of daily practice. Most people never get here."
        case 60...99: return "Two months deep. Speech is becoming second nature."
        case 100...364: return "Triple digits. You are one of the few who don't quit."
        default: return "A year-plus on fire. Legendary."
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                heroFlame
                statsRow
                milestoneCard
                calendarCard
                encouragementCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background {
            AppBackground(style: .subtle)
        }
        .navigationTitle("Streak")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Hero

    private var heroFlame: some View {
        let isLit = currentStreak > 0
        return VStack(spacing: 28) {
            FlameAnimationView(size: 220, isLit: isLit)
                .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("\(currentStreak)")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isLit
                                ? [
                                    Color(red: 1.0, green: 0.96, blue: 0.78),
                                    Color(red: 1.0, green: 0.62, blue: 0.18),
                                    Color(red: 0.95, green: 0.28, blue: 0.08)
                                ]
                                : [
                                    Color(red: 0.70, green: 0.72, blue: 0.78),
                                    Color(red: 0.45, green: 0.48, blue: 0.55),
                                    Color(red: 0.28, green: 0.31, blue: 0.38)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: isLit ? Color.orange.opacity(0.55) : .clear, radius: 14, y: 4)
                    .contentTransition(.numericText(value: Double(currentStreak)))

                Text("DAY STREAK")
                    .font(.caption.weight(.heavy))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(isLit ? 0.7 : 0.45))
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(
                icon: currentStreak > 0 ? "flame.fill" : "flame",
                iconColor: currentStreak > 0 ? .orange : .white.opacity(0.35),
                value: "\(currentStreak)",
                unit: currentStreak == 1 ? "day" : "days",
                label: "Current"
            )
            statTile(
                icon: "trophy.fill",
                iconColor: .yellow,
                value: "\(longestStreak)",
                unit: longestStreak == 1 ? "day" : "days",
                label: "Best"
            )
        }
    }

    private func statTile(icon: String, iconColor: Color, value: String, unit: String, label: String) -> some View {
        GlassCard(tint: iconColor.opacity(0.06), padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(unit)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Milestone

    private var milestoneCard: some View {
        NavigationLink {
            AchievementGalleryView()
        } label: {
            GlassCard(tint: .orange.opacity(0.06)) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Next Milestone", systemImage: "target")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(currentStreak) / \(nextMilestone)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.yellow, Color.orange, Color.red.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * milestoneProgress))
                                .shadow(color: Color.orange.opacity(0.5), radius: 6, y: 1)
                        }
                    }
                    .frame(height: 10)

                    let remaining = max(0, nextMilestone - currentStreak)
                    Text(remaining == 0
                         ? "You hit \(nextMilestone) days. New milestone unlocked."
                         : "\(remaining) day\(remaining == 1 ? "" : "s") to \(nextMilestone)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))

                    if !streakAchievements.isEmpty {
                        Divider().overlay(Color.white.opacity(0.08))

                        HStack(spacing: 10) {
                            HStack(spacing: -6) {
                                ForEach(streakAchievements.prefix(3), id: \.id) { achievement in
                                    streakAchievementBadge(achievement)
                                }
                            }

                            Text("\(streakAchievementsUnlocked) of \(streakAchievements.count) streak awards")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))

                            Spacer()

                            HStack(spacing: 3) {
                                Text("View all")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
    }

    private func streakAchievementBadge(_ achievement: Achievement) -> some View {
        ZStack {
            Circle()
                .fill(achievement.isUnlocked ? Color.orange.opacity(0.85) : Color.white.opacity(0.06))
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                }
                .shadow(color: achievement.isUnlocked ? Color.orange.opacity(0.4) : .clear, radius: 4, y: 1)

            Image(systemName: achievement.isUnlocked ? achievement.icon : "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(achievement.isUnlocked ? .white : .white.opacity(0.35))
        }
        .frame(width: 26, height: 26)
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        GlassCard(tint: .teal.opacity(0.05)) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Last 14 Days", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    ForEach(lastFourteenDays) { day in
                        VStack(spacing: 6) {
                            Text(day.weekdayShort)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))

                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(day.practiced
                                          ? Color.orange.opacity(0.85)
                                          : Color.white.opacity(0.06))
                                    .frame(height: 28)
                                    .overlay {
                                        if day.practiced {
                                            Image(systemName: "flame.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .shadow(color: day.practiced ? Color.orange.opacity(0.4) : .clear, radius: 4, y: 1)

                                if day.isToday {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                                        .frame(height: 28)
                                }
                            }

                            Text(day.dayNumber)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Encouragement

    private var encouragementCard: some View {
        GlassCard(tint: .orange.opacity(0.04)) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 28)

                Text(encouragement)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Helpers

    private struct DayCell: Identifiable {
        let date: Date
        let practiced: Bool
        let isToday: Bool

        var id: Date { date }

        var weekdayShort: String {
            let f = DateFormatter()
            f.dateFormat = "EEEEE" // S, M, T, W, T, F, S
            return f.string(from: date)
        }

        var dayNumber: String {
            let f = DateFormatter()
            f.dateFormat = "d"
            return f.string(from: date)
        }
    }

    private static func calculateLongestStreak(from dates: [Date]) -> Int {
        let calendar = Calendar.current
        let unique = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !unique.isEmpty else { return 0 }
        let sorted = unique.sorted()
        var longest = 1
        var current = 1
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            if let next = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(next, inSameDayAs: curr) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }
}

#Preview {
    NavigationStack {
        StreakDetailView()
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self], inMemory: true)
}
