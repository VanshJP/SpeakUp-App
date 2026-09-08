import SwiftData
import SwiftUI

/// App shell: 5 tabs + global sheets + deep links. Tab roots in `tabRoot(for:)`.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpeechService.self) private var speechService
    @Environment(LLMService.self) private var llmService
    @Query private var userSettings: [UserSettings]

    @State private var selectedTab: AppTab = .today
    @State private var showingCountdown = false
    @State private var showingRecording = false
    @State private var showingReadAloud = false
    @State private var showingGoals = false
    @State private var selectedRecordingId: String?
    @State private var pendingRecordingNavigation: String?
    @State private var freshResultRecordingId: String?
    @State private var showOnboarding = false
    @State private var achievementService = AchievementService()
    @State private var coachMoments = CoachMomentService.shared
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
    @State private var recordingGoalId: UUID?
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
    
    private func tabContent(for tab: AppTab) -> some View {
        NavigationStack {
            tabRoot(for: tab)
                .background { AppBackground() }
        }
    }

    @ViewBuilder
    private func tabRoot(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayView(
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
                }
            )
        case .library:
            PracticeHubView(
                onSelectPrompt: { prompt in
                    recordingPrompt = prompt
                    recordingStoryId = nil
                    recordingDuration = .sixty
                    adoptChallengeIfMatching(prompt)
                    showingCountdown = true
                },
                onStartStoryPractice: { story in
                    recordingPrompt = nil
                    recordingStoryId = story.id
                    recordingDuration = .sixty
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
                onStartPractice: {
                    selectedTab = .today
                }
            )
            .navigationDestination(item: $selectedRecordingId) { recordingId in
                RecordingDetailView(
                    recordingId: recordingId,
                    allowsCoachMoments: freshResultRecordingId == recordingId,
                    onPracticeAgain: { prompt in
                        recordingPrompt = prompt
                        recordingStoryId = nil
                        recordingDuration = .sixty
                        recordingChallenge = nil
                        showingCountdown = true
                    },
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
            
            if showingCountdown {
                CountdownOverlayView(
                    prompt: recordingPrompt,
                    duration: recordingDuration,
                    countdownDuration: countdownDuration,
                    countdownStyle: countdownStyle,
                    look: countdownLook,
                    backdrop: recordingBackdrop,
                    selectedGoalId: $recordingGoalId,
                    challenge: recordingChallenge,
                    onComplete: {
                        showingCountdown = false
                        showingRecording = true
                    },
                    onCancel: {
                        showingCountdown = false
                        recordingPrompt = nil
                        recordingStoryId = nil
                        recordingGoalId = nil
                        recordingChallenge = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 1.05)))
                .zIndex(1)
                .allowsHitTesting(true)
            }

            if appTour.activeStep != nil {
                AppTourOverlay(tour: appTour, onFinish: finishTour)
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .environment(\.appTour, appTour)
        .environment(\.glassAppearance, glassAppearance)
        .environment(\.appCanvas, appCanvas)
        .animation(.easeInOut(duration: 0.3), value: showingCountdown)
        .motion(AppMotion.settle, value: appTour.activeStep != nil)
        .onChange(of: appTour.activeStep) { _, step in
            guard let step, selectedTab != step.tab else { return }
            selectedTab = step.tab
        }
        .fullScreenCover(isPresented: $showingRecording, onDismiss: {
            recordingStoryId = nil
            recordingChallenge = nil
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
                sessionSource: recordingChallenge != nil ? SharedPromptLink.shareSource : nil,
                onSavedAndClosed: { recording in
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
                    pendingRecordingNavigation = recording.id.uuidString
                    freshResultRecordingId = recording.id.uuidString
                    selectedTab = .history
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
            evaluateOnboardingIfNeeded()
        }
        .onChange(of: userSettings.first?.hasCompletedOnboarding) { _, _ in
            // @Query may not be hydrated on first onAppear — re-evaluate once it lands
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

                    if result.reminderEnabled {
                        let service = NotificationService()
                        await service.checkPermission()
                        await service.scheduleDailyReminder(
                            hour: result.reminderHour,
                            minute: result.reminderMinute
                        )
                    }

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

        // Persist reminder preference + time so SettingsView reflects it.
        settings.dailyReminderEnabled = result.reminderEnabled
        settings.dailyReminderHour = result.reminderHour
        settings.dailyReminderMinute = result.reminderMinute


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

    // MARK: - Coach notes

    private func performCoachMomentAction(_ action: CoachMomentAction) {
        switch action {
        case .openConfidence:
            showingConfidenceTools = true
        case .practiceAgain:
            recordingPrompt = nil
            recordingStoryId = nil
            recordingDuration = .sixty
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

    private func startRecording(from url: URL) {
        guard !showOnboarding, !showingRecording, !showingCountdown else { return }

        recordingPrompt = nil
        recordingStoryId = nil
        recordingGoalId = nil
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
