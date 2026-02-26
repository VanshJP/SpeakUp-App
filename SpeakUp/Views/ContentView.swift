import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    @State private var selectedTab: AppTab = .today
    @State private var showingCountdown = false
    @State private var showingRecording = false
    @State private var showingPromptWheel = false
    @State private var showingGoals = false
    @State private var selectedRecordingId: String?
    @State private var showOnboarding = false
    @State private var achievementService = AchievementService()
    @State private var socialChallengeService = SocialChallengeService()
    @State private var showingChallengeAccept = false

    // New feature sheets
    @State private var showingWarmUps = false
    @State private var showingDrills = false
    @State private var showingConfidenceTools = false
    @State private var showingBeforeAfter = false
    @State private var showingJournalExport = false
    @State private var showingCurriculum = false

    // Recording parameters to pass
    @State private var recordingPrompt: Prompt?
    @State private var recordingDuration: RecordingDuration = .sixty

    private var countdownDuration: Int {
        userSettings.first?.countdownDuration ?? 15
    }

    private var countdownStyle: CountdownStyle {
        CountdownStyle(rawValue: userSettings.first?.countdownStyle ?? 0) ?? .countDown
    }

    private var timerEndBehavior: TimerEndBehavior {
        TimerEndBehavior(rawValue: userSettings.first?.timerEndBehavior ?? 0) ?? .saveAndStop
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("Today", systemImage: "mic.badge.plus", value: .today) {
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
                                showingCurriculum = true
                            }
                        )
                        .sheet(isPresented: $showingCurriculum) {
                            NavigationStack {
                                CurriculumView()
                            }
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                        }
                    }
                }

                Tab("Prompts", systemImage: "text.bubble.fill", value: .prompts) {
                    NavigationStack {
                        AllPromptsView(onSelectPrompt: { prompt in
                            recordingPrompt = prompt
                            recordingDuration = .sixty
                            showingCountdown = true
                        })
                    }
                }

                Tab("History", systemImage: "clock.fill", value: .history) {
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
                }

                Tab("Rewards", systemImage: "trophy.fill", value: .achievements) {
                    NavigationStack {
                        AchievementGalleryView()
                    }
                }

                Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                    NavigationStack {
                        SettingsView()
                    }
                }
            }
            .tint(.teal)

            // Countdown Overlay
            if showingCountdown {
                CountdownOverlayView(
                    prompt: recordingPrompt,
                    duration: recordingDuration,
                    countdownDuration: countdownDuration,
                    countdownStyle: countdownStyle,
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
        .fullScreenCover(isPresented: $showingRecording) {
            RecordingView(
                prompt: recordingPrompt,
                duration: recordingDuration,
                timerEndBehavior: timerEndBehavior,
                countdownStyle: countdownStyle,
                onComplete: { recording in
                    showingRecording = false
                    Task {
                        await achievementService.checkAchievements(context: modelContext)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedRecordingId = recording.id.uuidString
                        selectedTab = .history
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
            NavigationStack {
                GoalsView()
            }
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
        .sheet(isPresented: $showingBeforeAfter) {
            BeforeAfterReplayView()
        }
        .sheet(isPresented: $showingJournalExport) {
            JournalExportView()
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
               let promptId = components.queryItems?.first(where: { $0.name == "prompt" })?.value {
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
    case achievements
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .prompts: return "Prompts"
        case .history: return "History"
        case .achievements: return "Rewards"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .today: return "mic.badge.plus"
        case .prompts: return "text.bubble"
        case .history: return "clock"
        case .achievements: return "trophy"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .today: return "mic.badge.plus"
        case .prompts: return "text.bubble.fill"
        case .history: return "clock.fill"
        case .achievements: return "trophy.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}
