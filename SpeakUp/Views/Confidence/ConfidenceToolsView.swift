import SwiftUI

struct ConfidenceToolsView: View {
    /// nil = all categories. The page opens unfiltered so the whole map of
    /// exercises is visible; a category pill narrows from there.
    @State private var selectedCategory: ConfidenceCategory?
    @State private var showingExercise: ConfidenceExercise?

    /// Pushed onto a caller-owned `NavigationStack` (Library → Tools). See
    /// `ToolPage`, which owns what that changes.
    var isPushed: Bool = false

    private var exercises: [ConfidenceExercise] {
        guard let selectedCategory else { return DefaultConfidenceExercises.all }
        return DefaultConfidenceExercises.all.filter { $0.category == selectedCategory }
    }

    /// Denominator for every row's duration arc, scoped to what is visible.
    private var longestExerciseMinutes: Double {
        Double(exercises.map(\.durationMinutes).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .calm, isPushed: isPushed) {
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

    /// Unfiltered shows every category as a labeled section (name, what it's
    /// for, how many), so browsing teaches the taxonomy. A filter collapses
    /// to the single matching group.
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
            // Cost before commit: minutes in the dial, and how many steps that
            // buys in the chip — a 10-step ladder and a 4-step reset read very
            // differently, and both never fit in the dial's 8pt label.
            tag: "\(exercise.steps.count) steps"
        ) {
            Haptics.medium()
            showingExercise = exercise
        }
    }
}
