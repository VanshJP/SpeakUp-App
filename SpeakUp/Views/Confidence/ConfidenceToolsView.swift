import SwiftUI

struct ConfidenceToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: ConfidenceCategory = .calming
    @State private var showingExercise: ConfidenceExercise?

    private var exercises: [ConfidenceExercise] {
        DefaultConfidenceExercises.all.filter { $0.category == selectedCategory }
    }

    /// Denominator for every row's duration arc, scoped to the visible
    /// category — within one category the relative lengths are what's worth
    /// comparing.
    private var longestExerciseMinutes: Double {
        Double(exercises.map(\.durationMinutes).max() ?? 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        // Category tabs
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ConfidenceCategory.allCases) { category in
                                    FilterPill(
                                        title: category.displayName,
                                        icon: category.icon,
                                        isSelected: selectedCategory == category,
                                        color: category.color
                                    ) {
                                        withAnimation(AppMotion.slide) {
                                            selectedCategory = category
                                        }
                                    }
                                }
                            }
                        }

                        // Exercise cards
                        if exercises.isEmpty {
                            EmptyStateCard(
                                icon: "heart.circle",
                                title: "Nothing here",
                                message: "No exercises in this category yet. Try another one."
                            )
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(exercises) { exercise in
                                    PracticeItemRow(
                                        title: exercise.title,
                                        subtitle: exercise.description,
                                        icon: exercise.category.icon,
                                        tint: exercise.category.color,
                                        durationFraction: PracticeItemRow.fraction(
                                            Double(exercise.durationMinutes),
                                            longest: longestExerciseMinutes
                                        ),
                                        durationLabel: "\(exercise.durationMinutes)m"
                                    ) {
                                        showingExercise = exercise
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Confidence Tools")
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
            .fullScreenCover(item: $showingExercise) { exercise in
                ConfidenceExerciseView(exercise: exercise)
            }
        }
    }
}
