import SwiftUI

struct WarmUpListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = WarmUpViewModel()
    @State private var showingExercise = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        // Category picker
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(WarmUpCategory.allCases) { category in
                                    Button {
                                        withAnimation { viewModel.selectedCategory = category }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: category.icon)
                                                .font(.caption2)
                                            Text(category.displayName)
                                                .font(.caption.weight(.medium))
                                        }
                                        .foregroundStyle(viewModel.selectedCategory == category ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background {
                                            if viewModel.selectedCategory == category {
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
                            ForEach(viewModel.exercises) { exercise in
                                Button {
                                    viewModel.selectExercise(exercise)
                                    showingExercise = true
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

                                                Text(exercise.instructions)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)

                                                Text("\(exercise.durationSeconds)s")
                                                    .font(.caption2.weight(.medium))
                                                    .foregroundStyle(exercise.category.color)
                                            }

                                            Spacer()

                                            Image(systemName: "play.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(exercise.category.color)
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
            .navigationTitle("Warm-Ups")
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
            .fullScreenCover(isPresented: $showingExercise) {
                WarmUpExerciseView(viewModel: viewModel)
            }
        }
    }
}
