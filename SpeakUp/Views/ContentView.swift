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
    @State private var showingEvents = false
    @State private var showingReadAloud = false
    @State private var settingsViewModel = SettingsViewModel()

    // Recording parameters to pass
    @State private var recordingPrompt: Prompt?
    @State private var recordingDuration: RecordingDuration = .sixty
    @State private var recordingGoalId: UUID?
    @State private var recordingEventId: UUID?
    @State private var recordingScriptVersionId: UUID?

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
                        recordingEventId = nil
                        recordingScriptVersionId = nil
                        showingCountdown = true
                    },
                    onShowWheel: {
                        showingPromptWheel = true
                    },
                    onShowGoals: {
                        showingGoals = true
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
                    onShowEvents: {
                        showingEvents = true
                    },
                    onShowReadAloud: {
                        showingReadAloud = true
                    }
                )
            }
        case .prompts:
            NavigationStack {
                AllPromptsView(onSelectPrompt: { prompt in
                    recordingPrompt = prompt
                    recordingDuration = .sixty
                    recordingEventId = nil
                    recordingScriptVersionId = nil
                    showingCountdown = true
                })
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
            
            // Countdown Overlay
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
            recordingEventId = nil
            recordingScriptVersionId = nil
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
                eventId: recordingEventId,
                scriptVersionId: recordingScriptVersionId,
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
                recordingEventId = nil
                recordingScriptVersionId = nil
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
        .sheet(isPresented: $showingDrills) {
            DrillSelectionView()
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
        .sheet(isPresented: $showingEvents) {
            EventListView(onStartPractice: { event, scriptVersionId in
                recordingEventId = event.id
                recordingScriptVersionId = scriptVersionId
                let targetSeconds = event.expectedDurationMinutes * 60
                recordingDuration = RecordingDuration.allCases.min(by: {
                    abs($0.rawValue - targetSeconds) < abs($1.rawValue - targetSeconds)
                }) ?? .sixty
                recordingPrompt = nil
                showingEvents = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingCountdown = true
                }
            })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReadAloud) {
            ReadAloudSelectionView()
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
                        recordingEventId = nil
                        recordingScriptVersionId = nil
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
            OnboardingView {
                if let settings = userSettings.first {
                    settings.hasCompletedOnboarding = true
                    try? modelContext.save()
                }
                showOnboarding = false
            }
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
            recordingEventId = nil
            recordingScriptVersionId = nil
            showingCountdown = true

        case "challenge":
            if socialChallengeService.handleIncomingURL(url) {
                showingChallengeAccept = true
            }

        default:
            break
        }
    }
}

// MARK: - App Tab Enum

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case prompts
    case history
    case learn
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .prompts: return "Prompts"
        case .history: return "History"
        case .learn: return "Learn"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .today: return "mic.badge.plus"
        case .prompts: return "text.bubble"
        case .history: return "clock"
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

