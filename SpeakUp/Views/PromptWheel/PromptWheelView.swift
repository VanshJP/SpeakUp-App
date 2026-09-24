import SwiftUI
import SwiftData

struct PromptWheelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PromptWheelViewModel()

    let onSelectPrompt: (Prompt) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                PageScrollView {
                    VStack(spacing: 24) {
                        headerCaption
                        wheelSection

                        if let prompt = viewModel.selectedPrompt {
                            resultCard(prompt)
                                .transition(.scale.combined(with: .opacity))
                        }

                        Color.clear.frame(height: 96)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)

                VStack {
                    Spacer()
                    spinButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle("Prompt Wheel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }

    // MARK: - Header

    private var headerCaption: some View {
        VStack(spacing: 6) {
            Text("Random discovery")
                .eyebrowStyle(AppColors.primary)

            Text("Spin to land on a category")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Wheel Section

    /// Categories on an `ArcDial` that wraps: flick it, drag it, tap an icon
    /// that is in view, or press Spin.
    @ViewBuilder
    private var wheelSection: some View {
        if viewModel.categories.isEmpty {
            Text("No prompt categories are turned on. Pick some in Settings → Prompts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            ArcDial(
                count: viewModel.categories.count,
                position: viewModel.position,
                wraps: true,
                step: 30,
                tint: { categoryColor(for: viewModel.categories[$0]) },
                glyph: { index in
                    let category = viewModel.categories[index]
                    Image(systemName: PromptCategory(rawValue: category)?.iconName ?? "text.bubble")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(categoryColor(for: category))
                        .frame(width: 36, height: 36)
                },
                hub: { hub },
                onScrub: { viewModel.scrub(to: $0) },
                onRelease: { viewModel.release(projected: $0) }
            )
            // Full bleed: the wheel is meant to run off the screen.
            .padding(.horizontal, -20)
            .allowsHitTesting(!viewModel.isSpinning)
            .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isSpinning)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Prompt wheel")
            .accessibilityValue(viewModel.selectedCategory ?? "")
            .accessibilityHint("Swipe sideways to spin")
            .accessibilityAction(named: "Spin") { viewModel.spin() }
        }
    }

    /// The category under the marker while the finger turns the wheel; the
    /// result once it lands. Not named mid-spin - the target is already set
    /// and would give the landing away.
    private var hub: some View {
        let category = viewModel.categories[
            ArcDial<EmptyView, EmptyView>.index(at: viewModel.position, count: viewModel.categories.count)
        ]
        return VStack(spacing: 4) {
            Text(viewModel.isSpinning ? "Spinning…" : category)
                .font(.title3.weight(.bold))
                .foregroundStyle(viewModel.isSpinning ? .white.opacity(0.7) : categoryColor(for: category))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)

            Text(viewModel.selectedCategory != nil ? "Landed" : "\(viewModel.prompts.count) prompts ready")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Color Helpers

    private var segmentColors: [Color] {
        viewModel.categories.map { categoryColor(for: $0) }
    }

    private func categoryColor(for category: String) -> Color {
        PromptCategory(rawValue: category)?.color ?? AppColors.primary
    }
    
    // MARK: - Result Card

    private func resultCard(_ prompt: Prompt) -> some View {
        let color = categoryColor(for: prompt.category)

        return GlassCard(tint: color.opacity(0.10), accentBorder: color.opacity(0.35)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: PromptCategory(rawValue: prompt.category)?.iconName ?? "text.bubble")
                        .font(.caption.weight(.semibold))
                    Text(prompt.category)
                        .font(.caption.weight(.semibold))

                    Spacer()

                    StatusPill.difficulty(prompt.difficulty)
                }
                .foregroundStyle(color)

                Text(prompt.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                GlassButton(
                    title: "Use this prompt",
                    icon: "mic.fill",
                    style: .primary,
                    fullWidth: true
                ) {
                    Haptics.medium()
                    onSelectPrompt(prompt)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Spin Button

    private var spinButton: some View {
        GlassButton(
            title: viewModel.isSpinning ? "Spinning…" : "Spin the wheel",
            icon: "arrow.trianglehead.2.clockwise.rotate.90",
            style: .primary,
            size: .large,
            isLoading: false,
            fullWidth: true
        ) {
            viewModel.spin()
        }
        .disabled(viewModel.isSpinning)
        .opacity(viewModel.isSpinning ? 0.7 : 1)
    }
}

#Preview {
    PromptWheelView(onSelectPrompt: { _ in })
        .modelContainer(for: [Prompt.self], inMemory: true)
}
