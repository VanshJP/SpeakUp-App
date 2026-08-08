import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpeechService.self) private var speechService
    @Environment(LLMService.self) private var llmService
    @Query private var userSettings: [UserSettings]

    @State private var selectedTab: AppTab = .today
    @State private var showingCountdown = false
    @State private var showingRecording = false
    @State private var showingPromptWheel = false
    @State private var showingGoals = false
    @State private var selectedRecordingId: String?
    @State private var pendingRecordingNavigation: String?
    @State private var showOnboarding = false
    @State private var achievementService = AchievementService()
    /// Owned here because the tour crosses tabs: it drives `selectedTab` and
    /// draws over the tab bar, neither of which a single tab's root can do.
    @State private var appTour = AppTourModel()

    // Feature sheets
    @State private var showingWarmUps = false
    @State private var showingDrills = false
    @State private var showingConfidenceTools = false
    @State private var showingBeforeAfter = false
    @State private var showingJournalExport = false
    @State private var showingAchievements = false
    @State private var showingStoryEditor = false
    @State private var settingsViewModel = SettingsViewModel()
    @State private var storiesViewModel = StoriesViewModel()
    @State private var paywall = PaywallCoordinator.shared

    // Story → Warm-Up / Drill routing
    @State private var warmUpStory: Story?
    @State private var drillStory: Story?

    // Recording parameters
    @State private var recordingPrompt: Prompt?
    @State private var recordingDuration: RecordingDuration = .sixty
    @State private var recordingGoalId: UUID?
    @State private var recordingStoryId: UUID?
    @State private var hasEvaluatedOnboarding = false

    private var countdownDuration: Int {
        userSettings.first?.countdownDuration ?? 15
    }

    private var countdownStyle: CountdownStyle {
        CountdownStyle(rawValue: userSettings.first?.countdownStyle ?? 0) ?? .countDown
    }

    private var timerEndBehavior: TimerEndBehavior {
        TimerEndBehavior(rawValue: userSettings.first?.timerEndBehavior ?? 0) ?? .saveAndStop
    }
    
    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            NavigationStack {
                TodayView(
                    onStartRecording: { prompt, duration in
                        recordingPrompt = prompt
                        recordingStoryId = nil
                        recordingDuration = duration
                        showingCountdown = true
                    },
                    onShowWheel: {
                        showingPromptWheel = true
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
                    onShowAchievements: {
                        showingAchievements = true
                    },
                    onStartStoryPractice: { story in
                        recordingPrompt = nil
                        recordingStoryId = story.id
                        recordingDuration = .sixty
                        showingCountdown = true
                    }
                )
            }
        case .library:
            NavigationStack {
                PracticeHubView(
                    onSelectPrompt: { prompt in
                        recordingPrompt = prompt
                        recordingStoryId = nil
                        recordingDuration = .sixty
                        showingCountdown = true
                    },
                    onStartStoryPractice: { story in
                        recordingPrompt = nil
                        recordingStoryId = story.id
                        recordingDuration = .sixty
                        showingCountdown = true
                    },
                    onSendToWarmUp: { story in
                        warmUpStory = story
                    },
                    onSendToDrill: { story in
                        drillStory = story
                    },
                    storiesViewModel: storiesViewModel
                )
            }
        case .history:
            NavigationStack {
                HistoryView(
                    onSelectRecording: { recordingId in
                        selectedRecordingId = recordingId
                    },
                    onShowBeforeAfter: {
                        showingBeforeAfter = true
                    },
                    onShowJournalExport: {
                        guard PaywallCoordinator.allow(.journalExport, trigger: "journal_export") else { return }
                        showingJournalExport = true
                    },
                    onShowGoals: {
                        showingGoals = true
                    }
                )
                .navigationDestination(item: $selectedRecordingId) { recordingId in
                    RecordingDetailView(
                        recordingId: recordingId,
                        onPracticeAgain: { prompt in
                            recordingPrompt = prompt
                            recordingStoryId = nil
                            recordingDuration = .sixty
                            showingCountdown = true
                        }
                    )
                    .onDisappear {
                        selectedRecordingId = nil
                    }
                }
            }
        case .learn:
            NavigationStack {
                CurriculumView()
            }
        case .settings:
            NavigationStack {
                SettingsView()
            }
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
            // Stop SwiftUI from auto-filling every tab symbol; we supply the
            // filled variant explicitly for the selected tab only, so inactive
            // tabs stay outline.
            .environment(\.symbolVariants, .none)
            .tint(.white)
            
            if showingCountdown {
                CountdownOverlayView(
                    prompt: recordingPrompt,
                    duration: recordingDuration,
                    countdownDuration: countdownDuration,
                    countdownStyle: countdownStyle,
                    selectedGoalId: $recordingGoalId,
                    onComplete: {
                        showingCountdown = false
                        showingRecording = true
                    },
                    onCancel: {
                        showingCountdown = false
                        // Clear session context so a later free/prompt practice
                        // doesn't inherit a stale story link or prompt.
                        recordingPrompt = nil
                        recordingStoryId = nil
                        recordingGoalId = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 1.05)))
                .zIndex(1)
            }

            // Above the tab bar on purpose: the tour points *at* the tabs, so
            // it has to be able to dim and outline them.
            if appTour.activeStep != nil {
                AppTourOverlay(tour: appTour, onFinish: finishTour)
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .environment(\.appTour, appTour)
        .animation(.easeInOut(duration: 0.3), value: showingCountdown)
        .motion(AppMotion.settle, value: appTour.activeStep != nil)
        .onChange(of: appTour.activeStep) { _, step in
            // The tour walks the tabs itself; the user's job is just to read.
            guard let step, selectedTab != step.tab else { return }
            selectedTab = step.tab
        }
        .fullScreenCover(isPresented: $showingRecording, onDismiss: {
            recordingStoryId = nil
            if let id = pendingRecordingNavigation {
                selectedRecordingId = id
                pendingRecordingNavigation = nil
            }
        }) {
            RecordingView(
                prompt: recordingPrompt,
                duration: recordingDuration,
                timerEndBehavior: timerEndBehavior,
                countdownStyle: countdownStyle,
                goalId: recordingGoalId,
                storyId: recordingStoryId,
                onComplete: { recording in
                    pendingRecordingNavigation = recording.id.uuidString
                    selectedTab = .history
                    showingRecording = false
                    Task {
                        await achievementService.checkAchievements(context: modelContext)
                    }
                },
                onCancel: {
                    showingRecording = false
                }
            )
        }
        .sheet(isPresented: $showingPromptWheel) {
            PromptWheelView(onSelectPrompt: { prompt in
                showingPromptWheel = false
                recordingPrompt = prompt
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingCountdown = true
                }
            })
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
        .sheet(isPresented: $showingAchievements) {
            NavigationStack {
                AchievementGalleryView()
            }
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
        // Full screen, not a sheet. The offer is a short flow through the user's
        // own progress before it asks for anything, and a card sheet both cuts
        // that short and reads as dismissible chrome.
        .fullScreenCover(item: $paywall.request) { request in
            PaywallView(request: request)
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        // Universal links arrive as a browsing activity rather than an open-URL
        // callback, but resolve to the same routes.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            handleDeepLink(url)
        }
        .overlay {
            if let achievement = achievementService.newlyUnlocked {
                AchievementUnlockedView(achievement: achievement) {
                    achievementService.clearNewlyUnlocked()
                    // Celebration just landed — the one moment a rating ask is
                    // welcome. The service decides whether to spend one.
                    if ReviewRequestService.shared.requestIfEligible(
                        .achievementUnlocked,
                        settings: userSettings.first
                    ) {
                        try? modelContext.save()
                    }
                }
                .zIndex(10)
            }
        }
        .onAppear {
            settingsViewModel.configure(with: modelContext)
            storiesViewModel.configure(with: modelContext)
            evaluateOnboardingIfNeeded()
        }
        .onChange(of: userSettings.first?.hasCompletedOnboarding) { _, _ in
            // @Query may not be hydrated on first onAppear — re-evaluate once it lands
            evaluateOnboardingIfNeeded()
        }
        .onChange(of: EntitlementStore.shared.isLifetime) { _, owned in
            // The deferred card promises held-back recordings score themselves
            // the moment Lifetime is unlocked. This is where that happens for a
            // purchase made in-app; the app-foreground pass covers the rest.
            guard owned else { return }
            RecordingProcessingCoordinator.shared.resumeDeferredRecordings(
                modelContext: modelContext,
                speechService: speechService,
                llmService: llmService
            )
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { result in
                // Everything that decides what the user sees next runs before
                // the cover comes down, so the destination is already in place
                // behind it. Routing *after* an await meant the last tap landed
                // the user on Today, then flipped the tab, then pushed a detail
                // view at them — the flow's final impression was a stutter.
                if let settings = userSettings.first {
                    applyOnboardingResult(result, to: settings)
                    try? modelContext.save()
                }
                OnboardingViewModel.clearResumeState()

                // The baseline was recorded inside onboarding, so there is no
                // post-dismissal handoff into an unguided recorder — that
                // handoff was the moment the old flow lost people.
                if let baselineID = result.baselineRecordingID, result.reviewBaselineOnFinish {
                    selectedTab = .history
                    selectedRecordingId = baselineID.uuidString
                }
                showOnboarding = false

                Task { @MainActor in
                    // None of the rest changes the screen, so none of it holds
                    // up the dismissal.
                    //
                    // Sync SettingsViewModel's cached word lists so vocab and
                    // dictionary words appear immediately without a restart.
                    await settingsViewModel.loadSettings()

                    if result.reminderEnabled {
                        let service = NotificationService()
                        await service.checkPermission()
                        await service.scheduleDailyReminder(
                            hour: result.reminderHour,
                            minute: result.reminderMinute
                        )
                    }

                    if result.baselineRecordingID != nil {
                        // The unlock overlay is full-screen confetti. Fired into
                        // the dismissal it lands on top of the reveal the user
                        // is still leaving, so it waits for the transition.
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
        // First pick stays the primary goal for anything that names one.
        settings.onboardingGoalRaw = (result.goals.first ?? .everydayConfidence).rawValue

        // Persist reminder preference + time so SettingsView reflects it.
        settings.dailyReminderEnabled = result.reminderEnabled
        settings.dailyReminderHour = result.reminderHour
        settings.dailyReminderMinute = result.reminderMinute

        // Prompt categories are intentionally NOT narrowed by the onboarding
        // goals. The goals *weight* which categories surface (`PromptMix`),
        // while every category stays enabled so the full pool remains
        // reachable. Narrowing belongs to the user, via PromptSettingsView,
        // and that gate beats the onboarding weighting when the two disagree.

        // Voice calibration captured during onboarding. Matches
        // `SettingsViewModel.saveCalibrationProfile`: a deliberate "this is my
        // voice" reading earns full blend trust rather than starting at one
        // sample, so speaker separation works on the very first conversation.
        if let profile = result.voiceProfile {
            settings.voiceProfileF0Hz = profile.f0Hz
            settings.voiceProfileEnergyDb = profile.energyDb
            settings.voiceProfileSampleCount = max(settings.voiceProfileSampleCount, 3)
            settings.voiceProfileLastUpdated = Date()
        }

        for word in result.vocabWords {
            settings.addVocabWord(word)
        }
        for word in result.dictionaryWords {
            settings.addDictationBiasWord(word)
        }

        // If recordings already exist when onboarding completes (re-onboarding,
        // app upgrade, or testing), suppress the first-recording setup sheet —
        // the user clearly knows how to record. The baseline recorded inside
        // onboarding doesn't count as "already knows": the sheet firing after
        // it is exactly the deferred-setup moment it exists for.
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

    // MARK: - Onboarding

    /// Show onboarding only for confirmed first-launch users. Evaluating before
    /// `@Query` hydrates would flash onboarding over a returning user's home.
    private func evaluateOnboardingIfNeeded() {
        guard !hasEvaluatedOnboarding, let settings = userSettings.first else { return }
        hasEvaluatedOnboarding = true
        if !settings.hasCompletedOnboarding {
            showOnboarding = true
        }
    }

    // MARK: - Deep Links

    private func handleDeepLink(_ url: URL) {
        // A campaign link arrives as https on our own domain; normalise it into
        // the custom-scheme form so both entry points route identically.
        let url = UniversalLink.route(from: url) ?? url
        guard url.scheme == "speakup" else { return }

        // Any link can carry campaign parameters, so attribution is captured
        // before routing rather than on one dedicated host.
        AttributionStore.shared.capture(from: url)

        switch url.host {
        case "open":
            // Attribution-only entry point for campaign links that should land
            // the user on the home screen.
            selectedTab = .today

        case "record":
            // Fresh session context — never inherit a story/goal/prompt from
            // whatever was recorded last.
            recordingPrompt = nil
            recordingStoryId = nil
            recordingGoalId = nil
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let promptId = components.queryItems?.first(where: { $0.name == "prompt" })?.value
            {
                let descriptor = FetchDescriptor<Prompt>()
                if let prompts = try? modelContext.fetch(descriptor) {
                    recordingPrompt = prompts.first { $0.id == promptId }
                }
            }
            showingCountdown = true

        case "story":
            selectedTab = .library
            if url.pathComponents.contains("new") {
                showingStoryEditor = true
            }

        default:
            break
        }
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

    /// Outline variant — shown when the tab is not selected.
    var icon: String {
        switch self {
        case .today: return "mic"
        case .library: return "books.vertical"
        case .history: return "clock"
        case .learn: return "book"
        case .settings: return "gearshape"
        }
    }

    /// Filled variant — shown when the tab is selected.
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
