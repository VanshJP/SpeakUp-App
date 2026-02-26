import SwiftUI
import SwiftData

struct BatchAddPromptsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var selectedCategory: PromptCategory = .personalGrowth
    @State private var selectedDifficulty: PromptDifficulty = .medium

    private var promptLines: [String] {
        inputText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                ScrollView {
                    VStack(spacing: 20) {
                        textInputSection
                        categorySection
                        difficultySection
                        addButton
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Add Multiple Prompts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Text Input

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Prompts", systemImage: "text.bubble")
                .font(.headline)

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $inputText)
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)
                        .font(.body)

                    Divider()

                    HStack {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("One prompt per line")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(promptLines.count) prompt\(promptLines.count == 1 ? "" : "s") detected")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(promptLines.isEmpty ? Color.secondary : Color.teal)
                    }
                }
            }
        }
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Category", systemImage: "folder")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(PromptCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            Haptics.selection()
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 13))
                                .foregroundStyle(selectedCategory == category ? .white : category.color)

                            Text(category.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(selectedCategory == category ? .white : .secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .background {
                            if selectedCategory == category {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(category.color.opacity(0.7))
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("All prompts will be added to this category.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Difficulty

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Difficulty", systemImage: "speedometer")
                .font(.headline)

            GlassCard {
                HStack(spacing: 12) {
                    ForEach(PromptDifficulty.allCases, id: \.self) { difficulty in
                        Button {
                            Haptics.selection()
                            selectedDifficulty = difficulty
                        } label: {
                            Text(difficulty.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(selectedDifficulty == difficulty ? .white : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background {
                                    if selectedDifficulty == difficulty {
                                        Capsule()
                                            .fill(difficulty.color.opacity(0.7))
                                    } else {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                    }
                                }
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            savePrompts()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Add \(promptLines.count) Prompt\(promptLines.count == 1 ? "" : "s")")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal, Color.cyan.opacity(0.85), Color.teal.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .teal.opacity(0.5), radius: 16, y: 4)
            }
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.1), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(promptLines.isEmpty)
        .opacity(promptLines.isEmpty ? 0.5 : 1)
        .padding(.top, 8)
    }

    // MARK: - Save

    private func savePrompts() {
        for line in promptLines {
            let prompt = Prompt(
                id: "user-\(UUID().uuidString)",
                text: line,
                category: selectedCategory.rawValue,
                difficulty: selectedDifficulty,
                isUserCreated: true
            )
            modelContext.insert(prompt)
        }
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }
}

#Preview {
    BatchAddPromptsView()
        .modelContainer(for: [Prompt.self], inMemory: true)
}
