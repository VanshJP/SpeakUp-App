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

    /// Arrive pre-narrowed from the focus browser in Library → Tools.
    var initialFocus: PracticeFocus?

    @State private var selectedFocus: PracticeFocus?
    @State private var didApplyInitialFocus = false

    private var visibleModes: [DrillMode] {
        guard let selectedFocus else { return DrillMode.allCases }
        return DrillMode.allCases.filter { $0.focus == selectedFocus }
    }

    /// Focuses the shipped drill modes cover, in declaration order.
    private var availableFocuses: [PracticeFocus] {
        PracticeFocus.allCases.filter { focus in
            DrillMode.allCases.contains { $0.focus == focus }
        }
    }

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

            ToolFilterBar {
                FilterPill(
                    title: "All",
                    icon: "square.grid.2x2",
                    isSelected: selectedFocus == nil
                ) {
                    withAnimation(AppMotion.slide) { selectedFocus = nil }
                }

                ForEach(availableFocuses) { focus in
                    FilterPill(
                        title: focus.shortTitle,
                        icon: focus.icon,
                        isSelected: selectedFocus == focus,
                        color: focus.color
                    ) {
                        withAnimation(AppMotion.slide) {
                            selectedFocus = selectedFocus == focus ? nil : focus
                        }
                    }
                }
            }

            // Drills were already named for outcomes — they are just headed by
            // them now, in the same vocabulary the other three tools use, so a
            // reader can see that Emphasis and Vocal Variety are the same job.
            VStack(spacing: 20) {
                ForEach(selectedFocus.map { [$0] } ?? availableFocuses) { focus in
                    focusSection(focus)
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
            if !didApplyInitialFocus, let initialFocus {
                didApplyInitialFocus = true
                selectedFocus = initialFocus
            }
            guard let initialMode else { return }
            selectedDrillMode = initialMode
            showingSession = false
            showingDrillFlow = true
        }
    }

    // MARK: - Sections

    private func focusSection(_ focus: PracticeFocus) -> some View {
        let modes = visibleModes.filter { $0.focus == focus }
        guard !modes.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                GlassSectionHeader(focus.title, icon: focus.icon) {
                    Text("\(modes.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(focus.promise)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVStack(spacing: 12) {
                    ForEach(modes) { mode in
                        drillRow(mode)
                    }
                }
            }
        )
    }

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
            selectedDrillMode = mode
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
