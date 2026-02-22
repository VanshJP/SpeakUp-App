import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TodayViewModel()
    @State private var weakAreaService = WeakAreaService()
    @State private var curriculumViewModel = CurriculumViewModel()
    @Query(sort: \Recording.date, order: .reverse) private var recordings: [Recording]

    var onStartRecording: (Prompt?, RecordingDuration) -> Void
    var onShowWheel: () -> Void
    var onShowGoals: () -> Void
    var onShowWarmUps: () -> Void
    var onShowDrills: () -> Void
    var onShowConfidence: () -> Void
    var onShowCurriculum: () -> Void

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {

                    // Header Stats (Ring visualization)
                    headerSection

                    // Interactive Prompt Card (tap to start)
                    interactivePromptSection

                    // Prominent Start Button
                    startButtonSection

                    // Quick-access toolbar strip
                    toolbarStrip

                    // Continue Learning (Curriculum)
                    if curriculumViewModel.currentLesson != nil {
                        CurriculumProgressCard(
                            viewModel: curriculumViewModel,
                            onTap: { onShowCurriculum() }
                        )
                    }

                    // Practice Tools 2x2 Grid
                    practiceToolsGrid

                    // Suggested For You (weak areas)
                    suggestedSection

                    // Daily Challenge
                    if let challenge = viewModel.dailyChallenge {
                        DailyChallengeCard(challenge: challenge)
                    }

                    // Streak Celebration (if active)
                    if viewModel.userStats.currentStreak >= 2 {
                        streakCelebrationBanner
                    }

                    // Quick Insights Row
                    quickInsightsSection

                    // Weekly Progress Card
                    if let weeklyData = viewModel.weeklyProgress {
                        WeeklyProgressCard(data: weeklyData)
                    }

                    // Active Goals Preview
                    if !viewModel.activeGoals.isEmpty {
                        goalsPreviewSection
                    }

                    // Daily Tip
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
        .task {
            weakAreaService.analyze(recordings: Array(recordings))
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        RingStatsView(
            streak: viewModel.userStats.currentStreak,
            sessions: viewModel.userStats.totalRecordings,
            score: Int(viewModel.userStats.averageScore),
            improvement: viewModel.userStats.improvementRate
        )
    }

    // MARK: - Streak Celebration Banner

    private var streakCelebrationBanner: some View {
        FeaturedGlassCard(
            gradientColors: [.orange.opacity(0.15), .yellow.opacity(0.08)]
        ) {
            HStack(spacing: 14) {
                ZStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange, .red],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .frame(width: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.userStats.currentStreak)-Day Streak!")
                        .font(.headline.weight(.bold))

                    Text(streakMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(viewModel.userStats.currentStreak)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(.orange.opacity(0.15))
                            .overlay {
                                Circle()
                                    .stroke(.orange.opacity(0.3), lineWidth: 1.5)
                            }
                    }
            }
        }
    }

    private var streakMessage: String {
        let streak = viewModel.userStats.currentStreak
        if streak >= 30 { return "Incredible dedication! You're a master." }
        if streak >= 14 { return "Two weeks strong! Consistency is key." }
        if streak >= 7 { return "A full week! Your habits are forming." }
        return "Nice momentum! Keep showing up."
    }

    // MARK: - Start Button Section

    private var startButtonSection: some View {
        VStack(spacing: 12) {
            Button {
                onStartRecording(
                    viewModel.todaysPrompt,
                    viewModel.selectedDuration
                )
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Start Session")
                        .font(.headline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.teal, Color.cyan.opacity(0.85), Color.teal.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .teal.opacity(0.5), radius: 16, y: 4)
                        .shadow(color: .cyan.opacity(0.2), radius: 30, y: 8)
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

            HStack(spacing: 12) {
                GlassButton(
                    title: "Free Practice",
                    icon: "waveform",
                    style: .secondary,
                    fullWidth: true
                ) {
                    onStartRecording(nil, viewModel.selectedDuration)
                }

                GlassButton(
                    title: "Spin Wheel",
                    icon: "circle.grid.3x3.fill",
                    style: .secondary,
                    fullWidth: true
                ) {
                    onShowWheel()
                }
            }
        }
    }

    // MARK: - Interactive Prompt Section

    private var interactivePromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    // MARK: - Quick-Access Toolbar Strip

    private var toolbarStrip: some View {
        HStack(spacing: 0) {
            toolbarStripButton(icon: "wind", label: "Warm Up", color: .blue) {
                onShowWarmUps()
            }
            toolbarStripButton(icon: "bolt.fill", label: "Drills", color: .orange) {
                onShowDrills()
            }
            toolbarStripButton(icon: "heart.fill", label: "Calm", color: .pink) {
                onShowConfidence()
            }
            toolbarStripButton(icon: "book.fill", label: "Learn", color: .purple) {
                onShowCurriculum()
            }
        }
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                }
        }
    }

    private func toolbarStripButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Practice Tools 2x2 Grid

    private var practiceToolsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Practice Tools", systemImage: "square.grid.2x2.fill")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                PracticeToolCard(
                    icon: "wind",
                    title: "Warm Up",
                    subtitle: "Breathing & vocal exercises",
                    color: .blue
                ) { onShowWarmUps() }

                PracticeToolCard(
                    icon: "bolt.fill",
                    title: "Quick Drills",
                    subtitle: "Focused skill practice",
                    color: .orange
                ) { onShowDrills() }

                PracticeToolCard(
                    icon: "heart.fill",
                    title: "Confidence",
                    subtitle: "Calming & visualization",
                    color: .pink
                ) { onShowConfidence() }

                PracticeToolCard(
                    icon: "book.fill",
                    title: "Curriculum",
                    subtitle: "Guided learning path",
                    color: .purple
                ) { onShowCurriculum() }
            }
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

    // MARK: - Quick Insights Section

    private var quickInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Insights", systemImage: "lightbulb.fill")
                .font(.headline)

            HStack(spacing: 12) {
                QuickInsightCard(
                    icon: "exclamationmark.bubble.fill",
                    iconColor: .orange,
                    title: topFillerDisplay,
                    subtitle: "Top Filler",
                    gradientColors: [.orange.opacity(0.1), .clear]
                )

                QuickInsightCard(
                    icon: "clock.fill",
                    iconColor: .purple,
                    title: viewModel.userStats.formattedPracticeTime,
                    subtitle: "Total Practice",
                    gradientColors: [.purple.opacity(0.1), .clear]
                )
            }
        }
    }

    private var topFillerDisplay: String {
        if let topFiller = viewModel.userStats.mostUsedFillers.first {
            return "\"\(topFiller.word)\""
        }
        return "None yet"
    }

    // MARK: - Goals Preview Section

    private var goalsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Active Goals", systemImage: "target")
                    .font(.headline)

                Spacer()

                Button {
                    onShowGoals()
                } label: {
                    HStack(spacing: 4) {
                        Text("See All")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.teal)
                }
            }

            ForEach(viewModel.activeGoals.prefix(2)) { goal in
                GoalProgressRow(goal: goal)
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

// MARK: - Quick Insight Card

struct QuickInsightCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var gradientColors: [Color] = [.clear]

    var body: some View {
        GlassCard(tint: gradientColors.first, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

// MARK: - Goal Progress Row

struct GoalProgressRow: View {
    let goal: UserGoal

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: goal.type.iconName)
                        .foregroundStyle(.teal)

                    Text(goal.title)
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Text("\(goal.current)/\(goal.target)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.teal.opacity(0.15))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.teal.opacity(0.7), .teal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * goal.progress)
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
            }
        }
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
            GlassCard(tint: color.opacity(0.08)) {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(color)
                    }

                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 120)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        TodayView(
            onStartRecording: { _, _ in },
            onShowWheel: {},
            onShowGoals: {},
            onShowWarmUps: {},
            onShowDrills: {},
            onShowConfidence: {},
            onShowCurriculum: {}
        )
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}

