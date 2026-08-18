import SwiftUI

/// Recording Look picker: one live preview of the session on top, every option
/// laid out in grids underneath.
///
/// It used to be four tabbed sections, each a horizontal filter strip, and the
/// preview changed meaning depending on which tab you were in — sometimes a
/// countdown, sometimes a recording. With twenty options across four groups,
/// most of them sat off-screen and the preview never said which screen you were
/// looking at. Now nothing hides behind a swipe, and the preview shows both
/// halves of a real session at once, on the backdrop you picked.
///
/// The preview is the real components — `CircularWaveformView`, `RecordButton`,
/// `TimerDial`, `RecordingBackdropView` — not stand-ins.
struct RecordingLookView: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var showingPreview = false

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    hero

                    GlassButton(
                        title: "Play Preview",
                        icon: "play.fill",
                        style: .primary,
                        size: .medium,
                        fullWidth: true
                    ) {
                        openPreview()
                    }
                    .accessibilityHint("Plays a full-screen countdown and recording. The record button stops it.")
                    .padding(.horizontal, 20)

                    group(
                        title: "Background",
                        caption: "Behind the countdown and the whole recording.",
                        options: RecordingBackdrop.allCases,
                        selected: viewModel.recordingBackdrop,
                        name: \.displayName
                    ) { backdrop in
                        viewModel.recordingBackdrop = backdrop
                    } thumbnail: { backdrop in
                        RecordingBackdropView(backdrop: backdrop, animated: false)
                            .frame(width: 320, height: 320)
                            .scaleEffect(0.25)
                    }

                    group(
                        title: "Waveform",
                        caption: "The ring that reacts to your voice while you record.",
                        options: WaveformStyle.allCases,
                        selected: viewModel.waveformStyle,
                        name: \.displayName
                    ) { style in
                        viewModel.waveformStyle = style
                    } thumbnail: { style in
                        if style == .off {
                            // Off draws nothing, and a blank tile reads as a
                            // broken thumbnail rather than a choice.
                            Image(systemName: "waveform.slash")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.55))
                        } else {
                            CircularWaveformView(style: style, canvasSize: 76, simulated: true)
                        }
                    }

                    group(
                        title: "Record Button",
                        caption: "The button you press to start and stop a take.",
                        options: RecordButtonStyle.allCases,
                        selected: viewModel.recordButtonStyle,
                        name: \.displayName
                    ) { style in
                        viewModel.recordButtonStyle = style
                    } thumbnail: { style in
                        RecordButton(isRecording: false, style: style) {}
                            .scaleEffect(0.62)
                    }

                    group(
                        title: "Timer",
                        caption: "The dial on the prepare screen and the clock while you record.",
                        options: TimerLook.allCases,
                        selected: viewModel.countdownLook,
                        name: \.displayName
                    ) { look in
                        viewModel.countdownLook = look
                    } thumbnail: { look in
                        TimerDial(look: look, progress: 0.65, text: "7", caption: "sec")
                            .scaleEffect(0.5)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Recording Look")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.waveformStyle) { _, _ in persist() }
        .onChange(of: viewModel.recordButtonStyle) { _, _ in persist() }
        .onChange(of: viewModel.countdownLook) { _, _ in persist() }
        .onChange(of: viewModel.recordingBackdrop) { _, _ in persist() }
        .fullScreenCover(isPresented: $showingPreview) {
            RecordingLookPreview(
                waveformStyle: viewModel.waveformStyle,
                buttonStyle: viewModel.recordButtonStyle,
                countdownLook: viewModel.countdownLook,
                backdrop: viewModel.recordingBackdrop,
                countdownDuration: viewModel.countdownDuration.rawValue,
                countdownStyle: viewModel.countdownStyle
            )
        }
    }

    private func persist() {
        guard !viewModel.isSyncing else { return }
        Haptics.selection()
        Task { await viewModel.saveSettings() }
    }

    private func openPreview() {
        Haptics.medium()
        showingPreview = true
    }

    // MARK: - Hero

    /// Both halves of a session in one card — the countdown dial and the
    /// recording ring, on the chosen backdrop — so every pick below is visible
    /// without switching modes.
    private var hero: some View {
        ZStack {
            RecordingBackdropView(backdrop: viewModel.recordingBackdrop)

            VStack(spacing: 18) {
                heroPiece("Timer") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = 10 - Int(context.date.timeIntervalSinceReferenceDate.rounded(.down)) % 10
                        TimerDial(
                            look: viewModel.countdownLook,
                            progress: Double(remaining) / 10.0,
                            text: "\(remaining)",
                            caption: "sec",
                            isPulsing: true
                        )
                        .scaleEffect(0.78)
                        .frame(width: 118, height: 118)
                    }
                }

                heroPiece("Recording") {
                    ZStack {
                        CircularWaveformView(style: viewModel.waveformStyle, canvasSize: 130, simulated: true)
                            // Fresh subtree per style so the new one animates in.
                            .id(viewModel.waveformStyle)

                        RecordButton(isRecording: true, style: viewModel.recordButtonStyle) {}
                            .scaleEffect(130.0 / 220.0)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        // minHeight, not a hard height: the two labels grow with Dynamic Type
        // and would otherwise push the recording half under the clip.
        .frame(minHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppColors.cardStroke, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { openPreview() }
        .padding(.horizontal, 20)
        .animation(AppMotion.settle, value: viewModel.recordingBackdrop)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of your recording look")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Plays a full-screen countdown and recording. The record button stops it.")
    }

    private func heroPiece<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1.0)

            content()
        }
    }

    // MARK: - Option Groups

    private func group<Option: Identifiable & Equatable, Thumb: View>(
        title: String,
        caption: String,
        options: [Option],
        selected: Option,
        name: KeyPath<Option, String>,
        select: @escaping (Option) -> Void,
        @ViewBuilder thumbnail: @escaping (Option) -> Thumb
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Adaptive, not a fixed column count: the tiles are a hard 76pt so
            // an oversized thumbnail (the backdrop renders at 320pt and gets
            // clipped) can't stretch the grid.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 76), spacing: 12)],
                spacing: 14
            ) {
                ForEach(options) { option in
                    let isSelected = option == selected

                    Button {
                        select(option)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(isSelected ? AppColors.glassTintPrimary : AppColors.surfaceLift)

                                // Thumbnails are scaled-down full-size views, so
                                // their layout stays big (the backdrop is 320pt,
                                // the dial 150pt) even though they draw small.
                                // Clamped and made inert here or the last tile in
                                // a grid — drawn on top — swallows taps meant for
                                // the row above it.
                                thumbnail(option)
                                    .frame(width: 76, height: 76)
                                    .allowsHitTesting(false)
                            }
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? AppColors.primary : AppColors.cardStroke,
                                        lineWidth: isSelected ? 2 : 1
                                    )
                            }

                            Text(option[keyPath: name])
                                .font(.caption2.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AppColors.primary : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                        }
                        // Pins the tap target to this tile's own bounds.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option[keyPath: name])
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.horizontal, 20)
    }
}
