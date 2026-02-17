import SwiftUI

struct ConfidenceToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: ConfidenceCategory = .calming
    @State private var showingExercise: ConfidenceExercise?

    private var exercises: [ConfidenceExercise] {
        DefaultConfidenceExercises.all.filter { $0.category == selectedCategory }
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
                                    Button {
                                        withAnimation { selectedCategory = category }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: category.icon)
                                                .font(.caption2)
                                            Text(category.displayName)
                                                .font(.caption.weight(.medium))
                                        }
                                        .foregroundStyle(selectedCategory == category ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background {
                                            if selectedCategory == category {
                                                Capsule().fill(category.color)
                                            } else {
                                                Capsule().fill(.ultraThinMaterial)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Exercise cards
                        LazyVStack(spacing: 12) {
                            ForEach(exercises) { exercise in
                                Button {
                                    showingExercise = exercise
                                } label: {
                                    GlassCard {
                                        HStack(spacing: 12) {
                                            Image(systemName: exercise.category.icon)
                                                .font(.title2)
                                                .foregroundStyle(exercise.category.color)
                                                .frame(width: 44, height: 44)
                                                .background {
                                                    Circle().fill(exercise.category.color.opacity(0.15))
                                                }

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(exercise.title)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)

                                                Text(exercise.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)

                                                Text("\(exercise.durationMinutes) min")
                                                    .font(.caption2.weight(.medium))
                                                    .foregroundStyle(exercise.category.color)
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Confidence Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $showingExercise) { exercise in
                ConfidenceExerciseView(exercise: exercise)
            }
        }
    }
}
