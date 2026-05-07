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
    @State private var socialChallengeService = SocialChallengeService()
    @State private var showingChallengeAccept = false

    // Feature sheets
    @State private var showingWarmUps = false
    @State private var showingDrills = false
    @State private var showingConfidenceTools = false
    @State private var showingBeforeAfter = false
    @State private var showingJournalExport = false
    @State private var showingAchievements = false
    @State private var showingWordBank = false
    @State private var showingReadAloud = false
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
                    onShowWordBank: {
                        showingWordBank = true
                    },
                    onShowReadAloud: {
                        showingReadAloud = true
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
                    RecordingDetailView(recordingId: recordingId)
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
                    Tab(tab.title, systemImage: tab.icon, value: tab) {
                        tabContent(for: tab)
                    }
                }
            }
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
        .sheet(isPresented: $showingWordBank) {
            NavigationStack {
                WordBankView(viewModel: settingsViewModel)
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
        .sheet(isPresented: $showingReadAloud) {
            ReadAloudSelectionView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
            if userSettings.first?.hasCompletedOnboarding != true {
                showOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $showingChallengeAccept) {
            if let challenge = socialChallengeService.incomingChallenge {
                ChallengeAcceptView(
                    challenge: challenge,
                    onAccept: {
                        showingChallengeAccept = false
                        let descriptor = FetchDescriptor<Prompt>()
                        if let prompts = try? modelContext.fetch(descriptor) {
                            recordingPrompt = prompts.first { $0.id == challenge.promptId }
                        }
                        socialChallengeService.clearIncoming()
                        showingCountdown = true
                    },
                    onDismiss: {
                        showingChallengeAccept = false
                        socialChallengeService.clearIncoming()
                    }
                )
            }
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

        // Narrow daily prompt categories to the goal's recommended mix on
        // first run. We only override if the user hasn't already customised
        // the list (i.e. it still equals the full default set).
        let allCategories = Set(PromptCategory.allCases.map { $0.rawValue })
        let currentCategories = Set(settings.enabledPromptCategories)
        if currentCategories == allCategories || currentCategories.isEmpty {
            let goalCategories = result.goal.defaultPromptCategoryNames
            if !goalCategories.isEmpty {
                settings.enabledPromptCategories = goalCategories
            }
        }

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

    // MARK: - Deep Links

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "speakup" else { return }

        switch url.host {
        case "record":
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let promptId = components.queryItems?.first(where: { $0.name == "prompt" })?.value
            {
                let descriptor = FetchDescriptor<Prompt>()
                if let prompts = try? modelContext.fetch(descriptor) {
                    recordingPrompt = prompts.first { $0.id == promptId }
                }
            } else {
                recordingPrompt = nil
            }
            showingCountdown = true

        case "challenge":
            if socialChallengeService.handleIncomingURL(url) {
                showingChallengeAccept = true
            }

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

    var icon: String {
        switch self {
        case .today: return "mic.badge.plus"
        case .library: return "books.vertical.fill"
        case .history: return "clock.fill"
        case .learn: return "book"
        case .settings: return "gearshape"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}
