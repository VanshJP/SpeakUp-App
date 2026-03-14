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
                                        color: difficultyColor(difficulty)
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
                            ForEach(viewModel.passages) { passage in
                                Button {
                                    viewModel.selectedPassage = passage
                                    showingSession = true
                                } label: {
                                    PassageCard(passage: passage)
                                }
                                .buttonStyle(.plain)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
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

    private func difficultyColor(_ difficulty: ReadAloudDifficulty) -> Color {
        switch difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    var color: Color = .teal

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(color)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
        }
        .buttonStyle(.plain)
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

                    Text(passage.difficulty.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(difficultyColor.opacity(0.2))
                        }
                        .foregroundStyle(difficultyColor)
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
                        .foregroundStyle(.teal)
                }
            }
        }
    }

    private var difficultyColor: Color {
        switch passage.difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}
