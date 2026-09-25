import SwiftUI
import SwiftData

struct DrillSelectionView: View {
    @Environment(\.dismiss) private var dismiss
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

    /// Set once `initialMode` has opened its drill. `.task` runs again each
    /// time this page reappears, and a full-screen cover closing is a
    /// reappearance - without this, closing the drill launched it again.
    @State private var didLaunchInitialMode = false

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
                    tint: AppColors.categoryNeutralCool
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
        .fullScreenCover(item: $activeDrill, onDismiss: drillClosed) { mode in
            DrillFlowView(
                mode: mode,
                viewModel: viewModel,
                // The rung `startDrill` will run: the highest one open.
                roundSeconds: mode.durationSeconds(atLevel: DrillProgressStore.record(for: mode)?.level ?? 0)
            )
        }
        .onAppear(perform: loadRecords)
        .task {
            guard !didLaunchInitialMode, let initialMode else { return }
            didLaunchInitialMode = true
            start(initialMode)
        }
    }

    /// A drill opened for its caller - a result's next step, Today's focus
    /// card - hands back to that caller when it closes. It used to land on the
    /// full drill catalog, one more ✕ away from the result that prescribed it.
    private func drillClosed() {
        loadRecords()
        if initialMode != nil { dismiss() }
    }

    private func start(_ mode: DrillMode) {
        viewModel.preparePrompt(for: mode)
        if let storyTopic, takesStoryTopic(mode) {
            viewModel.impromptuPrompt = storyTopic
        }
        activeDrill = mode
    }

    // MARK: - Story

    /// The story as the drill's topic: tell it, no script. "Drilling from" a
    /// story used to be a banner only - every drill still drew a stock topic.
    private var storyTopic: String? {
        guard let sourceStory else { return nil }
        let title = sourceStory.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty
            ? "Tell your story in your own words, without the script"
            : "Tell \u{201C}\(title)\u{201D} in your own words, without the script"
    }

    /// Drills that talk through a topic. Vocal Variety and Emphasis work one
    /// scripted line, and Q&A answers a question, so they keep their own.
    private func takesStoryTopic(_ mode: DrillMode) -> Bool {
        switch mode {
        case .fillerElimination, .paceControl, .pausePractice, .impromptuSprint: return true
        case .vocalVariety, .emphasis, .qaSprint: return false
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
            start(mode)
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
    /// Named on the prep screen: the ladder changes it run to run.
    let roundSeconds: Int

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
                prepTitle: "\(mode.title) · \(roundSeconds)s",
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
