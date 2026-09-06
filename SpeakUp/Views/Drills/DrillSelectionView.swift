import SwiftUI
import SwiftData

struct DrillSelectionView: View {
    @Query private var userSettings: [UserSettings]
    @State private var viewModel = DrillViewModel()
    @State private var showingDrillFlow = false
    @State private var showingSession = false
    @State private var selectedDrillMode: DrillMode?

    /// How this list is hosted. See `ToolPresentation` / `ToolPage`.
    var presentation: ToolPresentation = .sheet

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
        ToolPage(tool: .drills, presentation: presentation) {
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
                        if mode.preparesPromptUpFront {
                            viewModel.preparePrompt(for: mode)
                        }
                        selectedDrillMode = mode
                        showingSession = false
                        showingDrillFlow = true
                    }
                }
            }
        }
        // One full-screen cover owns countdown → session. An overlay on the
        // Library tools list clipped the dial into a card-shaped box, then a
        // second cover jumped to the session — two surfaces for one flow.
        .fullScreenCover(isPresented: $showingDrillFlow, onDismiss: {
            showingSession = false
            selectedDrillMode = nil
        }) {
            drillFlowCover
        }
        .task {
            guard let initialMode else { return }
            selectedDrillMode = initialMode
            showingSession = false
            showingDrillFlow = true
        }
    }

    @ViewBuilder
    private var drillFlowCover: some View {
        if showingSession {
            DrillSessionView(viewModel: viewModel)
        } else if let mode = selectedDrillMode {
            CountdownOverlayView(
                prompt: nil,
                duration: .thirty,
                countdownDuration: userSettings.first?.countdownDuration ?? 15,
                countdownStyle: CountdownStyle(rawValue: userSettings.first?.countdownStyle ?? 0) ?? .countDown,
                look: TimerLook(rawValue: userSettings.first?.countdownLook ?? 0) ?? .ring,
                backdrop: RecordingBackdrop(rawValue: userSettings.first?.countdownBackdrop ?? 0) ?? .base,
                prepTitle: mode.title,
                prepSubtitle: mode.preparesPromptUpFront ? viewModel.impromptuPrompt : mode.description,
                onComplete: {
                    viewModel.targetWPM = userSettings.first.resolvedTargetWPM
                    viewModel.startDrill(mode: mode)
                    withAnimation(AppMotion.settle) {
                        showingSession = true
                    }
                },
                onCancel: {
                    showingDrillFlow = false
                    selectedDrillMode = nil
                }
            )
        } else {
            Color.clear.onAppear { showingDrillFlow = false }
        }
    }
}
