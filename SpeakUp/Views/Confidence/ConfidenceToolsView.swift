import SwiftUI

struct ConfidenceToolsView: View {
    @State private var selectedCategory: ConfidenceCategory?
    @State private var showingExercise: ConfidenceExercise?

    var presentation: ToolPresentation = .sheet

    private var exercises: [ConfidenceExercise] {
        guard let selectedCategory else { return DefaultConfidenceExercises.all }
        return DefaultConfidenceExercises.all.filter { $0.category == selectedCategory }
    }

    private var longestExerciseMinutes: Double {
        Double(exercises.map(\.durationMinutes).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .calm, presentation: presentation) {
            ToolFilterBar {
                FilterPill(
                    title: "All",
                    icon: "square.grid.2x2",
                    isSelected: selectedCategory == nil
                ) {
                    withAnimation(AppMotion.slide) { selectedCategory = nil }
                }

                ForEach(ConfidenceCategory.allCases) { category in
                    FilterPill(
                        title: category.displayName,
                        icon: category.icon,
                        isSelected: selectedCategory == category,
                        color: category.color
                    ) {
                        withAnimation(AppMotion.slide) { selectedCategory = category }
                    }
                }
            }

            exerciseContent
        }
        .fullScreenCover(item: $showingExercise) { exercise in
            ConfidenceExerciseView(exercise: exercise)
        }
    }

    // MARK: - Exercise Content

    @ViewBuilder
    private var exerciseContent: some View {
        if selectedCategory != nil {
            if exercises.isEmpty {
                EmptyStateCard(
                    icon: "heart.circle",
                    title: "Nothing here",
                    message: "No exercises in this category yet. Try another one."
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(exercises) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }
        } else {
            VStack(spacing: 20) {
                ForEach(ConfidenceCategory.allCases) { category in
                    categorySection(category)
                }
            }
        }
    }

    private func categorySection(_ category: ConfidenceCategory) -> some View {
        let items = exercises.filter { $0.category == category }
        guard !items.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                GlassSectionHeader(category.displayName, icon: category.icon) {
                    Text("\(items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(category.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
