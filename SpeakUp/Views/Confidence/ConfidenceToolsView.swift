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

    /// The focuses Calm actually covers, in declaration order. Derived, so
    /// adding an exercise cannot leave a pill behind.
    private var availableFocuses: [PracticeFocus] {
        PracticeFocus.allCases.filter { focus in
            DefaultConfidenceExercises.all.contains { $0.category.focus == focus }
        }
    }

    private var longestExerciseMinutes: Double {
        Double(DefaultConfidenceExercises.all.map(\.durationMinutes).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .calm, presentation: presentation) {
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
        let focuses = selectedFocus.map { [$0] } ?? availableFocuses

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
                    focusSection(focus)
                }
            }
        }
    }

    private func focusSection(_ focus: PracticeFocus) -> some View {
        let items = exercises.filter { $0.category.focus == focus }
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
