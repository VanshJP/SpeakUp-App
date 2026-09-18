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

            FocusFilterBar(
                focuses: viewModel.availableFocuses,
                selection: $viewModel.selectedFocus
            )

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
        let focuses = FocusFilterBar.visible(viewModel.availableFocuses, selection: viewModel.selectedFocus)

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
                    FocusSection(focus: focus, items: viewModel.exercises(for: focus)) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }
        }
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
