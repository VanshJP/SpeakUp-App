import SwiftUI

struct ReadAloudSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ReadAloudViewModel()
    @State private var showingSession = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        Text("Read the passage out loud. We'll track your accuracy in real time.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        // Difficulty filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterPill(
                                    title: "All",
                                    isSelected: viewModel.selectedDifficulty == nil
                                ) {
                                    withAnimation { viewModel.selectedDifficulty = nil }
                                }

                                ForEach(ReadAloudDifficulty.allCases) { difficulty in
                                    FilterPill(
                                        title: difficulty.displayName,
                                        isSelected: viewModel.selectedDifficulty == difficulty,
                                        color: AppColors.difficultyColor(difficulty)
                                    ) {
                                        withAnimation {
                                            viewModel.selectedDifficulty = viewModel.selectedDifficulty == difficulty ? nil : difficulty
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Category filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ReadAloudCategory.allCases) { category in
                                    FilterPill(
                                        title: category.displayName,
                                        icon: category.icon,
                                        isSelected: viewModel.selectedCategory == category
                                    ) {
                                        withAnimation {
                                            viewModel.selectedCategory = viewModel.selectedCategory == category ? nil : category
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Passage cards
                        LazyVStack(spacing: 12) {
                            if viewModel.passages.isEmpty {
                                EmptyStateCard(
                                    icon: "text.book.closed",
                                    title: "Nothing here",
                                    message: "No passages match these filters. Try clearing one."
                                )
                            } else {
                                ForEach(viewModel.passages) { passage in
                                    Button {
                                        viewModel.selectedPassage = passage
                                        showingSession = true
                                    } label: {
                                        PassageCard(passage: passage)
                                    }
                                    .buttonStyle(GlassPressStyle())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Read Aloud")
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
            .fullScreenCover(isPresented: $showingSession) {
                if let passage = viewModel.selectedPassage {
                    ReadAloudSessionView(viewModel: viewModel, passage: passage)
                }
            }
        }
    }

}

// MARK: - Passage Card

private struct PassageCard: View {
    let passage: ReadAloudPassage

    var body: some View {
        GlassCard(tint: difficultyColor.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(passage.category.displayName, systemImage: passage.category.icon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    StatusPill(
                        text: passage.difficulty.displayName,
                        color: difficultyColor,
                        fillOpacity: 0.2
                    )
                }

                Text(passage.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(passage.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack {
                    Label("\(passage.wordCount) words", systemImage: "text.word.spacing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
    }

    private var difficultyColor: Color { AppColors.difficultyColor(passage.difficulty) }
}
