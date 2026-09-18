import SwiftUI
import SwiftData

struct DrillSelectionView: View {
    @State private var viewModel = DrillViewModel()

    /// The drill being run, and the only state the cover reads.
    ///
    /// This used to be three: a `showingDrillFlow` flag that presented the
    /// cover, a `selectedDrillMode` the cover's content unwrapped, and a
    /// `showingSession` phase — with an `onDismiss` that cleared the last two.
    /// SwiftUI runs `onDismiss` *after* the dismissal animation, so starting a
    /// second drill while the first was still animating out set the mode, then
    /// had it cleared out from under the presentation: the cover opened on
    /// nothing, drew a blank screen, and closed itself again. Tapping a second
    /// time worked only because by then nothing was animating.
    ///
    /// `fullScreenCover(item:)` hands the mode to the content instead of
    /// leaving it to be read back out of view state, so there is nothing left
    /// to race and no "no mode" branch to render.
    @State private var activeDrill: DrillMode?

    var presentation: ToolPresentation = .sheet

    var sourceStory: Story?
    var initialMode: DrillMode?

    /// Arrive pre-narrowed from the focus browser in Library → Tools.
    var initialFocus: PracticeFocus?

    @State private var selectedFocus: PracticeFocus?
    @State private var didApplyInitialFocus = false

    private var visibleModes: [DrillMode] {
        guard let selectedFocus else { return DrillMode.allCases }
        return DrillMode.allCases.filter { $0.focus == selectedFocus }
    }

    /// Focuses the shipped drill modes cover, in declaration order.
    private var availableFocuses: [PracticeFocus] { PracticeToolKind.drills.focuses }

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

            FocusFilterBar(focuses: availableFocuses, selection: $selectedFocus)

            // Drills were already named for outcomes — they are just headed by
            // them now, in the same vocabulary the other three tools use, so a
            // reader can see that Emphasis and Vocal Variety are the same job.
            VStack(spacing: 20) {
                ForEach(FocusFilterBar.visible(availableFocuses, selection: selectedFocus)) { focus in
                    FocusSection(focus: focus, items: visibleModes.filter { $0.focus == focus }) { mode in
                        drillRow(mode)
                    }
                }
            }
        }
        .fullScreenCover(item: $activeDrill) { mode in
            DrillFlowView(mode: mode, viewModel: viewModel)
        }
        .task {
            if !didApplyInitialFocus, let initialFocus {
                didApplyInitialFocus = true
                selectedFocus = initialFocus
            }
            guard let initialMode else { return }
            activeDrill = initialMode
        }
    }

    // MARK: - Rows

    private func drillRow(_ mode: DrillMode) -> some View {
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
            activeDrill = mode
        }
    }
}

// MARK: - Drill Flow

/// Countdown, then the drill itself, inside one cover.
///
/// The phase lives here — as this view's own state, created fresh with the
/// presentation — rather than beside the flag that presents the cover. That
/// pairing is what produced the blank screen; see `DrillSelectionView`.
private struct DrillFlowView: View {
    let mode: DrillMode
    var viewModel: DrillViewModel

    @Environment(\.dismiss) private var dismiss
    @Query private var userSettings: [UserSettings]
    @State private var isRunning = false

    var body: some View {
        if isRunning {
            DrillSessionView(viewModel: viewModel)
        } else {
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
                        isRunning = true
                    }
                },
                onCancel: {
                    dismiss()
                }
            )
        }
    }
}
