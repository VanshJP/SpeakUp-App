import SwiftUI

struct WarmUpListView: View {
    @State private var viewModel = WarmUpViewModel()
    @State private var showingExercise = false

    var presentation: ToolPresentation = .sheet

    var sourceStory: Story?

    /// Arrive pre-narrowed from the focus browser in Library → Tools.
    var initialFocus: PracticeFocus?

    @State private var didApplyInitialFocus = false

    private var longestExerciseSeconds: Double {
        Double(DefaultWarmUps.all.map(\.durationSeconds).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .warmUp, presentation: presentation) {
            if let story = sourceStory {
                SourceStoryBanner(
                    eyebrow: "Warming up for",
                    title: story.title.isEmpty ? "Untitled note" : story.title
                )
            }

            ToolFilterBar {
                FilterPill(
                    title: "All",
                    icon: "square.grid.2x2",
                    isSelected: viewModel.selectedFocus == nil
                ) {
                    withAnimation(AppMotion.slide) { viewModel.selectedFocus = nil }
                }

                ForEach(viewModel.availableFocuses) { focus in
                    FilterPill(
                        title: focus.shortTitle,
                        icon: focus.icon,
                        isSelected: viewModel.selectedFocus == focus,
                        color: focus.color
                    ) {
                        withAnimation(AppMotion.slide) {
                            viewModel.selectedFocus = viewModel.selectedFocus == focus ? nil : focus
                        }
                    }
                }
            }

            exerciseContent
        }
        .task {
            guard !didApplyInitialFocus, let initialFocus else { return }
            didApplyInitialFocus = true
            viewModel.selectedFocus = initialFocus
        }
        .fullScreenCover(isPresented: $showingExercise) {
            WarmUpExerciseView(viewModel: viewModel)
        }
    }

    // MARK: - Exercise Content

    /// Grouped by what the exercise improves, never by what it is. Both the
    /// unfiltered map and a narrowed list use the same section, so a filter
    /// collapses the page to one group rather than swapping it for a flat list
    /// that has lost its heading (invariant 8, map before mask).
    @ViewBuilder
    private var exerciseContent: some View {
        let focuses = viewModel.selectedFocus.map { [$0] } ?? viewModel.availableFocuses

        if viewModel.exercises.isEmpty {
            EmptyStateCard(
                icon: "wind",
                title: "Nothing here",
                message: "No warm-ups train that yet. Try another one.",
                buttonTitle: "Show All",
                buttonAction: {
                    withAnimation(AppMotion.slide) { viewModel.selectedFocus = nil }
                }
            )
        } else {
            VStack(spacing: 20) {
                ForEach(focuses) { focus in
                    focusSection(focus)
                }
            }
        }
    }

    private func focusSection(_ focus: PracticeFocus) -> some View {
        let items = viewModel.exercises(for: focus)
        guard !items.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                GlassSectionHeader(focus.title, icon: focus.icon) {
                    Text("\(items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(focus.promise)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVStack(spacing: 12) {
                    ForEach(items) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }
        )
    }

    private func exerciseRow(_ exercise: WarmUpExercise) -> some View {
        PracticeItemRow(
            title: exercise.title,
            subtitle: exercise.instructions,
            icon: exercise.category.icon,
            tint: exercise.category.color,
            durationFraction: PracticeItemRow.fraction(
                Double(exercise.durationSeconds),
                longest: longestExerciseSeconds
            ),
            durationLabel: "\(exercise.durationSeconds)s",
            // The mechanism moves here. It is useful once you have decided
            // what you are training, and misleading as the thing you browse by.
            tag: exercise.category.displayName,
            accessory: .play
        ) {
            viewModel.selectExercise(exercise)
            showingExercise = true
        }
    }
}
