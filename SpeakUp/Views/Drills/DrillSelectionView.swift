import SwiftUI
import SwiftData

struct DrillSelectionView: View {
    @State private var viewModel = DrillViewModel()

    /// The drill being run, and the only state the cover reads.
    ///
    /// This used to be three: a `showingDrillFlow` flag that presented the
    /// cover, a `selectedDrillMode` the cover's content unwrapped, and a
    /// `showingSession` phase - with an `onDismiss` that cleared the last two.
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

    /// Best score, runs and level per drill, re-read whenever a drill closes.
    /// They live in `UserDefaults`, which nothing observes.
    @State private var records: [DrillMode: DrillRecord] = [:]

    var presentation: ToolPresentation = .sheet

    var sourceStory: Story?
    var initialMode: DrillMode?

    /// Arrive from the focus browser in Library → Tools. The page scrolls to
    /// that group; it no longer hides the rest (see `FocusSection`).
    var initialFocus: PracticeFocus?

    /// Focuses the shipped drill modes cover, in declaration order.
    private var availableFocuses: [PracticeFocus] { PracticeToolKind.drills.focuses }

    private func modes(for focus: PracticeFocus) -> [DrillMode] {
        DrillMode.allCases.filter { $0.focus == focus }
    }

    /// Denominator for each row's arc, so 15s and 60s drills read as
    /// different sizes of commitment rather than four identical cards.
    private var longestDrillSeconds: Double {
        Double(DrillMode.allCases.compactMap(\.durationLadder.last).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .drills, presentation: presentation, focus: initialFocus) {
            if let story = sourceStory {
                SourceStoryBanner(
                    eyebrow: "Drilling from",
                    title: story.title.isEmpty ? "Untitled story" : story.title,
                    tint: AppColors.categoryNeutralCool,
                    trailingTag: "Impromptu"
                )
            }

            // Drills were already named for outcomes - they are just headed by
            // them now, in the same vocabulary the other three tools use, so a
            // reader can see that Emphasis and Vocal Variety are the same job.
            // Seven drills under five headings never needed a filter as well.
            VStack(spacing: 20) {
                ForEach(availableFocuses) { focus in
                    FocusSection(focus: focus, items: modes(for: focus)) { mode in
                        drillRow(mode)
                    }
                }
            }
        }
        .fullScreenCover(item: $activeDrill, onDismiss: loadRecords) { mode in
            DrillFlowView(mode: mode, viewModel: viewModel)
        }
        .onAppear(perform: loadRecords)
        .task {
            guard let initialMode else { return }
            viewModel.preparePrompt(for: initialMode)
            activeDrill = initialMode
        }
    }

    private func loadRecords() {
        var loaded: [DrillMode: DrillRecord] = [:]
        for mode in DrillMode.allCases {
            loaded[mode] = DrillProgressStore.record(for: mode)
        }
        records = loaded
    }

    // MARK: - Rows

    private func drillRow(_ mode: DrillMode) -> some View {
        let record = records[mode]
        let seconds = mode.durationSeconds(atLevel: record?.level ?? 0)
        return PracticeItemRow(
            title: mode.title,
            subtitle: mode.outcome,
            icon: mode.icon,
            tint: mode.color,
            durationFraction: PracticeItemRow.fraction(
                Double(seconds),
                longest: longestDrillSeconds
            ),
            durationLabel: "\(seconds)s",
            tag: progressTag(for: mode, record: record)
        ) {
            Haptics.medium()
            viewModel.preparePrompt(for: mode)
            activeDrill = mode
        }
    }

    /// What the drill shows while you run it until you have run it, then the
    /// number to beat - and, on a laddered drill, which rung you are on.
    private func progressTag(for mode: DrillMode, record: DrillRecord?) -> String {
        guard let record, record.runs > 0 else { return mode.liveFeedback }
        let best = "Best \(record.best)"
        guard mode.durationLadder.count > 1 else { return best }
        return "Level \(record.level + 1) of \(mode.durationLadder.count) · \(best)"
    }
}

// MARK: - Drill Flow

/// Countdown, then the drill itself, inside one cover.
///
/// The phase lives here - as this view's own state, created fresh with the
/// presentation - rather than beside the flag that presents the cover. That
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
                prepSubtitle: viewModel.impromptuPrompt.isEmpty ? mode.description : viewModel.impromptuPrompt,
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
