import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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
        }
        .animation(.easeInOut(duration: 0.3), value: showingCountdown)
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
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .overlay {
            if let achievement = achievementService.newlyUnlocked {
                AchievementUnlockedView(achievement: achievement) {
                    achievementService.clearNewlyUnlocked()
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
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { result in
                Task { @MainActor in
                    if let settings = userSettings.first {
                        applyOnboardingResult(result, to: settings)
                        try? modelContext.save()
                    }
                    OnboardingViewModel.clearResumeState()
                    // Sync SettingsViewModel's cached word lists so vocab and
                    // dictionary words appear immediately without a restart.
                    await settingsViewModel.loadSettings()
                    showOnboarding = false

                    if result.reminderEnabled {
                        let service = NotificationService()
                        await service.checkPermission()
                        await service.scheduleDailyReminder(
                            hour: result.reminderHour,
                            minute: result.reminderMinute
                        )
                    }

                    if result.launchFirstRecording {
                        try? await Task.sleep(for: .milliseconds(500))
                        recordingPrompt = nil
                        recordingStoryId = nil
                        recordingDuration = .sixty
                        showingCountdown = true
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
        settings.onboardingGoalRaw = result.goal.rawValue

        // Persist reminder preference + time so SettingsView reflects it.
        settings.dailyReminderEnabled = result.reminderEnabled
        settings.dailyReminderHour = result.reminderHour
        settings.dailyReminderMinute = result.reminderMinute

        // Prompt categories are intentionally NOT narrowed by the onboarding
        // goal — the goal is stored for reference but all categories stay
        // enabled so the user sees the full prompt pool. Category selection is
        // user-driven via PromptSettingsView.

        for word in result.vocabWords {
            settings.addVocabWord(word)
        }
        for word in result.dictionaryWords {
            settings.addDictationBiasWord(word)
        }

        // If recordings already exist when onboarding completes (re-onboarding,
        // app upgrade, or testing), suppress the first-recording setup sheet —
        // the user clearly knows how to record. Without this, the sheet fires
        // on TodayView appearance whenever count >= 1 and the flag is false.
        if !settings.hasShownFirstRecordingSetup {
            let count = (try? modelContext.fetchCount(FetchDescriptor<Recording>())) ?? 0
            if count > 0 { settings.hasShownFirstRecordingSetup = true }
        }
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
        guard url.scheme == "speakup" else { return }

        switch url.host {
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
}
