import SwiftUI
import SwiftData

struct StreakDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var achievements: [Achievement]
    @Query private var userSettings: [UserSettings]

    @State private var recordingDates: [Date] = []
    @State private var frozenDays: [Date] = []

    private var streakAchievements: [Achievement] {
        achievements.filter { $0.id.hasPrefix("streak_") }
    }

    private var streakAchievementsUnlocked: Int {
        streakAchievements.filter(\.isUnlocked).count
    }

    private var streakSnapshot: (currentStreak: Int, freezesAvailable: Int, frozenDays: [Date]) {
        StreakProtection.liveSnapshot(
            practiceDays: recordingDates,
            frozenDays: frozenDays
        )
    }

    private var currentStreak: Int {
        streakSnapshot.currentStreak
    }

    private var freezesAvailable: Int {
        streakSnapshot.freezesAvailable
    }

    private var effectiveFrozenDays: Set<Date> {
        Set(streakSnapshot.frozenDays.map { Calendar.current.startOfDay(for: $0) })
    }

    private var uniquePracticeDays: Int {
        Set(recordingDates.map { Calendar.current.startOfDay(for: $0) }).count
    }

    private var longestStreak: Int {
        Self.calculateLongestStreak(from: recordingDates)
    }

    private var lastFourteenDays: [DayCell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let practiced: Set<Date> = Set(
            recordingDates.map { calendar.startOfDay(for: $0) }
        )
        let frozen = effectiveFrozenDays
        return (0..<14).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let day = calendar.startOfDay(for: date)
            return DayCell(
                date: date,
                practiced: practiced.contains(day),
                frozen: !practiced.contains(day) && frozen.contains(day),
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

    var body: some View {
        PageScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                heroFlame
                freezeProtectionCard
                milestoneCard
                calendarCard
            }
            .padding(.horizontal, AppLayout.pageHorizontal)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background {
            AppBackground(style: .subtle)
        }
        .navigationTitle("Streak")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Pushed from Today, whose root hides the bar (ui-design-system rule 9).
        .restoresNavigationBar()
        .task {
            let container = modelContext.container
            let payload = await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<Recording>()
                descriptor.propertiesToFetch = [\.date]
                let recordings = (try? context.fetch(descriptor)) ?? []
                let frozen = (try? context.fetch(FetchDescriptor<UserSettings>()).first?.streakFrozenDays) ?? []
                return (recordings.map(\.date), frozen)
            }.value
            recordingDates = payload.0
            frozenDays = payload.1
        }
        .onChange(of: userSettings.first?.streakFrozenDays ?? []) { _, days in
            frozenDays = days
        }
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
                    .shadow(color: isLit ? AppColors.warning.opacity(0.55) : .clear, radius: 14, y: 4)
                    .contentTransition(.numericText(value: Double(currentStreak)))

                Text("Day streak")
                    .eyebrowStyle(.white.opacity(isLit ? 0.7 : 0.45))

                if longestStreak > currentStreak {
                    Text("Best \(longestStreak) days")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 6)
                }
            }
        }
        .padding(.top, 12)
    }


    // MARK: - Freeze protection

    private var freezeProtectionCard: some View {
        GlassCard(tint: AppColors.primary.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Streak freezes", icon: "snowflake")

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(freezesAvailable)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(freezesAvailable)))

                    Text("freezes banked")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Text(freezeProtectionCopy)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)

                let daysToNext = daysUntilNextFreeze
                if let daysToNext {
                    Divider().overlay(Color.white.opacity(0.08))
                    Text("\(daysToNext) more practice day\(daysToNext == 1 ? "" : "s") to earn the next freeze.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    private var freezeProtectionCopy: String {
        if freezesAvailable > 0 {
            return "A freeze spends itself when you miss a single day with a live streak. There's nothing to tap: open Big Talk the next day and your streak is still standing."
        }
        return "Bank one freeze for every five practice days, up to two. If you miss a single day while a streak is live, the next app open spends a freeze for you."
    }

    private var daysUntilNextFreeze: Int? {
        guard freezesAvailable < StreakProtection.maxBankedFreezes else { return nil }
        let remainder = uniquePracticeDays % StreakProtection.daysPerEarnedFreeze
        guard remainder != 0 else { return StreakProtection.daysPerEarnedFreeze }
        return StreakProtection.daysPerEarnedFreeze - remainder
    }

    // MARK: - Milestone

    private var milestoneCard: some View {
        NavigationLink {
            AchievementGalleryView()
        } label: {
            GlassCard(tint: AppColors.warning.opacity(0.06)) {
                VStack(alignment: .leading, spacing: 14) {
                    GlassCardTitle("Next milestone", icon: "target") {
                        Text("\(currentStreak) / \(nextMilestone)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    TickMeter(fraction: milestoneProgress, color: AppColors.warning)
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
                            Image(systemName: "rosette")
                                .font(.caption)
                                .foregroundStyle(AppColors.warning)

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
        .buttonStyle(GlassPressStyle())
        .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
    }


    // MARK: - Calendar

    private var calendarCard: some View {
        GlassCard(tint: AppColors.primary.opacity(0.05)) {
            VStack(alignment: .leading, spacing: 14) {
                GlassCardTitle("Last 14 days", icon: "calendar")

                HStack(spacing: 6) {
                    ForEach(lastFourteenDays) { day in
                        VStack(spacing: 6) {
                            Text(day.weekdayShort)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))

                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(dayCellFill(for: day))
                                    .frame(height: 28)
                                    .overlay {
                                        if day.practiced {
                                            Image(systemName: "flame.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.white)
                                        } else if day.frozen {
                                            Image(systemName: "snowflake")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(AppColors.primary.opacity(0.95))
                                        }
                                    }
                                    .shadow(color: day.practiced ? AppColors.warning.opacity(0.4) : (day.frozen ? AppColors.primary.opacity(0.25) : .clear), radius: 4, y: 1)

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
                        // One stop per day. Uncombined, VoiceOver read the
                        // letter, the glyph and the number as three swipes
                        // and never said whether the day was practised.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.accessibilityLabel)
                    }
                }
            }
        }
    }


    // MARK: - Helpers

    private func dayCellFill(for day: DayCell) -> Color {
        if day.practiced { return AppColors.warning.opacity(0.85) }
        if day.frozen { return AppColors.primary.opacity(0.22) }
        return Color.white.opacity(0.06)
    }

    private struct DayCell: Identifiable {
        let date: Date
        let practiced: Bool
        let frozen: Bool
        let isToday: Bool

        var id: Date { date }

        // DateFormatter is expensive to allocate - shared per type, not per cell.
        private static let weekdayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEEEE" // S, M, T, W, T, F, S
            return f
        }()

        private static let dayNumberFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "d"
            return f
        }()

        var weekdayShort: String {
            Self.weekdayFormatter.string(from: date)
        }

        var dayNumber: String {
            Self.dayNumberFormatter.string(from: date)
        }

        var accessibilityLabel: String {
            let name = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
            let state = practiced ? "practised" : (frozen ? "covered by a freeze" : "no practice")
            return isToday ? "Today, \(name), \(state)" : "\(name), \(state)"
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
