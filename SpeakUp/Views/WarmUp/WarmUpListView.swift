import SwiftUI

struct WarmUpListView: View {
    @State private var viewModel = WarmUpViewModel()
    @State private var showingExercise = false

    /// Pushed onto a caller-owned `NavigationStack` (Library → Tools). See
    /// `ToolPage`, which owns what that changes.
    var isPushed: Bool = false

    var sourceStory: Story?

    /// Denominator for every row's duration arc. Scoped to the visible
    /// category, so the arcs re-scale as you filter — within one category the
    /// relative lengths are what's worth comparing.
    private var longestExerciseSeconds: Double {
        Double(viewModel.exercises.map(\.durationSeconds).max() ?? 0)
    }

    var body: some View {
        ToolPage(tool: .warmUp, isPushed: isPushed) {
            if let story = sourceStory {
                SourceStoryBanner(
                    eyebrow: "Warming up for",
                    title: story.title.isEmpty ? "Untitled note" : story.title
                )
            }

            // All first, so the page opens showing the whole map rather than
            // one slice of it.
            ToolFilterBar {
                FilterPill(
                    title: "All",
                    icon: "square.grid.2x2",
                    isSelected: viewModel.selectedCategory == nil
                ) {
                    withAnimation(AppMotion.slide) { viewModel.selectedCategory = nil }
                }

                ForEach(WarmUpCategory.allCases) { category in
                    FilterPill(
                        title: category.displayName,
                        icon: category.icon,
                        isSelected: viewModel.selectedCategory == category,
                        color: category.color
                    ) {
                        withAnimation(AppMotion.slide) { viewModel.selectedCategory = category }
                    }
                }
            }

            exerciseContent
        }
        .fullScreenCover(isPresented: $showingExercise) {
            WarmUpExerciseView(viewModel: viewModel)
        }
    }

    // MARK: - Exercise Content

    /// Unfiltered shows every category as a labeled section (name, what it's
    /// for, how many), so browsing teaches the taxonomy. A filter collapses
    /// to the single matching group.
    @ViewBuilder
    private var exerciseContent: some View {
        if let selected = viewModel.selectedCategory {
            if viewModel.exercises.isEmpty {
                EmptyStateCard(
                    icon: "wind",
                    title: "Nothing here",
                    message: "No warm-ups in this category yet. Try another one.",
                    buttonTitle: "Show All",
                    buttonAction: {
                        withAnimation(AppMotion.slide) {
                            viewModel.selectedCategory = nil
                        }
                    }
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.exercises) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }
        } else {
            VStack(spacing: 20) {
                ForEach(WarmUpCategory.allCases) { category in
                    categorySection(category)
                }
            }
        }
    }

    private func categorySection(_ category: WarmUpCategory) -> some View {
        let items = viewModel.exercises.filter { $0.category == category }
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
            accessory: .play
        ) {
            viewModel.selectExercise(exercise)
            showingExercise = true
        }
    }
}
