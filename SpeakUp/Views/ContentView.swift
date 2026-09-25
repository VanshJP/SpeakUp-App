import SwiftData
import SwiftUI

/// App shell: 5 tabs + global sheets + deep links. Tab roots in `tabRoot(for:)`.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    @State private var selectedTab: AppTab = .today
    @State private var showingCountdown = false
    @State private var showingRecording = false
    /// One cover hosts the countdown and then the take, so the session zooms
    /// out of the button that started it and the canvas never slides.
    @Namespace private var sessionZoom
    @State private var sessionZoomSource: String?
    @State private var showingReadAloud = false
    @State private var showingGoals = false
    @State private var selectedRecordingId: String?
    @State private var pendingRecordingNavigation: String?
    @State private var freshResultRecordingId: String?
    @State private var showOnboarding = false
    @State private var achievementService = AchievementService.shared
    @State private var coachMoments = CoachMomentService.shared
    @State private var routine = PracticeRoutineService.shared
    /// Owned here because the tour crosses tabs: it drives `selectedTab` and
    /// draws over the tab bar, neither of which a single tab's root can do.
    @State private var appTour = AppTourModel()

    @State private var showingWarmUps = false
    @State private var showingDrills = false
    @State private var showingConfidenceTools = false
    @State private var showingBeforeAfter = false
    @State private var showingJournalExport = false
    @State private var showingStoryEditor = false
    @State private var settingsViewModel = SettingsViewModel()
    @State private var storiesViewModel = StoriesViewModel()

    @State private var warmUpStory: Story?
    @State private var drillStory: Story?

    @State private var recordingPrompt: Prompt?
    @State private var recordingDuration: RecordingDuration = .sixty
    @State private var recordingStoryId: UUID?
    @State private var recordingChallenge: SharedChallenge?
    @State private var hasEvaluatedOnboarding = false

    private var countdownDuration: Int {
        userSettings.first?.countdownDuration ?? 15
    }

    private var countdownStyle: CountdownStyle {
        CountdownStyle(rawValue: userSettings.first?.countdownStyle ?? 0) ?? .countDown
    }

    private var countdownLook: TimerLook {
        TimerLook(rawValue: userSettings.first?.countdownLook ?? 0) ?? .ring
    }

    private var recordingBackdrop: RecordingBackdrop {
        RecordingBackdrop(rawValue: userSettings.first?.countdownBackdrop ?? 0) ?? .base
    }

    private var glassAppearance: GlassAppearance {
        GlassAppearance(rawValue: userSettings.first?.glassAppearance ?? 0) ?? .light
    }

    private var appCanvas: AppCanvas {
        AppCanvas(rawValue: userSettings.first?.appCanvas ?? 0) ?? .classic
    }

    private var timerEndBehavior: TimerEndBehavior {
        TimerEndBehavior(rawValue: userSettings.first?.timerEndBehavior ?? 0) ?? .saveAndStop
    }

    /// The take length from Settings → Session Defaults, for starts from a
    /// surface with no length control of its own (a Library or wheel prompt,
    /// a coach note, a deep link). Today passes its pill; a repeat passes the
    /// original take's length.
    private var defaultTakeDuration: RecordingDuration {
        RecordingDuration(rawValue: userSettings.first?.defaultDuration ?? 60) ?? .sixty
    }

    /// What the prepare countdown names when there is no prompt card to show.
    /// A story or free-talk take used to count down over a bare dial. Only
    /// while the countdown is up: Cancel clears the prompt and story as the
    /// cover animates out, which would otherwise flash "Free talk" on the way.
    private var countdownPrepTitle: String? {
        guard showingCountdown, recordingPrompt == nil else { return nil }
        guard let storyId = recordingStoryId else { return "Free talk" }
        let title = storiesViewModel.stories.first { $0.id == storyId }?.title ?? ""
        return title.isEmpty ? "Your story" : title
    }

    private var countdownPrepSubtitle: String? {
        guard showingCountdown, recordingPrompt == nil else { return nil }
        let length = recordingDuration.displayName
        return recordingStoryId == nil ? "Any topic · \(length)" : "Story · \(length)"
    }
    
    private func tabContent(for tab: AppTab) -> some View {
        NavigationStack {
            tabRoot(for: tab)
                .background { AppBackground() }
        }
        // Inside the tab, whose bottom safe area ends at the top of the tab
        // bar. As a sibling of the `TabView` the bar sat in the shell's safe
        // area, which ends at the home indicator - 8pt above that is inside
        // the floating tab bar, so the bar covered the tabs it should sit on.
        .safeAreaBar(edge: .bottom, spacing: 0) { routineHandoffOverlay }
    }

    @ViewBuilder
    private func tabRoot(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayView(
                isActiveTab: selectedTab == .today && !showOnboarding,
                onStartRecording: { prompt, duration in
                    recordingPrompt = prompt
                    recordingStoryId = nil
                    recordingDuration = duration
                    adoptChallengeIfMatching(prompt)
                    showingCountdown = true
                },
                onShowReadAloud: {
                    showingReadAloud = true
                },
                onShowWarmUps: {
                    showingWarmUps = true
                },
                onShowDrills: {
                    showingDrills = true
                },
                onShowConfidence: {
                    showingConfidenceTools = true
                },
                onShowCurriculum: {
                    selectedTab = .learn
                },
                onStartStoryPractice: { story, duration in
                    recordingPrompt = nil
                    recordingStoryId = story.id
                    recordingDuration = duration
                    recordingChallenge = nil
                    showingCountdown = true
                },
                sessionZoomSource: $sessionZoomSource,
                zoomNamespace: sessionZoom
            )
        case .library:
            PracticeHubView(
                onSelectPrompt: { prompt in
                    recordingPrompt = prompt
                    recordingStoryId = nil
                    recordingDuration = defaultTakeDuration
                    adoptChallengeIfMatching(prompt)
                    showingCountdown = true
                },
                onStartStoryPractice: { story, duration in
                    recordingPrompt = nil
                    recordingStoryId = story.id
                    recordingDuration = duration
                    recordingChallenge = nil
                    showingCountdown = true
                },
                onSendToWarmUp: { story in
                    warmUpStory = story
                },
                onSendToDrill: { story in
                    drillStory = story
                },
                onShowBeforeAfter: {
                    showingBeforeAfter = true
                },
                onShowJournalExport: {
                    showingJournalExport = true
                },
                onShowGoals: {
                    showingGoals = true
                },
                storiesViewModel: storiesViewModel
            )
        case .history:
            HistoryView(
                onSelectRecording: { recordingId in
                    selectedRecordingId = recordingId
                },
                onShowBeforeAfter: {
                    showingBeforeAfter = true
                },
                onShowJournalExport: {
                    showingJournalExport = true
                },
                onShowGoals: {
                    showingGoals = true
                },
                onShowToday: {
                    selectedTab = .today
                },
                onPracticeScenario: { scenario in
                    startScenarioPractice(scenario)
                }
            )
            .navigationDestination(item: $selectedRecordingId) { recordingId in
                RecordingDetailView(
                    recordingId: recordingId,
                    source: freshResultRecordingId == recordingId ? .postSession : .history,
                    onPracticeAgain: { recording in
                        recordingPrompt = recording.storyId == nil ? recording.prompt : nil
                        recordingStoryId = recording.storyId
                        recordingDuration = RecordingDuration(rawValue: recording.targetDuration) ?? .sixty
                        recordingChallenge = nil
                        showingCountdown = true
                    },
                    allowsCoachMoments: freshResultRecordingId == recordingId,
                    onShowConfidence: {
                        showingConfidenceTools = true
                    }
                )
                .restoresNavigationBar()
                .onDisappear {
                    if freshResultRecordingId == recordingId {
                        freshResultRecordingId = nil
                    }
                    selectedRecordingId = nil
                }
            }
        case .learn:
            CurriculumView()
        case .settings:
            SettingsView()
        }
    }
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    Tab(tab.title, systemImage: tab == selectedTab ? tab.selectedIcon : tab.icon, value: tab) {
                        tabContent(for: tab)
                    }
                }
            }
            .environment(\.symbolVariants, .none)
            .tint(.white)
            

            if appTour.activeStep != nil {
                AppTourOverlay(tour: appTour, onFinish: finishTour)
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .environment(\.appTour, appTour)
        .environment(\.glassAppearance, glassAppearance)
        .environment(\.appCanvas, appCanvas)
        .motion(AppMotion.settle, value: appTour.activeStep != nil)
        .onChange(of: routine.pendingStep) { _, step in
            guard step != nil else { return }
            openPendingRoutineStep()
        }
        .onChange(of: appTour.activeStep) { _, step in
            guard let step, selectedTab != step.tab else { return }
            selectedTab = step.tab
        }
        .fullScreenCover(isPresented: isShowingSession, onDismiss: endSession) {
            sessionCover
        }
        .sheet(isPresented: $showingReadAloud) {
            ReadAloudSelectionView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingGoals) {
            GoalsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingWarmUps) {
            WarmUpListView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $warmUpStory) { story in
            WarmUpListView(sourceStory: story)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingDrills) {
            DrillSelectionView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $drillStory) { story in
            DrillSelectionView(sourceStory: story)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingConfidenceTools) {
            ConfidenceToolsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingBeforeAfter) {
            BeforeAfterReplayView()
        }
        .sheet(isPresented: $showingJournalExport) {
            NavigationStack {
                JournalExportView()
            }
        }
        .sheet(isPresented: $showingStoryEditor) {
            NavigationStack {
                StoryEditorView(viewModel: storiesViewModel)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            handleDeepLink(url)
        }
        .overlay {
            if let achievement = achievementService.newlyUnlocked {
                AchievementUnlockedView(achievement: achievement) {
                    achievementService.clearNewlyUnlocked()
                }
                .zIndex(10)
            } else if let moment = coachMoments.pendingOverlay {
                CoachMomentOverlay(
                    moment: moment,
                    onAccept: {
                        let action = moment.action
                        coachMoments.consume(moment, context: modelContext)
                        performCoachMomentAction(action)
                    },
                    onDismiss: {
                        coachMoments.dismiss(moment, context: modelContext)
                    }
                )
                .zIndex(10)
            }
        }
        .onAppear {
            settingsViewModel.configure(with: modelContext)
            storiesViewModel.configure(with: modelContext)
            routine.configure(with: modelContext)
            evaluateOnboardingIfNeeded()
        }
        .onChange(of: userSettings.first?.hasCompletedOnboarding) { _, _ in
            // @Query may not be hydrated on first onAppear - re-evaluate once it lands
            evaluateOnboardingIfNeeded()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { result in
                if let settings = userSettings.first {
                    applyOnboardingResult(result, to: settings)
                    try? modelContext.save()
                }
                OnboardingViewModel.clearResumeState()

                if let baselineID = result.baselineRecordingID, result.reviewBaselineOnFinish {
                    selectedTab = .history
                    selectedRecordingId = baselineID.uuidString
                }
                showOnboarding = false

                Task { @MainActor in
                    await settingsViewModel.loadSettings()

                    if result.baselineRecordingID != nil {
                        try? await Task.sleep(for: .milliseconds(700))
                        await achievementService.checkAchievements(context: modelContext)
                    }
                }
            }
        }
    }

    // MARK: - Onboarding

    /// Apply user picks captured during onboarding to the persisted
    /// `UserSettings` row. De-duplicates word lists case-insensitively
    /// against existing entries so re-running onboarding never produces
    /// duplicate vocab/dictionary chips.
    private func applyOnboardingResult(_ result: OnboardingResult, to settings: UserSettings) {
        settings.hasCompletedOnboarding = true
        settings.speakerLevel = result.speakerLevel.rawValue
        settings.userName = result.userName
        settings.onboardingGoalsRaw = result.goals.map(\.rawValue)
        settings.onboardingGoalRaw = (result.goals.first ?? .everydayConfidence).rawValue

        for word in result.vocabWords {
            settings.addVocabWord(word)
        }
        for word in result.dictionaryWords {
            settings.addDictationBiasWord(word)
        }

        if !settings.hasShownFirstRecordingSetup {
            let count = (try? modelContext.fetchCount(FetchDescriptor<Recording>())) ?? 0
            let baselineCount = result.baselineRecordingID != nil ? 1 : 0
            if count > baselineCount { settings.hasShownFirstRecordingSetup = true }
        }
    }

    // MARK: - App Tour

    /// Ends the walkthrough. Marked seen either way: a user who skipped it has
    /// told us what they think of it, and re-showing would be nagging. Landing
    /// back on Today matters because the last stop is Settings, and leaving
    /// someone parked there is the opposite of "you now know where things are".
    private func finishTour(completed: Bool) {
        appTour.activeStep = nil
        selectedTab = .today
        if let settings = userSettings.first {
            settings.hasSeenAppTour = true
            try? modelContext.save()
        }
        AnalyticsService.shared.log(
            .onboardingStep("app_tour", action: completed ? "complete" : "skip")
        )
    }

    // MARK: - Routine

    /// Sits on the tab bar rather than inside the screen that finished,
    /// because that screen is a sheet on its way out - set while the sheet is
    /// still up, the bar is simply already there when it goes. Each tab's
    /// `safeAreaBar` hosts it (`tabContent(for:)`), so it rides above the tab
    /// bar and lifts the scroll content clear of itself. The tour outranks
    /// it: a spotlight with a bar floating over it teaches nothing.
    ///
    /// Split out of `body` deliberately; the shell is already near the
    /// type-checker's budget for one expression (gotchas §15).
    private var routineHandoffOverlay: some View {
        VStack(spacing: 0) {
            if let handoff = routine.handoff, appTour.activeStep == nil {
                RoutineHandoffBar(
                    handoff: handoff,
                    onTake: {
                        routine.advance()
                        openPendingRoutineStep()
                    },
                    onDismiss: routine.dismissHandoff
                )
                .padding(.horizontal, AppLayout.pageHorizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .motion(AppMotion.settle, value: routine.handoff)
    }

    /// Opens whatever the routine is asking for. `.session` is deliberately left
    /// set: Today owns the day's prompt and the duration pill, so it finishes
    /// that case itself once the tab switch lands. Everything else opens here,
    /// through the same sheets the Today tiles use.
    private func openPendingRoutineStep() {
        guard let step = routine.pendingStep else { return }
        switch step {
        case .calm:
            routine.clearPendingStep()
            showingConfidenceTools = true
        case .warmUp:
            routine.clearPendingStep()
            showingWarmUps = true
        case .drill:
            routine.clearPendingStep()
            showingDrills = true
        case .readAloud:
            routine.clearPendingStep()
            showingReadAloud = true
        case .review:
            routine.clearPendingStep()
            openLatestTake()
        case .session:
            selectedTab = .today
        }
    }

    /// "Read the score" means the take just recorded, so it opens that take's
    /// breakdown rather than the History list it would have to be found in.
    private func openLatestTake() {
        var latest = FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latest.fetchLimit = 1
        selectedTab = .history
        if let recording = try? modelContext.fetch(latest).first {
            selectedRecordingId = recording.id.uuidString
        }
    }

    // MARK: - Coach notes

    private func performCoachMomentAction(_ action: CoachMomentAction) {
        switch action {
        case .openConfidence:
            showingConfidenceTools = true
        case .practiceAgain:
            recordingPrompt = nil
            recordingStoryId = nil
            recordingDuration = defaultTakeDuration
            recordingChallenge = nil
            showingCountdown = true
        case .close:
            break
        }
    }

    // MARK: - Onboarding

    private func evaluateOnboardingIfNeeded() {
        guard !hasEvaluatedOnboarding, let settings = userSettings.first else { return }
        hasEvaluatedOnboarding = true
        if !settings.hasCompletedOnboarding {
            showOnboarding = true
        }
    }

    // MARK: - Session cover

    private var isShowingSession: Binding<Bool> {
        Binding(
            get: { showingCountdown || showingRecording },
            set: { presented in
                guard !presented else { return }
                showingCountdown = false
                showingRecording = false
            }
        )
    }

    /// Closes out the take the cover just dismissed. This runs *after* the
    /// dismissal animation, which is the only safe moment to open the take's
    /// destination: `selectedTab` has to stay on Today for the whole zoom-out
    /// or the button the cover is zooming back into leaves the screen
    /// mid-animation. `recordingSession.onComplete` therefore only stages the
    /// destination in `pendingRecordingNavigation` and leaves the rest here.
    ///
    /// A tap that starts the next session while this one is still animating
    /// out (gotcha #27) has already flipped the flags back on by the time this
    /// fires, so the screen now belongs to that session, not this one:
    /// clearing would wipe its zoom source, and the staged destination would
    /// fire underneath it when *its* cover dismisses. Drop the abandoned
    /// take's destination and leave everything the new session owns alone.
    private func endSession() {
        guard !showingCountdown, !showingRecording else {
            pendingRecordingNavigation = nil
            freshResultRecordingId = nil
            return
        }

        recordingStoryId = nil
        recordingChallenge = nil
        sessionZoomSource = nil

        guard let id = pendingRecordingNavigation else { return }
        selectedTab = .history
        selectedRecordingId = id
        pendingRecordingNavigation = nil
    }

    /// Countdown, then the take, in one presentation. The countdown used to be
    /// an overlay on the tab shell and the take a cover sliding up over it —
    /// two entrances for one act. Now the cover zooms out of the button that
    /// started it (when the launcher named one) and the countdown crossfades
    /// into the recorder on the same canvas.
    @ViewBuilder
    private var sessionCover: some View {
        if let sessionZoomSource {
            sessionStage
                .navigationTransition(.zoom(sourceID: sessionZoomSource, in: sessionZoom))
        } else {
            sessionStage
        }
    }

    private var sessionStage: some View {
        ZStack {
            if showingRecording {
                recordingSession
                    .transition(.opacity)
            } else {
                CountdownOverlayView(
                    prompt: recordingPrompt,
                    duration: recordingDuration,
                    countdownDuration: countdownDuration,
                    countdownStyle: countdownStyle,
                    look: countdownLook,
                    backdrop: recordingBackdrop,
                    prepTitle: countdownPrepTitle,
                    prepSubtitle: countdownPrepSubtitle,
                    challenge: recordingChallenge,
                    onComplete: {
                        showingCountdown = false
                        showingRecording = true
                    },
                    onCancel: {
                        showingCountdown = false
                        recordingPrompt = nil
                        recordingStoryId = nil
                        recordingChallenge = nil
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(AppMotion.settle, value: showingRecording)
        // A zoom presentation can be dragged or pinched away. Mid-take that
        // would discard the recording, so the only exits are the ones on screen.
        .interactiveDismissDisabled()
    }

    private var recordingSession: some View {
        RecordingView(
            prompt: recordingPrompt,
            duration: recordingDuration,
            timerEndBehavior: timerEndBehavior,
            countdownStyle: countdownStyle,
            storyId: recordingStoryId,
            sessionSource: recordingChallenge != nil ? SharedPromptLink.shareSource : nil,
            onSavedAndClosed: { recording in
                routine.complete(.session)
                Task {
                    while RecordingProcessingCoordinator.shared.isProcessing(recording.id) {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                    }
                    await achievementService.checkAchievements(context: modelContext)
                    // Save & close means no replacement interruption. Keep
                    // unlock state, but do not surface an overlay now.
                    achievementService.clearNewlyUnlocked()
                }
            },
            onComplete: { recording in
                routine.complete(.session)
                pendingRecordingNavigation = recording.id.uuidString
                freshResultRecordingId = recording.id.uuidString
                // The tab switch waits for the cover's dismissal to finish.
                // See `endSession()`.
                showingRecording = false
                SharedChallengeStore.shared.dismiss()
                Task {
                    await achievementService.checkAchievements(context: modelContext)
                }
            },
            onCancel: {
                showingRecording = false
            }
        )
    }

    // MARK: - Deep Links

    private func handleDeepLink(_ url: URL) {
        let url = UniversalLink.route(from: url) ?? url
        guard url.scheme == "speakup" else { return }

        AttributionStore.shared.capture(from: url)

        switch url.host {
        case "open":
            selectedTab = .today

        case "record":
            startRecording(from: url)

        case "story":
            guard !showOnboarding, !showingRecording, !showingCountdown else { return }
            selectedTab = .library
            if url.pathComponents.contains("new") {
                showingStoryEditor = true
            }

        default:
            break
        }
    }

    /// History › Progress › "Where to improve": a take on a prompt from that
    /// situation, preferring one not yet answered. A scenario with no prompts
    /// (every category of it switched off) opens the Library instead of
    /// doing nothing.
    private func startScenarioPractice(_ scenario: PracticeScenario) {
        let prompts = ((try? modelContext.fetch(FetchDescriptor<Prompt>())) ?? []).filter {
            ScenarioReadinessEngine.scenario(forRawCategory: $0.category) == scenario
        }
        let answered = Set(((try? modelContext.fetch(FetchDescriptor<Recording>())) ?? []).compactMap { $0.prompt?.id })
        guard let prompt = prompts.filter({ !answered.contains($0.id) }).randomElement() ?? prompts.randomElement() else {
            selectedTab = .library
            return
        }
        recordingPrompt = prompt
        recordingStoryId = nil
        recordingDuration = defaultTakeDuration
        adoptChallengeIfMatching(prompt)
        showingCountdown = true
    }

    private func startRecording(from url: URL) {
        guard !showOnboarding, !showingRecording, !showingCountdown else { return }

        recordingPrompt = nil
        recordingStoryId = nil
        recordingDuration = defaultTakeDuration
        recordingChallenge = nil

        let payload = SharedPromptLink.payload(from: url) ?? SharedPromptPayload()
        if let prompt = SharedPromptResolver.resolve(payload, in: modelContext)
            ?? payload.promptID.flatMap({ SharedPromptResolver.prompt(id: $0, in: modelContext) }) {
            recordingPrompt = prompt
            if payload.isShareChallenge {
                let challenge = SharedChallenge(
                    promptID: prompt.id,
                    promptText: prompt.text,
                    category: prompt.category,
                    difficulty: prompt.difficulty.rawValue,
                    beatScore: payload.beatScore
                )
                recordingChallenge = challenge
                SharedChallengeStore.shared.remember(challenge)
                AnalyticsService.shared.log(.sharedPromptOpened())
            }
        }

        showingCountdown = true
    }

    private func adoptChallengeIfMatching(_ prompt: Prompt?) {
        guard let prompt, let pending = SharedChallengeStore.shared.pending,
              pending.promptID == prompt.id else {
            recordingChallenge = nil
            return
        }
        recordingChallenge = pending
    }
}

// MARK: - App Tab Enum

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case library
    case history
    case learn
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .library: return "Library"
        case .history: return "History"
        case .learn: return "Learn"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .today: return "mic"
        case .library: return "books.vertical"
        case .history: return "clock"
        case .learn: return "book"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .today: return "mic.fill"
        case .library: return "books.vertical.fill"
        case .history: return "clock.fill"
        case .learn: return "book.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
        .environment(SpeechService())
        .environment(AudioService())
        .environment(LLMService())
}
