import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView(showsIndicators: false) {
                VStack(spacing: AppLayout.chapterSpacing) {
                    glassSection
                    canvasSection
                }
                .pageContentInsets()
            }
        }
        .navigationTitle("App Look")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .environment(\.glassAppearance, viewModel.glassAppearance)
        .environment(\.appCanvas, viewModel.appCanvas)
    }

    // MARK: - Glass

    private var glassSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Glass", icon: "rectangle.on.rectangle")

            Text("How translucent cards sit on the canvas.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(GlassAppearance.allCases) { appearance in
                    glassOption(appearance)
                }
            }
        }
    }

    /// Each option is a miniature page: the current canvas, a sample plate
    /// using that glass, then the name. Selected is a ring — never a solid
    /// white fill that hides the thing you are choosing.
    private func glassOption(_ appearance: GlassAppearance) -> some View {
        let selected = viewModel.glassAppearance == appearance
        return Button {
            Haptics.selection()
            viewModel.glassAppearance = appearance
            Task { await viewModel.saveSettings() }
        } label: {
            VStack(spacing: 10) {
                glassPreview(for: appearance)

                VStack(spacing: 2) {
                    Text(appearance.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(appearance.previewCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.tint(appearance.glassTint), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? Color.white.opacity(0.92) : Color.white.opacity(0.14),
                        lineWidth: selected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transaction { $0.animation = nil }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(appearance.displayName) glass. \(appearance.subtitle)")
    }

    private func glassPreview(for appearance: GlassAppearance) -> some View {
        ZStack(alignment: .bottom) {
            AppCanvasView(canvas: viewModel.appCanvas, style: .primary)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 7) {
                Capsule()
                    .fill(Color.white.opacity(appearance.tintLift * 4.5 + 0.18))
                    .frame(width: 44, height: 5)
                Capsule()
                    .fill(Color.white.opacity(appearance.tintLift * 3.0 + 0.10))
                    .frame(width: 68, height: 5)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(appearance.tintLift * 1.8))
            }
            .glassEffect(
                .regular.tint(appearance.glassTint),
                in: .rect(cornerRadius: 11)
            )
            .padding(10)
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .transaction { $0.animation = nil }
    }

    // MARK: - Canvas

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Background", icon: "paintpalette.fill")

            Text("The mood behind every tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(AppCanvas.allCases) { canvas in
                    canvasOption(canvas)
                }
            }
        }
    }

    private func canvasOption(_ canvas: AppCanvas) -> some View {
        let selected = viewModel.appCanvas == canvas
        return Button {
            Haptics.selection()
            viewModel.appCanvas = canvas
            Task { await viewModel.saveSettings() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                canvasPreview(canvas, selected: selected)

                Text(canvas.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(canvas.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 32, alignment: .top)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16, tint: selected ? AppColors.primary.opacity(0.10) : nil)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(canvas.displayName). \(canvas.subtitle)")
    }

    private func canvasPreview(_ canvas: AppCanvas, selected: Bool) -> some View {
        ZStack {
            AppCanvasView(canvas: canvas, style: .primary)
                .allowsHitTesting(false)

            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView(viewModel: SettingsViewModel())
    }
}
