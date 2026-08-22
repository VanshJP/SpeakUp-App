import SwiftUI
import SwiftData

struct StreakDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var achievements: [Achievement]

    // Only dates are needed here. Fetched once on a background context so
    // opening the streak sheet never hydrates every Recording on the main
    // thread just to compute day math.
    @State private var recordingDates: [Date] = []

    private var streakAchievements: [Achievement] {
        achievements.filter { $0.id.hasPrefix("streak_") }
    }

    private var streakAchievementsUnlocked: Int {
        streakAchievements.filter(\.isUnlocked).count
    }

    private var currentStreak: Int {
        Date.calculateStreak(from: recordingDates)
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

    var body: some View {
        PageScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                heroFlame
                milestoneCard
                calendarCard
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
        .task {
            let container = modelContext.container
            recordingDates = await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<Recording>()
                descriptor.propertiesToFetch = [\.date]
                let recordings = (try? context.fetch(descriptor)) ?? []
                return recordings.map(\.date)
            }.value
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

                Text("DAY STREAK")
                    .font(.caption.weight(.heavy))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(isLit ? 0.7 : 0.45))

                // Best is the only other number worth a pixel here, and it is
                // a footnote to the current one — not its own card.
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
                                        colors: [AppColors.warning.opacity(0.85), AppColors.warning, AppColors.error.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * milestoneProgress))
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
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
    }


    // MARK: - Calendar

    private var calendarCard: some View {
        GlassCard(tint: AppColors.primary.opacity(0.05)) {
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
                                          ? AppColors.warning.opacity(0.85)
                                          : Color.white.opacity(0.06))
                                    .frame(height: 28)
                                    .overlay {
                                        if day.practiced {
                                            Image(systemName: "flame.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .shadow(color: day.practiced ? AppColors.warning.opacity(0.4) : .clear, radius: 4, y: 1)

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


    // MARK: - Helpers

    private struct DayCell: Identifiable {
        let date: Date
        let practiced: Bool
        let isToday: Bool

        var id: Date { date }

        // DateFormatter is expensive to allocate — shared per type, not per cell.
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
