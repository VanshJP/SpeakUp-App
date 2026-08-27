import SwiftUI

struct ReadAloudSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ReadAloudViewModel()
    @State private var showingSession = false

    /// When true the list is pushed onto a caller-owned `NavigationStack`
    /// (Library → Tools): no inner stack, and the sheet's ✕ gives way to the
    /// system back button.
    var isPushed: Bool = false

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
                    // Same header grammar as Warm-Ups, Drills, and Calm.
                    Text("Read Aloud")
                        .eyebrowStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ToolPurposeBanner(tool: .readAloud)

                    // Difficulty filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterPill(
                                title: "All",
                                isSelected: viewModel.selectedDifficulty == nil
                            ) {
                                withAnimation(AppMotion.slide) {
                                    viewModel.selectedDifficulty = nil
                                }
                            }

                            ForEach(ReadAloudDifficulty.allCases) { difficulty in
                                FilterPill(
                                    title: difficulty.displayName,
                                    isSelected: viewModel.selectedDifficulty == difficulty,
                                    color: AppColors.difficultyColor(difficulty)
                                ) {
                                    withAnimation(AppMotion.slide) {
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
                                    withAnimation(AppMotion.slide) {
                                        viewModel.selectedCategory = viewModel.selectedCategory == category ? nil : category
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Passage cards
                    if viewModel.selectedDifficulty != nil || viewModel.selectedCategory != nil {
                        Text("\(viewModel.passages.count) of \(DefaultReadAloudPassages.all.count) passages")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

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
                                    Haptics.medium()
                                    viewModel.selectedPassage = passage
                                    showingSession = true
                                } label: {
                                    PassageCard(passage: passage)
                                }
                                .buttonStyle(GlassPressStyle())
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Read Aloud")
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
        .fullScreenCover(isPresented: $showingSession) {
            if let passage = viewModel.selectedPassage {
                ReadAloudSessionView(viewModel: viewModel, passage: passage)
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

                HStack(spacing: 12) {
                    Label("\(passage.wordCount) words", systemImage: "text.word.spacing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Label(estimatedTime, systemImage: "clock")
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

    /// Rough cost at a conversational ~150 wpm, so a passage says what it
    /// takes before you commit.
    private var estimatedTime: String {
        let minutes = Double(passage.wordCount) / 150.0
        if minutes < 1 { return "<1 min" }
        return "≈\(Int(minutes.rounded())) min"
    }
}
