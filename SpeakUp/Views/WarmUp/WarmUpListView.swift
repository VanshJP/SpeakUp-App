import SwiftUI

struct WarmUpListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = WarmUpViewModel()
    @State private var showingExercise = false

    var sourceStory: Story?

    /// Denominator for every row's duration arc. Scoped to the visible
    /// category, so the arcs re-scale as you filter — within one category the
    /// relative lengths are what's worth comparing.
    private var longestExerciseSeconds: Double {
        Double(viewModel.exercises.map(\.durationSeconds).max() ?? 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                PageScrollView {
                    VStack(spacing: 16) {
                        if let story = sourceStory {
                            sourceStoryBanner(story)
                        }

                        // Category picker
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
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

                        // Exercise cards
                        if viewModel.exercises.isEmpty {
                            EmptyStateCard(
                                icon: "wind",
                                title: "Nothing here",
                                message: "No warm-ups in this category yet. Try another one."
                            )
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.exercises) { exercise in
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
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Warm-Ups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingExercise) {
                WarmUpExerciseView(viewModel: viewModel)
            }
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
