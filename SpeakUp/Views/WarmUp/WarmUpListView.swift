import SwiftUI

struct WarmUpListView: View {
    @State private var viewModel = WarmUpViewModel()
    @State private var showingExercise = false

    var presentation: ToolPresentation = .sheet

    var sourceStory: Story?

    /// Arrive from the focus browser in Library → Tools. The page scrolls to
    /// that group; it no longer hides the rest (see `FocusSection`).
    var initialFocus: PracticeFocus?

    private var longestExerciseSeconds: Double {
        Double(DefaultWarmUps.all.map(\.durationSeconds).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .warmUp, presentation: presentation, focus: initialFocus) {
            if let story = sourceStory {
                SourceStoryBanner(
                    eyebrow: "Warming up for",
                    title: story.title.isEmpty ? "Untitled story" : story.title
                )
            }

            exerciseContent
        }
        .fullScreenCover(isPresented: $showingExercise) {
            WarmUpExerciseView(viewModel: viewModel)
        }
    }

    // MARK: - Exercise Content

    /// Grouped by what the exercise improves, never by what it is. Every group
    /// is always present - a dozen warm-ups is a scroll, not a search problem,
    /// and the pill row that used to sit above these headings said the same
    /// three words in shorter form.
    private var exerciseContent: some View {
        VStack(spacing: 20) {
            ForEach(viewModel.availableFocuses) { focus in
                FocusSection(focus: focus, items: viewModel.exercises(for: focus)) { exercise in
                    exerciseRow(exercise)
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
            Haptics.medium()
            viewModel.selectExercise(exercise)
            showingExercise = true
        }
    }
}
