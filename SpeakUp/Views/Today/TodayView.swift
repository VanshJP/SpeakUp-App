import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TodayViewModel()

    @Query private var userSettings: [UserSettings]
    @State private var showingFirstRecordingSetup = false

    // Focus-card routing — mirrors the post-session NextStep sheets in
    // RecordingDetailView so both entry points land on the same tool.
    @State private var focusDrill: DrillMode?
    @State private var showingFocusWarmUp = false
    @State private var showingFocusReadAloud = false

    var onStartRecording: (Prompt?, RecordingDuration) -> Void
    var onShowWheel: () -> Void
    var onShowWarmUps: () -> Void
    var onShowDrills: () -> Void
    var onShowConfidence: () -> Void
    var onShowCurriculum: () -> Void
    var onShowAchievements: () -> Void = {}
    var onStartStoryPractice: ((Story) -> Void)?

    var body: some View {
        ZStack {
            AppBackground()

            // Explicit vertical axis — the Today screen is intentionally locked
            // to vertical scrolling only. No horizontal paging, no TabView page
            // style, no horizontal ScrollView.
            ScrollView(.vertical) {
                VStack(spacing: 20) {

                    // 1. Header — date + streak chip
                    topHeaderRow

                    // 2. Where you stand (tap → full Progress charts).
                    ringStatsSection

                    // 3. What to do about it. Reads as the conclusion drawn
                    //    from the rings directly above, which is why it sits
                    //    between the stats and the generic prompt path.
                    focusSection

                    // 4. Core action — today's prompt + start buttons
                    interactivePromptSection
                    startButtonSection

                    // 5. Quick actions
                    toolbarStrip

                    // 6. Daily challenge
                    if let challenge = viewModel.dailyChallenge {
                        DailyChallengeCard(challenge: challenge)
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable {
            await viewModel.loadData()
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
        .task {
            await checkFirstRecordingSetup()
        }
        .sheet(isPresented: $showingFirstRecordingSetup) {
            FirstRecordingSetupSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $focusDrill) { mode in
            DrillSelectionView(initialMode: mode)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingFocusWarmUp) {
            WarmUpListView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingFocusReadAloud) {
            ReadAloudSelectionView()
                .presentationDetents([.large])
        }
    }

    // MARK: - Focus Section

    /// Hidden until there is something to average. One analyzed session is a
    /// mood, not a pattern — below the threshold the prompt card is the honest
    /// primary action.
    private static let focusMinimumSessions = 2

    @ViewBuilder
    private var focusSection: some View {
        let samples = viewModel.recentSubscores

        if samples.count >= Self.focusMinimumSessions,
           let rolling = SpeechSubscores.rollingAverage(samples) {
            TodayFocusCard(
                step: NextStep.from(rolling),
                sessionCount: samples.count,
                onAction: self.handleFocusAction
            )
        }
    }

    private func handleFocusAction(_ action: NextStep.Action) {
        switch action {
        case .drill(let mode):
            focusDrill = mode
        case .warmUp:
            showingFocusWarmUp = true
        case .readAloud:
            showingFocusReadAloud = true
        case .practiceAgain:
            onStartRecording(viewModel.todaysPrompt, viewModel.selectedDuration)
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

    // MARK: - Top Header

    private var topHeaderRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(headline)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            Spacer()

            NavigationLink {
                StreakDetailView()
            } label: {
                StreakChip(streak: viewModel.userStats.currentStreak)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    private var headline: String {
        let name = userSettings.first?.userName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Ready to practice?" : "\(greeting), \(name)"
    }

    // MARK: - Ring Stats Section

    private var ringStatsSection: some View {
        NavigationLink {
            ProgressChartsView()
        } label: {
            RingStatsView(
                sessions: viewModel.userStats.weeklySessionCount,
                sessionsGoal: viewModel.userStats.weeklyGoalSessions,
                score: Int(viewModel.userStats.averageScore),
                bestScore: viewModel.userStats.bestScore,
                improvement: viewModel.userStats.improvementRate
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Haptics.medium() })
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
                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.94))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
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
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .fill(AppColors.surfaceLift)
                        }
                        .overlay {
                            Capsule()
                                .stroke(AppColors.cardStroke, lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
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

                    SmallIconButton(icon: "arrow.clockwise", label: "Different story") {
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

                    SmallIconButton(icon: "arrow.clockwise", label: "Different prompt") {
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

    // Four shortcuts, not six — Vocab lives in Settings and Read-Aloud in the
    // Library's Tools section, so Today keeps only what starts a session now.
    private var toolbarStrip: some View {
        HStack(spacing: 8) {
            quickActionTile(icon: "wind", label: "Warm Up", color: AppColors.toolWarmUp) {
                onShowWarmUps()
            }
            quickActionTile(icon: "bolt.fill", label: "Drills", color: AppColors.toolDrill) {
                onShowDrills()
            }
            quickActionTile(icon: "heart.fill", label: "Calm", color: AppColors.toolCalm) {
                onShowConfidence()
            }
            quickActionTile(icon: "shuffle", label: "Wheel", color: AppColors.toolWheel) {
                onShowWheel()
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.surfaceLift)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.cardStroke, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

}

// MARK: - Interactive Prompt Card

struct InteractivePromptCard: View {
    let prompt: Prompt?
    @Binding var selectedDuration: RecordingDuration
    let onTap: () -> Void
    let onRefresh: () -> Void

    @State private var isPulsing = false

    var body: some View {
        GlassCard(padding: 20, elevated: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(prompt?.category ?? "Loading...")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                    }
                    .foregroundStyle(categoryColor)

                    Spacer()

                    if let difficulty = prompt?.difficulty {
                        StatusPill.difficulty(difficulty)
                    }
                }

                Text(prompt?.text ?? "Loading today's prompt...")
                    .font(.title3.weight(.semibold))
                    .lineSpacing(3)
                    .lineLimit(4)
                    .foregroundStyle(prompt == nil ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    DurationPill(selectedDuration: $selectedDuration)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .opacity(isPulsing ? 0.6 : 1.0)

                        Text("Tap to start")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Whole card starts the session; the duration Menu still wins
            // its own taps because child controls take gesture priority.
            .contentShape(Rectangle())
            .onTapGesture { Haptics.medium(); onTap() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(prompt.map { "Daily prompt: \($0.text)" } ?? "Loading today's prompt")
            .accessibilityHint("Starts a practice recording")
        }
        .redacted(reason: prompt == nil ? .placeholder : [])
        .ambientLoop(AppMotion.ambient(duration: 1.2)) { isPulsing = true }
    }

    private var categoryColor: Color {
        guard let category = prompt?.category else { return AppColors.accent }
        return PromptCategory(rawValue: category)?.color ?? AppColors.accent
    }

    private var categoryIcon: String {
        guard let category = prompt?.category else { return "questionmark.circle" }
        return PromptCategory(rawValue: category)?.iconName ?? "text.bubble"
    }
}

// MARK: - Small Icon Button (for card actions)

struct SmallIconButton: View {
    let icon: String
    /// VoiceOver / Voice Control name — required so icon-only control is not silent.
    var label: String
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: icon) {
            Haptics.light()
            action()
        }
        .labelStyle(.iconOnly)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(width: 32, height: 32)
        .background {
            Circle()
                .fill(.ultraThinMaterial)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .buttonStyle(GlassPressStyle())
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
            onStartStoryPractice: { _ in }
        )
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self], inMemory: true)
}

