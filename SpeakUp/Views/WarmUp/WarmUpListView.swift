import SwiftUI

struct WarmUpListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = WarmUpViewModel()
    @State private var showingExercise = false

    /// When true the list is pushed onto a caller-owned `NavigationStack`
    /// (Library → Tools): no inner stack, and the sheet's ✕ gives way to the
    /// system back button.
    var isPushed: Bool = false

    var sourceStory: Story?

    /// Denominator for every row's duration arc. Scoped to the visible
    /// category, so the arcs re-scale as you filter — within one category the
    /// relative lengths are what's worth comparing.
    private var longestExerciseSeconds: Double {
        Double(viewModel.exercises.map(\.durationSeconds).max() ?? 0)
    }

    var body: some View {
        if isPushed {
            content
        } else {
            NavigationStack {
                content
            }
        }
    }

    private var content: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                VStack(spacing: 16) {
                    // Page identity: the eyebrow names the family, the
                    // banner carries outcome + best-for from PracticeToolKind
                    // so Today, Library, and this sheet tell one story.
                    // Same header grammar as Drills, Read Aloud, and Calm.
                    Text("Get Ready")
                        .eyebrowStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ToolPurposeBanner(tool: .warmUp)

                    if let story = sourceStory {
                        sourceStoryBanner(story)
                    }

                    // Category picker — All first, so the page opens
                    // showing the whole map instead of one slice of it.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterPill(
                                title: "All",
                                icon: "square.grid.2x2",
                                isSelected: viewModel.selectedCategory == nil
                            ) {
                                withAnimation(AppMotion.slide) {
                                    viewModel.selectedCategory = nil
                                }
                            }

                            ForEach(WarmUpCategory.allCases) { category in
                                FilterPill(
                                    title: category.displayName,
                                    icon: category.icon,
                                    isSelected: viewModel.selectedCategory == category,
                                    color: category.color
                                ) {
                                    withAnimation(AppMotion.slide) {
                                        viewModel.selectedCategory = category
                                    }
                                }
                            }
                        }
                    }

                    exerciseContent
                }
                .padding()
            }
        }
        .navigationTitle("Warm-Ups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            // The ✕ is a sheet affordance; a pushed page closes with Back.
            if !isPushed {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
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

    private func sourceStoryBanner(_ story: Story) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Warming up for")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(story.title.isEmpty ? "Untitled note" : story.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.primary.opacity(0.15))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.primary.opacity(0.35), lineWidth: 0.5)
                }
        }
    }
}
