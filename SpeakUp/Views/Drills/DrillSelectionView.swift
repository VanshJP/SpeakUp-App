import SwiftUI
import SwiftData

struct DrillSelectionView: View {
    @Query private var userSettings: [UserSettings]
    @State private var viewModel = DrillViewModel()
    @State private var showingDrillFlow = false
    @State private var showingSession = false
    @State private var selectedDrillMode: DrillMode?

    var presentation: ToolPresentation = .sheet

    var sourceStory: Story?
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
                        tag: mode.liveFeedback
                    ) {
                        Haptics.medium()
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
