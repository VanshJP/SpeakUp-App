import SwiftUI

/// Settings → Appearance: glass density + app canvas. Recording Look stays the
/// session-only picker (backdrop / waveform / button / timer); this page owns
/// everything that paints behind the tabs.
struct AppearanceSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView(showsIndicators: false) {
                VStack(spacing: AppLayout.chapterSpacing) {
                    glassSection
                    canvasSection
                    recordingLookLink
                }
                .pageContentInsets()
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .environment(\.glassAppearance, viewModel.glassAppearance)
        .environment(\.appCanvas, viewModel.appCanvas)
    }

    // MARK: - Glass

    private var glassSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Glass", icon: "rectangle.on.rectangle")

            Text("How translucent cards and chips sit on the canvas.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(GlassAppearance.allCases) { appearance in
                    glassOption(appearance)
                }
            }
        }
    }

    private func glassOption(_ appearance: GlassAppearance) -> some View {
        let selected = viewModel.glassAppearance == appearance
        return Button {
            Haptics.selection()
            viewModel.glassAppearance = appearance
            Task { await viewModel.saveSettings() }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: appearance.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? Color(red: 0.07, green: 0.07, blue: 0.08) : .white)

                Text(appearance.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? Color(red: 0.07, green: 0.07, blue: 0.08) : .white)

                Text(appearance.subtitle)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.7) : .secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.94))
                }
            }
            .modifier(AppearanceGlassPreviewChrome(isSelected: selected, appearance: appearance))
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(appearance.displayName) glass. \(appearance.subtitle)")
    }

    // MARK: - Canvas

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Background", icon: "paintpalette.fill")

            Text("The mood behind every tab. Recording has its own backdrop in Recording Look.")
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
                ZStack {
                    AppCanvasView(canvas: canvas, style: .primary, animated: false)
                        .frame(height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if selected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    }
                }

                Text(canvas.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)

                Text(canvas.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16, tint: selected ? AppColors.primary.opacity(0.10) : nil)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(canvas.displayName). \(canvas.subtitle)")
    }

    // MARK: - Recording Look door

    private var recordingLookLink: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Session look", icon: "waveform.circle")

            NavigationLink {
                RecordingLookView(viewModel: viewModel)
            } label: {
                GlassCard(padding: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppColors.categoryBrandBright)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle().fill(AppColors.categoryBrandBright.opacity(0.18))
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recording Look")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Backdrop, waveform, record button, and timer for takes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(GlassPressStyle())
        }
    }
}

/// Selected = solid white (same as filter chips). Idle previews that glass density.
private struct AppearanceGlassPreviewChrome: ViewModifier {
    let isSelected: Bool
    let appearance: GlassAppearance

    func body(content: Content) -> some View {
        Group {
            if isSelected {
                content.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                content
                    .glassEffect(
                        .regular.tint(appearance.glassTint),
                        in: .rect(cornerRadius: 16)
                    )
                    .glassRimStroke(cornerRadius: 16, appearance: appearance)
            }
        }
        .transaction { $0.animation = nil }
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView(viewModel: SettingsViewModel())
    }
}
