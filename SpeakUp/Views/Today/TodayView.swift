import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
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
    var onShowReadAloud: () -> Void
    var onShowWarmUps: () -> Void
    var onShowDrills: () -> Void
    var onShowConfidence: () -> Void
    var onShowCurriculum: () -> Void
    var onStartStoryPractice: ((Story, RecordingDuration) -> Void)?

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
            // Fire-and-forget: tops up the fresh-word pool while the user is
            // looking at Today, so tomorrow's workout has novel words ready.
            viewModel.warmVocabFreshWords(llmService: llmService)
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

    /// The card owns the whole brief now — topic, length, words, and Start —
    /// so the module is just the header plus that one object. The header takes
    /// `promptSectionTitle` because a story day is not a prompt day.
    private var sessionModule: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSectionHeader(promptSectionTitle, icon: "mic.fill")

            interactivePromptSection
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

    /// Today's words, built here because the handlers need the `modelContext`,
    /// then handed down as a value so both cards render the identical footer
    /// without four more init parameters each.
    private var sessionWords: SessionWordsRow {
        SessionWordsRow(
            workout: viewModel.vocabChallenge,
            bankWords: userSettings.first?.vocabWords ?? [],
            onSkip: { viewModel.skipVocabWord($0) },
            onAddToBank: { addSpotlightWordToBank($0) }
        )
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

    // MARK: - Start Footer

    /// The one hero action on Today, handed to whichever brief card renders so
    /// button and subject are the same object. Twin capsules and a segmented
    /// picker both failed here; read `docs/features/today-library.md`
    /// invariants 11–13 before changing it.
    private var sessionStartFooter: SessionStartFooter {
        SessionStartFooter(
            startHint: "Records a \(viewModel.selectedDuration.displayName) take on the topic above",
            freeHint: "Records a \(viewModel.selectedDuration.displayName) take with no topic",
            onStart: {
                Haptics.medium()
                if viewModel.storyPracticeEnabled, let story = viewModel.todaysStory {
                    onStartStoryPractice?(story, viewModel.selectedDuration)
                } else {
                    onStartRecording(viewModel.todaysPrompt, viewModel.selectedDuration)
                }
            },
            onFreeTalk: {
                Haptics.medium()
                onStartRecording(nil, viewModel.selectedDuration)
            }
        )
    }

    // MARK: - Interactive Prompt Section

    /// Story days practice a story, so the label above the card says which
    /// brief sits below — the card header alone didn't say whose take it was.
    private var promptSectionTitle: String {
        (viewModel.storyPracticeEnabled && viewModel.todaysStory != nil)
            ? "Today's story"
            : "Today's prompt"
    }

    @ViewBuilder
    private var interactivePromptSection: some View {
        if viewModel.storyPracticeEnabled, let story = viewModel.todaysStory {
            StoryPromptCard(
                story: story,
                selectedDuration: $viewModel.selectedDuration,
                words: sessionWords,
                footer: sessionStartFooter,
                onRefresh: { Task { await viewModel.refreshStory() } }
            )
        } else {
            InteractivePromptCard(
                prompt: viewModel.todaysPrompt,
                selectedDuration: $viewModel.selectedDuration,
                words: sessionWords,
                footer: sessionStartFooter,
                onRefresh: { Task { await viewModel.refreshPrompt() } }
            )
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
        case .readAloud: onShowReadAloud()
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

/// Today's topic: the brief and its action in one object. Header, prompt text,
/// words row, then the Start capsule as the footer — the button used to float
/// between this card and the tools strip, a third island that belonged to
/// neither neighbor.
///
/// Still not a control: no whole-card tap (the invisible gesture fought the
/// duration `Menu` for the same taps). The Start button is the only way to
/// begin.
///
/// Never line-limit the prompt: it clipped at four lines, which is the one
/// thing a prompt card must not do. The size comes from 14pt padding and 18pt
/// type instead.
struct InteractivePromptCard: View {
    let prompt: Prompt?
    @Binding var selectedDuration: RecordingDuration
    let words: SessionWordsRow
    let footer: SessionStartFooter
    let onRefresh: () -> Void

    private var redaction: RedactionReasons {
        prompt == nil ? .placeholder : []
    }

    var body: some View {
        GlassCard(padding: 14, elevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                // Everything *about* the take on one line, so the space under
                // the text belongs to the words alone.
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(prompt?.category ?? "Loading...")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .lineLimit(1)
                            // Shrinks before it truncates; "Current Events &
                            // Opinions" is the one that needs the headroom.
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(categoryColor)

                    Spacer(minLength: 4)

                    if let difficulty = prompt?.difficulty {
                        StatusPill.difficulty(difficulty)
                    }

                    DurationPill(selectedDuration: $selectedDuration)

                    // Reroll belongs beside the thing it rerolls; in a footer
                    // it cost a whole 44pt row. The negative gutter trims the
                    // layout box back to the header's height and edge, while
                    // the tap target itself stays 44pt.
                    SmallIconButton(icon: "arrow.clockwise", label: "Different prompt", action: onRefresh)
                        .padding(.trailing, -6)
                        .padding(.vertical, -6)
                }
                .redacted(reason: redaction)

                Text(prompt?.text ?? "Loading today's prompt...")
                    .font(.system(size: 18, weight: .semibold))
                    .lineSpacing(2)
                    .foregroundStyle(prompt == nil ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .redacted(reason: redaction)

                // Carries its own divider, so a day with no word workout ends
                // the brief at the prompt text.
                words
                    .redacted(reason: redaction)

                // The action lives with the brief it starts; loading state
                // never redacts it into looking broken.
                footer
                    .padding(.top, 4)
            }
            .accessibilityElement(children: .contain)
        }
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

// MARK: - Session Start Footer

/// The page's one hero action: a filled capsule and one quiet escape hatch.
/// Lives inside whichever brief card renders so the button can't drift away
/// from the thing it starts.
///
/// No prompt is not a mode you set and then confirm — it is a different way to
/// start, so it is a second start: quiet, unmistakably subordinate, one tap,
/// always visible. Give it a filled or stroked shape and it becomes the twin
/// capsule again; contrast only.
struct SessionStartFooter: View {
    var showFreeTalk = true
    let startHint: String
    let freeHint: String
    let onStart: () -> Void
    let onFreeTalk: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button {
                onStart()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Start Speaking")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.94))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
                }
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(startHint)

            if showFreeTalk {
                Button {
                    onFreeTalk()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Talk without a prompt")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    // 0.8 white on glass reads as a control only because it
                    // sits beside the capsule; alone it would be a caption.
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(freeHint)
            }
        }
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
            onShowReadAloud: {},
            onShowWarmUps: {},
            onShowDrills: {},
            onShowConfidence: {},
            onShowCurriculum: {},
            onStartStoryPractice: { _, _ in }
        )
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self, Achievement.self], inMemory: true)
}
