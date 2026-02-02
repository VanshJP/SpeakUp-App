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

    // Recording parameters to pass
    @State private var recordingPrompt: Prompt?
    @State private var recordingDuration: RecordingDuration = .sixty

    private var countdownDuration: Int {
        userSettings.first?.countdownDuration ?? 15
    }
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("Today", systemImage: "house.fill", value: .today) {
                    NavigationStack {
                        TodayView(
                            onStartRecording: { prompt, duration in
                                recordingPrompt = prompt
                                recordingDuration = duration
                                // Show countdown first instead of going directly to recording
                                showingCountdown = true
                            },
                            onShowWheel: {
                                showingPromptWheel = true
                            },
                            onShowGoals: {
                                showingGoals = true
                            }
                        )
                    }
                }
                
                Tab("History", systemImage: "clock.fill", value: .history) {
                    NavigationStack {
                        HistoryView(onSelectRecording: { recordingId in
                            selectedRecordingId = recordingId
                        })
                        .navigationDestination(item: $selectedRecordingId) { recordingId in
                            RecordingDetailView(recordingId: recordingId)
                        }
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
                    onComplete: {
                        // Countdown finished - transition to recording
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
                onComplete: { recording in
                    showingRecording = false
                    // Navigate to detail view after a short delay
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
                // Small delay before showing countdown
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
    }
}

// MARK: - App Tab Enum

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case history
    case settings
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .today: return "Today"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .today: return "house"
        case .history: return "clock"
        case .settings: return "gearshape"
        }
    }
    
    var selectedIcon: String {
        switch self {
        case .today: return "house.fill"
        case .history: return "clock.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}
