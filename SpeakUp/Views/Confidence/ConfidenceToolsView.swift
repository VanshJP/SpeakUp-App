import SwiftUI

struct ConfidenceToolsView: View {
    @State private var selectedFocus: PracticeFocus?
    @State private var showingExercise: ConfidenceExercise?

    var presentation: ToolPresentation = .sheet

    /// Arrive pre-narrowed from the focus browser in Library → Tools.
    var initialFocus: PracticeFocus?

    @State private var didApplyInitialFocus = false

    private var exercises: [ConfidenceExercise] {
        guard let selectedFocus else { return DefaultConfidenceExercises.all }
        return DefaultConfidenceExercises.all.filter { $0.category.focus == selectedFocus }
    }

    /// The focuses Calm actually covers, in declaration order.
    private var availableFocuses: [PracticeFocus] { PracticeToolKind.calm.focuses }

    private var longestExerciseMinutes: Double {
        Double(DefaultConfidenceExercises.all.map(\.durationMinutes).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .calm, presentation: presentation) {
            FocusFilterBar(focuses: availableFocuses, selection: $selectedFocus)

            exerciseContent
        }
        .task {
            guard !didApplyInitialFocus, let initialFocus else { return }
            didApplyInitialFocus = true
            selectedFocus = initialFocus
        }
        .fullScreenCover(item: $showingExercise) { exercise in
            ConfidenceExerciseView(exercise: exercise)
        }
    }

    // MARK: - Exercise Content

    /// Grouped by outcome, like every other tool page. Calm covers two: getting
    /// the body quiet, and getting the story you tell yourself straight. The
    /// technique — visualization, progressive exposure — is the row's tag.
    @ViewBuilder
    private var exerciseContent: some View {
        let focuses = FocusFilterBar.visible(availableFocuses, selection: selectedFocus)

        if exercises.isEmpty {
            EmptyStateCard(
                icon: "heart.circle",
                title: "Nothing here",
                message: "No exercises train that yet. Try another one.",
                buttonTitle: "Show All",
                buttonAction: {
                    withAnimation(AppMotion.slide) { selectedFocus = nil }
                }
            )
        } else {
            VStack(spacing: 20) {
                ForEach(focuses) { focus in
                    FocusSection(
                        focus: focus,
                        items: exercises.filter { $0.category.focus == focus }
                    ) { exercise in
                        exerciseRow(exercise)
                    }
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
