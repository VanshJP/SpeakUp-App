import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TodayViewModel()

    @Query private var userSettings: [UserSettings]
    @Environment(\.appTour) private var tour
    @State private var showingFirstRecordingSetup = false

    // Arrival moment — fires once per calendar day, on the first open.
    @AppStorage("lastArrivalDay") private var lastArrivalDay = ""
    @State private var arrived = false
    @State private var showArrivalConfetti = false
    @State private var challengeStore = SharedChallengeStore.shared

    // Focus-card routing — mirrors the post-session NextStep sheets in
    // RecordingDetailView so both entry points land on the same tool.
    @State private var focusDrill: DrillMode?
    @State private var showingFocusWarmUp = false
    @State private var showingFocusReadAloud = false
    @State private var showingHomeCustomize = false

    var onStartRecording: (Prompt?, RecordingDuration) -> Void
    var onShowWheel: () -> Void
    var onShowWarmUps: () -> Void
    var onShowDrills: () -> Void
    var onShowConfidence: () -> Void
    var onShowCurriculum: () -> Void
    var onStartStoryPractice: ((Story) -> Void)?

    /// Ordered visible modules from Settings. Empty storage → factory default.
    private var homeModules: [TodayHomeModule] {
        userSettings.first?.todayHomeModules ?? TodayHomeModule.defaultVisible
    }

    var body: some View {
        ZStack {
            AppBackground()

            // Vertical only, and `PageScrollView` is what makes that true: an
            // over-wide child used to let this page pan sideways. No horizontal
            // paging, no TabView page style, no horizontal scroller.
            PageScrollView {
                VStack(spacing: 20) {

                    // 1. Header — date + streak chip + customize
                    topHeaderRow

                    if let challenge = challengeStore.pending {
                        FriendChallengeCard(
                            challenge: challenge,
                            onAccept: { acceptFriendChallenge(challenge) },
                            onDismiss: { challengeStore.dismiss() }
                        )
                    }

                    // Modular home — Bevel-style. Order and visibility come from
                    // `UserSettings.todayHomeLayoutRaw`; session is always forced on.
                    ForEach(homeModules) { module in
                        homeModuleView(module)
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    showingHomeCustomize = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Customize Today")
            }
        }
        .refreshable {
            await viewModel.loadData()
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
        .task {
            playArrivalIfNeeded()
            await checkFirstRunSurfaces()
        }
        // The streak is only known once the load finishes, so the moment waits
        // for it rather than celebrating a zero.
        .onChange(of: viewModel.isLoading) { _, loading in
            if !loading { playArrivalIfNeeded() }
        }
        .sheet(isPresented: $showingFirstRecordingSetup, onDismiss: startTourIfNeeded) {
            FirstRecordingSetupSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingHomeCustomize) {
            NavigationStack {
                TodayHomeCustomizeView()
            }
            .presentationDetents([.large])
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

    // MARK: - Home Modules

    @ViewBuilder
    private func homeModuleView(_ module: TodayHomeModule) -> some View {
        switch module {
        case .rings:
            ringStatsSection
                .tourAnchor(.todayStats)
        case .weeklyRecap:
            weeklyRecapSection
        case .focus:
            // What to do about the rings. Sits above the prompt so the focus
            // is an instruction for the take, not a post-session report.
            focusSection
        case .session:
            sessionModule
                .tourAnchor(.todayPrompt)
        case .tools:
            prepToolsSection
                .tourAnchor(.todayTools)
        case .learn:
            learnShortcutCard
        }
    }

    private var sessionModule: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSectionHeader("Today's session", icon: "mic.fill")

            interactivePromptSection

            // The words are the spec for *this* take — brief above the button.
            SessionBriefRow(
                workout: viewModel.vocabChallenge,
                bankWords: userSettings.first?.vocabWords ?? [],
                onSkip: { viewModel.skipVocabWord($0) },
                onAddToBank: { addSpotlightWordToBank($0) }
            )

            startButtons
                .padding(.top, 2)
        }
    }

    // MARK: - Weekly Recap

    @ViewBuilder
    private var weeklyRecapSection: some View {
        if let progress = viewModel.weeklyProgress, progress.hasRecap, shouldShowWeeklyRecap {
            WeeklyRecapCard(progress: progress) {
                userSettings.first?.lastWeeklySummaryDate = Date()
                try? modelContext.save()
            }
        }
    }

    /// Visible until dismissed; a dismissal stamps lastWeeklySummaryDate, which
    /// hides the card until the next calendar week starts.
    private var shouldShowWeeklyRecap: Bool {
        guard let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return false
        }
        guard let dismissed = userSettings.first?.lastWeeklySummaryDate else { return true }
        return dismissed < weekStart
    }

    // MARK: - Focus Section

    /// Hidden until there is something to average. One analyzed session is a
    /// mood, not a pattern — below the threshold the prompt card is the honest
    /// primary action.
    private static let focusMinimumSessions = 2

    /// The instruction the user reads *before* they speak.
    ///
    /// This is the placement that makes the focus a training instruction rather
    /// than a report — the session screen can only ever tell you what to work
    /// on after the take you could have applied it to.
    @ViewBuilder
    private var focusSection: some View {
        if let plan = viewModel.coachPlan, plan.sessionCount >= Self.focusMinimumSessions {
            CoachFocusCard(
                plan: plan,
                onPractice: self.handleFocusRoute,
                onPracticeAgain: {
                    onStartRecording(viewModel.todaysPrompt, viewModel.selectedDuration)
                }
            )
        }
    }

    private func handleFocusRoute(_ route: CoachPracticeRoute) {
        switch route {
        case .drill(let raw):
            focusDrill = DrillMode(rawValue: raw)
        case .warmUp:
            showingFocusWarmUp = true
        case .readAloud:
            showingFocusReadAloud = true
        }
    }

    private func addSpotlightWordToBank(_ word: VocabChallengeWord) {
        guard let settings = userSettings.first else { return }
        guard WordSafety.allows(word.text) else { return }
        settings.addVocabWord(word.text)
        try? modelContext.save()
        Haptics.success()
    }

    /// Rebuilds the SwiftData prompt (catalog row or the shared insert) so
    /// ContentView can attach challenge chrome via the matching id.
    private func acceptFriendChallenge(_ challenge: SharedChallenge) {
        let payload = SharedPromptPayload(
            promptID: challenge.promptID,
            text: challenge.promptText,
            category: challenge.category,
            difficulty: challenge.difficulty,
            beatScore: challenge.beatScore,
            source: SharedPromptLink.shareSource
        )
        let prompt = SharedPromptResolver.resolve(payload, in: modelContext)
        onStartRecording(prompt, viewModel.selectedDuration)
    }

    // MARK: - First Run Surfaces

    /// The two things that wait for a score before they earn the user's
    /// attention: the deferred setup sheet (calibration, AI model, reminders)
    /// and the layout tour. Strictly sequential — the tour spotlights cut out
    /// of a dimmed layer, which a presented sheet would sit on top of.
    ///
    /// Both are gated on a recording existing, so a user who skipped the
    /// baseline meets them after their first real session instead.
    private func checkFirstRunSurfaces() async {
        guard let settings = userSettings.first else { return }
        let needsSetup = !settings.hasShownFirstRecordingSetup
        guard needsSetup || !settings.hasSeenAppTour else { return }

        let count = (try? modelContext.fetchCount(FetchDescriptor<Recording>())) ?? 0
        guard count >= 1 else { return }

        guard needsSetup else {
            startTourIfNeeded()
            return
        }
        showingFirstRecordingSetup = true
        settings.hasShownFirstRecordingSetup = true
        try? modelContext.save()
    }

    /// Called on setup-sheet dismissal and directly when that sheet has
    /// already been seen. Callers have established that a recording exists.
    private func startTourIfNeeded() {
        guard userSettings.first?.hasSeenAppTour == false else { return }
        tour?.begin()
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

                if let line = arrivalLine {
                    Text(line)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.warning)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }

            Spacer()

            NavigationLink {
                StreakDetailView()
            } label: {
                StreakChip(streak: viewModel.userStats.currentStreak)
                    // The chip is the reward, so it is what moves: one spring
                    // pop on the day's first open, nothing on later ones.
                    .scaleEffect(arrived ? 1 : 0.6)
                    .opacity(arrived ? 1 : 0)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
        }
        .padding(.top, 4)
        .overlay {
            if showArrivalConfetti {
                ConfettiView()
                    .frame(height: 400)
                    .allowsHitTesting(false)
            }
        }
    }

    /// What the streak is actually worth right now. Never claims a day the
    /// user has not earned — before today's session it names the stake.
    private var arrivalLine: String? {
        let streak = viewModel.userStats.currentStreak
        guard arrived, streak >= 1 else { return nil }
        return viewModel.practicedToday
            ? "Day \(streak) locked in"
            : "Day \(streak), one session keeps it"
    }

    /// Runs once per calendar day: pops the streak chip, fires a haptic, and
    /// adds confetti on every seventh day so the milestone still feels rare.
    private func playArrivalIfNeeded() {
        let today = Calendar.current.startOfDay(for: .now).ISO8601Format()
        guard lastArrivalDay != today else {
            arrived = true
            return
        }
        guard !viewModel.isLoading else { return }
        lastArrivalDay = today

        let streak = viewModel.userStats.currentStreak
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15)) {
            arrived = true
        }
        if streak >= 1 {
            Haptics.success()
        }
        if streak >= 7, streak % 7 == 0 {
            showArrivalConfetti = true
        }
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

    // MARK: - Start Buttons

    private var startButtons: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.medium()
                if viewModel.storyPracticeEnabled, let story = viewModel.todaysStory {
                    onStartStoryPractice?(story)
                } else {
                    onStartRecording(viewModel.todaysPrompt, viewModel.selectedDuration)
                }
            } label: {
                startLabel(
                    icon: viewModel.storyPracticeEnabled ? "book.pages" : "mic.fill",
                    title: viewModel.storyPracticeEnabled ? "With Story" : "With Prompt"
                )
                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
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
                startLabel(icon: "waveform", title: "Free Practice")
                    .foregroundStyle(.white)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay { Capsule().fill(AppColors.surfaceLift) }
                            .overlay { Capsule().stroke(AppColors.cardStroke, lineWidth: 0.5) }
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    }
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func startLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
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

    // MARK: - Prep Tools

    /// Outcome-labelled tiles plus an optional coach recommendation. Four
    /// tools that start prep now — Read-Aloud lives in Library Tools.
    private var prepToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Prep tools", icon: "wrench.and.screwdriver.fill") {
                Button {
                    Haptics.light()
                    showingHomeCustomize = true
                } label: {
                    Text("Edit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Customize Today layout")
            }

            if let recommended = recommendedPrepTool {
                recommendedToolBanner(recommended)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(PracticeToolKind.todayStripDefaults) { tool in
                    Button {
                        Haptics.light()
                        openPrepTool(tool)
                    } label: {
                        PrepToolTile(tool: tool, isHighlighted: recommendedPrepTool == tool)
                    }
                    .buttonStyle(QuickActionTileStyle())
                }
            }
        }
    }

    /// Coach route wins when we have enough sessions; otherwise warm-up is the
    /// honest default before a cold take.
    private var recommendedPrepTool: PracticeToolKind? {
        if let plan = viewModel.coachPlan, plan.sessionCount >= Self.focusMinimumSessions {
            return PracticeToolKind.recommended(for: plan.focus.practiceRoute)
        }
        if !viewModel.practicedToday {
            return .warmUp
        }
        return nil
    }

    private func recommendedToolBanner(_ tool: PracticeToolKind) -> some View {
        Button {
            Haptics.medium()
            openPrepTool(tool)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tool.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tool.color)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle().fill(tool.color.opacity(0.18))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggested before you start")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(tool.shortTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(tool.outcome)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tool.color.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(tool.color.opacity(0.3), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(GlassPressStyle())
    }

    private func openPrepTool(_ tool: PracticeToolKind) {
        switch tool {
        case .warmUp: onShowWarmUps()
        case .drills: onShowDrills()
        case .calm: onShowConfidence()
        case .wheel: onShowWheel()
        case .readAloud: showingFocusReadAloud = true
        case .learn: onShowCurriculum()
        }
    }

    // MARK: - Learn Shortcut

    private var learnShortcutCard: some View {
        Button {
            Haptics.medium()
            onShowCurriculum()
        } label: {
            GlassCard(tint: AppColors.primary.opacity(0.08), padding: 16) {
                HStack(spacing: 14) {
                    Image(systemName: PracticeToolKind.learn.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle().fill(AppColors.primary.opacity(0.18))
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(PracticeToolKind.learn.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(PracticeToolKind.learn.outcome)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("\(PracticeToolKind.learn.title). \(PracticeToolKind.learn.outcome)")
    }

    private struct QuickActionTileStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .brightness(configuration.isPressed ? 0.08 : 0)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }

}

// MARK: - Prep Tool Tile

/// Dense Today tile: icon, short title, one-line outcome. Replaces the old
/// one-word labels that did not say what each tool was for.
private struct PrepToolTile: View {
    let tool: PracticeToolKind
    var isHighlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: tool.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tool.color)
                Spacer(minLength: 0)
                if isHighlighted {
                    Circle()
                        .fill(tool.color)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }

            Text(tool.shortTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(tool.outcome)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.surfaceLift)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isHighlighted ? tool.color.opacity(0.45) : AppColors.cardStroke,
                            lineWidth: isHighlighted ? 1 : 0.5
                        )
                }
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.shortTitle). \(tool.outcome)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Interactive Prompt Card

struct InteractivePromptCard: View {
    let prompt: Prompt?
    @Binding var selectedDuration: RecordingDuration
    let onTap: () -> Void
    let onRefresh: () -> Void

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

                    SmallIconButton(icon: "arrow.clockwise", label: "Different prompt", action: onRefresh)
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

#Preview {
    NavigationStack {
        TodayView(
            onStartRecording: { _, _ in },
            onShowWheel: {},
            onShowWarmUps: {},
            onShowDrills: {},
            onShowConfidence: {},
            onShowCurriculum: {},
            onStartStoryPractice: { _ in }
        )
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self], inMemory: true)
}

