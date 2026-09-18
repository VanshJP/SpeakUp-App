import SwiftUI

struct ConfidenceToolsView: View {
    @State private var showingExercise: ConfidenceExercise?

    var presentation: ToolPresentation = .sheet

    /// Arrive from the focus browser in Library → Tools. The page scrolls to
    /// that group; it no longer hides the rest (see `FocusSection`).
    var initialFocus: PracticeFocus?

    /// The focuses Calm actually covers, in declaration order.
    private var availableFocuses: [PracticeFocus] { PracticeToolKind.calm.focuses }

    private func exercises(for focus: PracticeFocus) -> [ConfidenceExercise] {
        DefaultConfidenceExercises.all.filter { $0.category.focus == focus }
    }

    private var longestExerciseMinutes: Double {
        Double(DefaultConfidenceExercises.all.map(\.durationMinutes).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .calm, presentation: presentation, focus: initialFocus) {
            exerciseContent
        }
        .fullScreenCover(item: $showingExercise) { exercise in
            ConfidenceExerciseView(exercise: exercise)
        }
    }

    // MARK: - Exercise Content

    /// Grouped by outcome, like every other tool page. Calm covers two: getting
    /// the body quiet, and getting the story you tell yourself straight. The
    /// technique — visualization, progressive exposure — is the row's tag.
    ///
    /// Two groups never needed a filter above them.
    private var exerciseContent: some View {
        VStack(spacing: 20) {
            ForEach(availableFocuses) { focus in
                FocusSection(focus: focus, items: exercises(for: focus)) { exercise in
                    exerciseRow(exercise)
                }
            }
        }
    }

    private func exerciseRow(_ exercise: ConfidenceExercise) -> some View {
        PracticeItemRow(
            title: exercise.title,
            subtitle: exercise.description,
            icon: exercise.category.icon,
            tint: exercise.category.color,
            durationFraction: PracticeItemRow.fraction(
                Double(exercise.durationMinutes),
                longest: longestExerciseMinutes
            ),
            durationLabel: "\(exercise.durationMinutes)m",
            tag: "\(exercise.steps.count) steps"
        ) {
            Haptics.medium()
            showingExercise = exercise
        }
    }
}
