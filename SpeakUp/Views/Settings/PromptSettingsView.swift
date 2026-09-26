import SwiftUI

struct PromptSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showingAddPrompt = false
    /// Set when a tap tried to switch off the last category: the footer says
    /// why nothing happened instead of the tap vanishing.
    @State private var refusedLastCategory = false

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: AppLayout.chapterSpacing) {
                    GlassRowGroup(dividerInset: Self.dividerInset) {
                        Button {
                            Haptics.light()
                            showingAddPrompt = true
                        } label: {
                            row {
                                Label("Add a custom prompt", systemImage: "plus.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())

                        toggleRow(
                            "Hide answered prompts",
                            icon: "checkmark.circle",
                            isOn: $viewModel.hideAnsweredPrompts,
                            caption: "Prompts you've already recorded stop coming back."
                        )

                        toggleRow(
                            "Practice stories",
                            icon: "book.pages",
                            isOn: $viewModel.storyPracticeEnabled,
                            caption: "Show a random story instead of the daily prompt."
                        )
                    }

                    // The page's main job, so it is open rather than folded
                    // behind a row that had to be tapped first.
                    VStack(alignment: .leading, spacing: 10) {
                        GlassSectionHeader("Categories") {
                            Text("\(viewModel.enabledPromptCategories.count) of \(PromptCategory.allCases.count) on")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        GlassRowGroup(dividerInset: Self.categoryDividerInset) {
                            ForEach(PromptCategory.allCases, id: \.self) { category in
                                categoryRow(category)
                            }
                        }

                        Text(refusedLastCategory
                             ? "Keep at least one category on, so Today always has a prompt to offer."
                             : "Today's prompts come from the categories that are on. To browse or search every prompt, open Library, then Prompts.")
                            .font(.caption)
                            .foregroundStyle(refusedLastCategory ? AppColors.warning : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                .padding()
                .labelStyle(.row)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Prompts")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.hideAnsweredPrompts) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onChange(of: viewModel.storyPracticeEnabled) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .sheet(isPresented: $showingAddPrompt) {
            AddPromptView()
        }
    }

    // MARK: - Rows

    /// Rules start under the row titles: 14pt row inset + the 24pt glyph
    /// column + the 12pt gap of `RowLabelStyle`.
    private static let dividerInset: CGFloat = 50
    /// Category rows lead with a 28pt chip instead of a bare glyph.
    private static let categoryDividerInset: CGFloat = 14 + 28 + 12

    private func categoryRow(_ category: PromptCategory) -> some View {
        let isOn = viewModel.isCategoryEnabled(category)
        return Button {
            if viewModel.toggleCategory(category) {
                Haptics.selection()
                refusedLastCategory = false
            } else {
                Haptics.warning()
                refusedLastCategory = true
            }
        } label: {
            HStack(spacing: 12) {
                IconChip(icon: category.iconName, tint: category.color, size: 28)

                Text(category.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
                    .symbolSwap(isOn)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>, caption: String) -> some View {
        row {
            Toggle(isOn: isOn) {
                Label(title, systemImage: icon)
                    .font(.subheadline)
            }
            .tint(AppColors.primary)
            .accessibilityHint(caption)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 36)
                .accessibilityHidden(true)
        }
    }
}
