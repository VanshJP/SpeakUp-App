import SwiftUI
import SwiftData

struct DrillSelectionView: View {
    @Query private var userSettings: [UserSettings]
    @State private var viewModel = DrillViewModel()
    @State private var showingSession = false
    @State private var showingCountdown = false
    @State private var selectedDrillMode: DrillMode?

    /// Pushed onto a caller-owned `NavigationStack` (Library → Tools). See
    /// `ToolPage`, which owns what that changes.
    var isPushed: Bool = false

    var sourceStory: Story?
    /// Arms a specific drill on open — used when a session's weakest subscore
    /// routes the user straight to the drill that targets it.
    var initialMode: DrillMode?

    /// Denominator for each row's arc, so 15s and 60s drills read as
    /// different sizes of commitment rather than four identical cards.
    private var longestDrillSeconds: Double {
        Double(DrillMode.allCases.map(\.defaultDurationSeconds).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .drills, isPushed: isPushed) {
            if let story = sourceStory {
                SourceStoryBanner(
                    eyebrow: "Drilling from",
                    title: story.title.isEmpty ? "Untitled story" : story.title,
                    tint: AppColors.categoryNeutralCool,
                    trailingTag: "Impromptu"
                )
            }

            // Rows, not a 2x2 of fixed-height tiles. Four tiles each stacking
            // an icon, a title, an outcome, a live-feedback label and a
            // duration — two of them tinted — was five things competing inside
            // 176pt. The row says the same in one scan line, and matches the
            // other three tool pages.
            LazyVStack(spacing: 12) {
                ForEach(DrillMode.allCases) { mode in
                    PracticeItemRow(
                        title: mode.title,
                        subtitle: mode.outcome,
                        icon: mode.icon,
                        tint: mode.color,
                        durationFraction: PracticeItemRow.fraction(
                            Double(mode.defaultDurationSeconds),
                            longest: longestDrillSeconds
                        ),
                        durationLabel: "\(mode.defaultDurationSeconds)s",
                        // What the session shows while it runs — the concrete
                        // promise that makes the format legible.
                        tag: mode.liveFeedback
                    ) {
                        Haptics.medium()
                        // Impromptu picks its topic now so the prep countdown
                        // can show it — that window is the thinking time the
                        // format promises.
                        if mode == .impromptuSprint {
                            viewModel.prepareImpromptuTopic()
                        }
                        selectedDrillMode = mode
                        showingCountdown = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingSession) {
            DrillSessionView(viewModel: viewModel)
        }
        .overlay {
            if showingCountdown, let mode = selectedDrillMode {
                CountdownOverlayView(
                    prompt: nil,
                    duration: .thirty,
                    countdownDuration: userSettings.first?.countdownDuration ?? 15,
                    countdownStyle: CountdownStyle(rawValue: userSettings.first?.countdownStyle ?? 0) ?? .countDown,
                    look: TimerLook(rawValue: userSettings.first?.countdownLook ?? 0) ?? .ring,
                    backdrop: RecordingBackdrop(rawValue: userSettings.first?.countdownBackdrop ?? 0) ?? .base,
                    prepTitle: mode.title,
                    prepSubtitle: mode == .impromptuSprint ? viewModel.impromptuPrompt : mode.description,
                    onComplete: {
                        showingCountdown = false
                        viewModel.targetWPM = userSettings.first.resolvedTargetWPM
                        viewModel.startDrill(mode: mode)
                        showingSession = true
                    },
                    onCancel: {
                        showingCountdown = false
                        selectedDrillMode = nil
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingCountdown)
        .task {
            guard let initialMode else { return }
            selectedDrillMode = initialMode
            showingCountdown = true
        }
    }
}
