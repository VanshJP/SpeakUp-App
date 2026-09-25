import SwiftUI
import SwiftData
import UIKit

struct PromptWheelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PromptWheelViewModel()

    let onSelectPrompt: (Prompt) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                PageScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        wheelSection

                        if let prompt = viewModel.selectedPrompt {
                            resultCard(prompt)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                // The page's one action surface. Start used to sit in the
                // result card with a white Spin capsule floating over the
                // scroll, which covered it on a small phone and put two
                // primaries on screen.
                .safeAreaBar(edge: .bottom) { actionBar }
            }
            .navigationTitle("Prompt Wheel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
        .onChange(of: viewModel.selectedPrompt?.id) { _, id in
            guard id != nil, let prompt = viewModel.selectedPrompt else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: "Landed on \(prompt.category). \(prompt.text)"
            )
        }
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
            // VoiceOver cannot drag, so it turns the wheel a stop at a time
            // (swipe up or down), which lands like a nudge does.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Prompt wheel")
            .accessibilityValue(markedCategory)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: viewModel.release(projected: viewModel.position + 1)
                case .decrement: viewModel.release(projected: viewModel.position - 1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Spin") { viewModel.spin() }
        }
    }

    /// The category under the marker - what the bowl names and VoiceOver
    /// reads. Only asked for while there are categories.
    private var markedCategory: String {
        viewModel.categories[
            ArcDial<EmptyView, EmptyView>.index(at: viewModel.position, count: viewModel.categories.count)
        ]
    }

    /// The category under the marker while the finger turns the wheel; the
    /// result once it lands. Not named mid-spin - the target is already set
    /// and would give the landing away.
    private var hub: some View {
        let category = markedCategory
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

    private func categoryColor(for category: String) -> Color {
        PromptCategory(rawValue: category)?.color ?? AppColors.primary
    }

    // MARK: - Result Card

    /// The landed prompt, read before you commit. Its action lives in the
    /// bar below.
    private func resultCard(_ prompt: Prompt) -> some View {
        let category = PromptCategory(rawValue: prompt.category)
        let color = categoryColor(for: prompt.category)

        return GlassCard(tint: color.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 12) {
                // Category · difficulty, the eyebrow Today's prompt card
                // wears - not a filled difficulty capsule beside a label.
                HStack(spacing: 5) {
                    Image(systemName: category?.iconName ?? "text.bubble")
                    Text(category?.shortName ?? prompt.category)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("·")
                    Text(prompt.difficulty.displayName)
                        .foregroundStyle(prompt.difficulty.color)
                }
                .eyebrowStyle(color)

                Text(prompt.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Action Bar

    /// Spin until the wheel lands; then the landed prompt's start, with Spin
    /// again as the quieter choice above it. One white primary either way.
    @ViewBuilder
    private var actionBar: some View {
        Group {
            if let prompt = viewModel.selectedPrompt, !viewModel.isSpinning {
                VStack(spacing: 10) {
                    GlassButton(
                        title: "Spin again",
                        icon: "arrow.trianglehead.2.clockwise.rotate.90",
                        style: .secondary,
                        fullWidth: true
                    ) {
                        viewModel.spin()
                    }

                    GlassButton(
                        title: "Use this prompt",
                        icon: "mic.fill",
                        style: .primary,
                        size: .large,
                        fullWidth: true
                    ) {
                        Haptics.medium()
                        onSelectPrompt(prompt)
                    }
                }
            } else {
                let canSpin = !viewModel.isSpinning && !viewModel.categories.isEmpty
                GlassButton(
                    title: viewModel.isSpinning ? "Spinning…" : "Spin the wheel",
                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                    style: .primary,
                    size: .large,
                    fullWidth: true
                ) {
                    viewModel.spin()
                }
                .disabled(!canSpin)
                .opacity(canSpin ? 1 : 0.7)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

#Preview {
    PromptWheelView(onSelectPrompt: { _ in })
        .modelContainer(for: [Prompt.self], inMemory: true)
}
