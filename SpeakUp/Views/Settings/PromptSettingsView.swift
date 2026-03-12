import SwiftUI
import SwiftData

struct PromptSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showingCategories = false
    @State private var showingAddPrompt = false

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 0) {
                            Button {
                                showingAddPrompt = true
                            } label: {
                                HStack {
                                    Label("Add Custom Prompt", systemImage: "plus.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(minHeight: 40)
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.vertical, 8)

                            Toggle(isOn: $viewModel.hideAnsweredPrompts) {
                                Label("Hide Answered Prompts", systemImage: "checkmark.circle")
                                    .font(.subheadline)
                            }
                            .tint(.teal)
                            .frame(minHeight: 40)

                            Divider().padding(.vertical, 8)

                            Button {
                                Haptics.light()
                                withAnimation(.spring(duration: 0.3)) {
                                    showingCategories.toggle()
                                }
                            } label: {
                                HStack {
                                    Label("Prompt Categories", systemImage: "folder")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(viewModel.enabledPromptCategories.count) selected")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .rotationEffect(.degrees(showingCategories ? 90 : 0))
                                }
                                .frame(minHeight: 40)
                            }
                            .buttonStyle(.plain)

                            if showingCategories {
                                VStack(spacing: 0) {
                                    ForEach(PromptCategory.allCases, id: \.self) { category in
                                        Divider().padding(.vertical, 6)

                                        Button {
                                            Haptics.selection()
                                            viewModel.toggleCategory(category)
                                        } label: {
                                            HStack {
                                                Image(systemName: category.iconName)
                                                    .foregroundStyle(category.color)
                                                    .frame(width: 24)
                                                Text(category.displayName)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                if viewModel.isCategoryEnabled(category) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(.teal)
                                                } else {
                                                    Image(systemName: "circle")
                                                        .foregroundStyle(.tertiary)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 4)
                                .transition(.opacity)
                            }
                        }
                    }

                    Text("Browse, search, and manage all prompts. Add your own custom prompts to practice with.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Prompts")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.hideAnsweredPrompts) { _, _ in
            Task { await viewModel.saveSettings() }
        }
        .sheet(isPresented: $showingAddPrompt) {
            AddPromptView()
        }
    }
}
