import SwiftUI
import SwiftData
import Charts

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TodayViewModel()
    @State private var weakAreaService = WeakAreaService()
    @State private var curriculumViewModel = CurriculumViewModel()

    @Query private var achievements: [Achievement]
    @Query private var userSettings: [UserSettings]
    @State private var showingFirstRecordingSetup = false

    var onStartRecording: (Prompt?, RecordingDuration) -> Void
    var onShowWheel: () -> Void
    var onShowWarmUps: () -> Void
    var onShowDrills: () -> Void
    var onShowConfidence: () -> Void
    var onShowCurriculum: () -> Void
    var onShowAchievements: () -> Void = {}
    var onShowWordBank: () -> Void = {}
    var onShowReadAloud: () -> Void = {}
    var onStartStoryPractice: ((Story) -> Void)?

    var body: some View {
        ZStack {
            AppBackground()

            // Explicit vertical axis — the Today screen is intentionally locked
            // to vertical scrolling only. No horizontal paging, no TabView page
            // style, no horizontal ScrollView.
            ScrollView(.vertical) {
                VStack(spacing: 20) {

                    // 1. Header Stats (Ring visualization)
                    headerSection

                    // 2. Interactive Prompt Card + Start Buttons
                    interactivePromptSection
                    startButtonSection

                    // 3. Quick Actions Strip
                    toolbarStrip

                    // 4. Continue Learning (Curriculum)
                    if curriculumViewModel.currentLesson != nil {
                        CurriculumProgressCard(
                            viewModel: curriculumViewModel,
                            onTap: { onShowCurriculum() }
                        )
                    }

                    // 5. Your Progress (merged snapshot + insights + weekly)
                    progressSummaryCard

                    // 6. Streak & Achievements (compact row)
                    streakAndAchievementsStrip

                    // 7. Suggested For You (weak areas)
                    suggestedSection

                    // 8. Daily Challenge
                    if let challenge = viewModel.dailyChallenge {
                        DailyChallengeCard(challenge: challenge)
                    }

                    // 9. Daily Tip
                    dailyTipSection
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Today")
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable {
            await viewModel.loadData()
        }
        .onAppear {
            viewModel.configure(with: modelContext)
            curriculumViewModel.loadProgress(context: modelContext)
        }
        .onChange(of: viewModel.isLoading) { _, newValue in
            if !newValue {
                weakAreaService.analyze(subscores: viewModel.recentSubscores)
            }
        }
        .task {
            await checkFirstRecordingSetup()
        }
        .sheet(isPresented: $showingFirstRecordingSetup) {
            FirstRecordingSetupSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - First Recording Setup

    private func checkFirstRecordingSetup() async {
        guard userSettings.first?.hasShownFirstRecordingSetup != true else { return }
        let descriptor = FetchDescriptor<Recording>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard count >= 1 else { return }
        showingFirstRecordingSetup = true
        if let settings = userSettings.first {
            settings.hasShownFirstRecordingSetup = true
            try? modelContext.save()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        RingStatsView(
            streak: viewModel.userStats.currentStreak,
            sessions: viewModel.userStats.weeklySessionCount,
            sessionsGoal: viewModel.userStats.weeklyGoalSessions,
            score: Int(viewModel.userStats.averageScore),
            improvement: viewModel.userStats.improvementRate
        )
    }

    private var streakMessage: String {
        let streak = viewModel.userStats.currentStreak
        if streak >= 30 { return "Incredible dedication!" }
        if streak >= 14 { return "Two weeks strong!" }
        if streak >= 7 { return "A full week!" }
        return "Keep showing up!"
    }

    // MARK: - Start Button Section

    private var startButtonSection: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.medium()
                if viewModel.storyPracticeEnabled, let story = viewModel.todaysStory {
                    onStartStoryPractice?(story)
                } else {
                    onStartRecording(
                        viewModel.todaysPrompt,
                        viewModel.selectedDuration
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.storyPracticeEnabled ? "book.pages" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(viewModel.storyPracticeEnabled ? "With Story" : "With Prompt")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.teal, Color.cyan.opacity(0.85), Color.teal.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .teal.opacity(0.4), radius: 12, y: 3)
                }
                .overlay {
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .white.opacity(0.1), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.medium()
                onStartRecording(nil, viewModel.selectedDuration)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Free Practice")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.teal.opacity(0.9), Color.cyan.opacity(0.75), Color.teal.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .teal.opacity(0.3), radius: 10, y: 3)
                }
                .overlay {
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.08), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Interactive Prompt Section

    private var interactivePromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.storyPracticeEnabled, let story = viewModel.todaysStory {
                HStack {
                    Label("Today's Story", systemImage: "book.pages.fill")
                        .font(.headline)

                    Spacer()

                    SmallIconButton(icon: "arrow.clockwise") {
                        Task {
                            await viewModel.refreshStory()
                        }
                    }
                }

                StoryPromptCard(
                    story: story,
                    selectedDuration: $viewModel.selectedDuration,
                    onTap: {
                        onStartStoryPractice?(story)
                    }
                )
            } else {
                HStack {
                    Label("Today's Prompt", systemImage: "text.bubble.fill")
                        .font(.headline)

                    Spacer()

                    SmallIconButton(icon: "arrow.clockwise") {
                        Task {
                            await viewModel.refreshPrompt()
                        }
                    }
                }

                InteractivePromptCard(
                    prompt: viewModel.todaysPrompt,
                    selectedDuration: $viewModel.selectedDuration,
                    onTap: {
                        onStartRecording(
                            viewModel.todaysPrompt,
                            viewModel.selectedDuration
                        )
                    },
                    onRefresh: {
                        Task {
                            await viewModel.refreshPrompt()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Quick Actions Strip

    private var toolbarStrip: some View {
        HStack(spacing: 8) {
            quickActionTile(icon: "wind", label: "Warm Up", color: .blue) {
                onShowWarmUps()
            }
            quickActionTile(icon: "bolt.fill", label: "Drills", color: .orange) {
                onShowDrills()
            }
            quickActionTile(icon: "heart.fill", label: "Calm", color: .pink) {
                onShowConfidence()
            }
            quickActionTile(icon: "shuffle", label: "Wheel", color: .purple) {
                onShowWheel()
            }
            quickActionTile(icon: "character.book.closed", label: "Vocab", color: .green) {
                onShowWordBank()
            }
        }
    }

    private func quickActionTile(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(height: 22)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(color.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.08), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(QuickActionTileStyle())
    }

    private struct QuickActionTileStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
                .brightness(configuration.isPressed ? 0.1 : 0)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }

    // MARK: - Suggested Section

    @ViewBuilder
    private var suggestedSection: some View {
        if let suggestion = weakAreaService.suggestion {
            VStack(alignment: .leading, spacing: 12) {
                Label("Suggested For You", systemImage: "sparkles")
                    .font(.headline)

                Button {
                    switch suggestion.type {
                    case .drill:
                        onShowDrills()
                    case .exercise, .practice:
                        onStartRecording(nil, viewModel.selectedDuration)
                    }
                } label: {
                    FeaturedGlassCard(gradientColors: [.purple.opacity(0.12), .blue.opacity(0.06)]) {
                        HStack(spacing: 14) {
                            Image(systemName: suggestion.icon)
                                .font(.title2)
                                .foregroundStyle(.purple)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(suggestion.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Progress Summary Card (merged snapshot + insights + weekly)

    @ViewBuilder
    private var progressSummaryCard: some View {
        let recentScores = viewModel.sparklineScores

        NavigationLink {
            ProgressChartsView()
        } label: {
            GlassCard(tint: .teal.opacity(0.06)) {
                VStack(spacing: 14) {
                    HStack {
                        Label("Your Progress", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        HStack(spacing: 4) {
                            Text("Details")
                                .font(.caption)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }

                    if recentScores.count >= 3 {
                        let latestScore = recentScores.last?.score ?? 0
                        let firstScore = recentScores.first?.score ?? 0
                        let trendDelta = latestScore - firstScore

                        // Sparkline
                        Chart {
                            ForEach(Array(recentScores.enumerated()), id: \.offset) { _, point in
                                LineMark(
                                    x: .value("Date", point.date),
                                    y: .value("Score", point.score)
                                )
                                .foregroundStyle(.teal.opacity(0.8))
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                .interpolationMethod(.catmullRom)

                                AreaMark(
                                    x: .value("Date", point.date),
                                    y: .value("Score", point.score)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.teal.opacity(0.2), .teal.opacity(0.01)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartYScale(domain: max(0, (recentScores.map(\.score).min() ?? 0) - 10)...min(100, (recentScores.map(\.score).max() ?? 100) + 10))
                        .frame(height: 48)

                        // Stats row
                        HStack(spacing: 0) {
                            progressStatItem(
                                value: "\(latestScore)",
                                label: "Latest",
                                color: AppColors.scoreColor(for: latestScore)
                            )
                            progressStatItem(
                                value: trendDelta >= 0 ? "+\(trendDelta)" : "\(trendDelta)",
                                label: "Trend",
                                color: trendDelta > 0 ? .green : trendDelta < 0 ? .red : .secondary
                            )
                            progressStatItem(
                                value: topFillerDisplay,
                                label: "Top Filler",
                                color: .orange
                            )
                            progressStatItem(
                                value: viewModel.userStats.formattedPracticeTime,
                                label: "Practice",
                                color: .purple
                            )
                        }
                    } else {
                        Text("Complete 3 sessions to see your progress trend")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }

                    if let weeklyData = viewModel.weeklyProgress {
                        Divider().overlay(Color.white.opacity(0.06))

                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .font(.caption)
                                .foregroundStyle(.teal)
                            Text("This week: \(weeklyData.sessionsThisWeek) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func progressStatItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var topFillerDisplay: String {
        if let topFiller = viewModel.userStats.mostUsedFillers.first {
            return "\"\(topFiller.word)\""
        }
        return "None"
    }

    // MARK: - Streak & Achievements Strip (compact merged row)

    private var streakAndAchievementsStrip: some View {
        let streak = viewModel.userStats.currentStreak
        let unlocked = achievements.filter(\.isUnlocked).count
        let total = achievements.count

        return HStack(spacing: 12) {
            StreakTile(streak: streak, message: streakMessage)

            AchievementsTile(unlocked: unlocked, total: total) {
                onShowAchievements()
            }
        }
    }

    // MARK: - Daily Tip Section

    private var dailyTipSection: some View {
        GlassCard(tint: .blue.opacity(0.05)) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Pro Tip")
                        .font(.subheadline.weight(.semibold))

                    Text(dailyTipText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var dailyTipText: String {
        let tips = [
            "Pause intentionally instead of using filler words. A brief silence sounds more confident than \"um.\"",
            "Record yourself daily -- even 30 seconds builds awareness of your speaking patterns.",
            "Speak at 140-160 words per minute for optimal clarity and engagement.",
            "Start your response by restating the question. It buys you time to think.",
            "Use the \"rule of three\" -- group your points in threes for memorable delivery.",
            "Practice with harder prompts to push your comfort zone and grow faster.",
            "Review your transcripts to catch filler patterns you don't notice while speaking."
        ]
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return tips[dayOfYear % tips.count]
    }
}

// MARK: - Interactive Prompt Card

struct InteractivePromptCard: View {
    let prompt: Prompt?
    @Binding var selectedDuration: RecordingDuration
    let onTap: () -> Void
    let onRefresh: () -> Void

    @State private var isPulsing = false

    var body: some View {
        GlassCard(tint: categoryColor.opacity(0.1), accentBorder: categoryColor.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(prompt?.category ?? "Loading...", systemImage: categoryIcon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(categoryColor)

                    Spacer()

                    if let difficulty = prompt?.difficulty {
                        DifficultyBadge(difficulty: difficulty)
                    }
                }

                Text(prompt?.text ?? "Loading today's prompt...")
                    .font(.title3.weight(.medium))
                    .lineLimit(4)
                    .foregroundStyle(prompt == nil ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { Haptics.medium(); onTap() }

                HStack {
                    DurationPill(selectedDuration: $selectedDuration)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.teal)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .opacity(isPulsing ? 0.6 : 1.0)

                        Text("Tap to start")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { Haptics.medium(); onTap() }
                }
            }
        }
        .redacted(reason: prompt == nil ? .placeholder : [])
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private var categoryColor: Color {
        guard let category = prompt?.category else { return .gray }
        return AppColors.categoryColor(category)
    }

    private var categoryIcon: String {
        guard let category = prompt?.category else { return "questionmark.circle" }
        return PromptCategory(rawValue: category)?.iconName ?? "text.bubble"
    }
}

// MARK: - Small Icon Button (for card actions)

struct SmallIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Duration Pill Selector

struct DurationPill: View {
    @Binding var selectedDuration: RecordingDuration

    var body: some View {
        Menu {
            ForEach(RecordingDuration.allCases) { duration in
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        selectedDuration = duration
                    }
                } label: {
                    HStack {
                        Text(duration.displayName)
                        if duration == selectedDuration {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(selectedDuration.displayName)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Difficulty Badge

struct DifficultyBadge: View {
    let difficulty: PromptDifficulty

    var body: some View {
        Text(difficulty.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(AppColors.difficultyColor(difficulty).opacity(0.2))
            }
            .foregroundStyle(AppColors.difficultyColor(difficulty))
    }
}

// MARK: - Practice Tool Card

struct PracticeToolCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard(tint: color.opacity(0.08), padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 30, height: 30)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color)
                    }

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 92)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streak Tile

private struct StreakTile: View {
    let streak: Int
    let message: String

    @State private var animatePulse = false

    private var isActive: Bool { streak >= 1 }

    var body: some View {
        GlassCard(tint: isActive ? .orange.opacity(0.08) : .white.opacity(0.02), padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: isActive
                                    ? [Color.orange.opacity(0.45), Color.orange.opacity(0.0)]
                                    : [Color.white.opacity(0.08), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 28
                            )
                        )
                        .frame(width: 52, height: 52)
                        .scaleEffect(animatePulse && isActive ? 1.12 : 0.95)
                        .opacity(animatePulse && isActive ? 0.55 : 1.0)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isActive
                                    ? [Color.yellow, Color.orange, Color.red.opacity(0.85)]
                                    : [Color.white.opacity(0.35), Color.white.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: isActive ? .orange.opacity(0.5) : .clear, radius: 6, y: 2)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(streak)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: Double(streak)))
                        Text(streak == 1 ? "day" : "days")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Text(isActive ? message : "Start today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                animatePulse = true
            }
        }
    }
}

// MARK: - Achievements Tile

private struct AchievementsTile: View {
    let unlocked: Int
    let total: Int
    let action: () -> Void

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(unlocked) / Double(total)
    }

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            GlassCard(tint: .yellow.opacity(0.07), padding: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 3)
                            .frame(width: 44, height: 44)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                AngularGradient(
                                    colors: [Color.yellow, Color.orange, Color.yellow],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.8), value: progress)

                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.yellow, Color.orange],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .yellow.opacity(0.4), radius: 4, y: 1)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(unlocked)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText(value: Double(unlocked)))
                            Text("/ \(total)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Text("Achievements")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}


#Preview {
    NavigationStack {
        TodayView(
            onStartRecording: { _, _ in },
            onShowWheel: {},
            onShowWarmUps: {},
            onShowDrills: {},
            onShowConfidence: {},
            onShowCurriculum: {},
            onShowAchievements: {},
            onShowWordBank: {},
            onShowReadAloud: {},
            onStartStoryPractice: { _ in }
        )
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self], inMemory: true)
}

