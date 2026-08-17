import SwiftUI

/// Photo-filter style picker for the recording screen. One live preview on top,
/// a strip of thumbnails below, instant swap on tap.
///
/// The preview is the real components — `CircularWaveformView`, `RecordButton`,
/// `CountdownDial` — not stand-ins, so what is picked here is what shows up.
struct RecordingLookView: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var section: Section = .waveform

    nonisolated enum Section: Int, Hashable, Identifiable, CaseIterable {
        case waveform, button, countdown

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .waveform: return "Waveform"
            case .button: return "Button"
            case .countdown: return "Countdown"
            }
        }

        var icon: String {
            switch self {
            case .waveform: return "waveform"
            case .button: return "record.circle"
            case .countdown: return "timer"
            }
        }

        var caption: String {
            switch self {
            case .waveform: return "The ring that reacts to your voice while you record."
            case .button: return "The button you press to start and stop a take."
            case .countdown: return "The dial on the prepare screen before recording starts."
            }
        }
    }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            VStack(spacing: 18) {
                preview

                SectionPicker(
                    sections: Section.allCases,
                    selection: $section,
                    label: { $0.title },
                    icon: { $0.icon },
                    style: .compact
                )
                .padding(.horizontal, 20)

                strip

                Text(section.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
        }
        .navigationTitle("Recording Look")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.waveformStyle) { _, _ in persist() }
        .onChange(of: viewModel.recordButtonStyle) { _, _ in persist() }
        .onChange(of: viewModel.countdownLook) { _, _ in persist() }
    }

    private func persist() {
        guard !viewModel.isSyncing else { return }
        Haptics.selection()
        Task { await viewModel.saveSettings() }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            AppBackground(style: .recording)

            switch section {
            case .waveform, .button:
                CircularWaveformView(style: viewModel.waveformStyle, simulated: true)
                    // Fresh subtree per style so the new one animates in.
                    .id(viewModel.waveformStyle)

                RecordButton(isRecording: true, style: viewModel.recordButtonStyle) {}
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

            case .countdown:
                // A looping 10-second dial, driven by the clock so it needs no
                // timer state of its own.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = 10 - Int(context.date.timeIntervalSinceReferenceDate.rounded(.down)) % 10
                    CountdownDial(
                        look: viewModel.countdownLook,
                        progress: Double(remaining) / 10.0,
                        number: remaining,
                        isPulsing: true
                    )
                }
            }
        }
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppColors.cardStroke, lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .animation(AppMotion.settle, value: section)
    }

    // MARK: - Filter Strip

    @ViewBuilder
    private var strip: some View {
        switch section {
        case .waveform:
            row(WaveformStyle.allCases, selected: viewModel.waveformStyle, name: \.displayName) { style in
                viewModel.waveformStyle = style
            } thumbnail: { style in
                CircularWaveformView(style: style, canvasSize: 84, simulated: true)
            }

        case .button:
            row(RecordButtonStyle.allCases, selected: viewModel.recordButtonStyle, name: \.displayName) { style in
                viewModel.recordButtonStyle = style
            } thumbnail: { style in
                RecordButton(isRecording: false, style: style) {}
                    .scaleEffect(0.62)
                    .allowsHitTesting(false)
            }

        case .countdown:
            row(CountdownLook.allCases, selected: viewModel.countdownLook, name: \.displayName) { look in
                viewModel.countdownLook = look
            } thumbnail: { look in
                CountdownDial(look: look, progress: 0.65, number: 7)
                    .scaleEffect(0.5)
            }
        }
    }

    private func row<Option: Identifiable & Equatable, Thumb: View>(
        _ options: [Option],
        selected: Option,
        name: KeyPath<Option, String>,
        select: @escaping (Option) -> Void,
        @ViewBuilder thumbnail: @escaping (Option) -> Thumb
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(options) { option in
                    let isSelected = option == selected

                    Button {
                        select(option)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(isSelected ? AppColors.glassTintPrimary : AppColors.surfaceLift)

                                thumbnail(option)
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? AppColors.primary : AppColors.cardStroke,
                                        lineWidth: isSelected ? 2 : 1
                                    )
                            }

                            Text(option[keyPath: name])
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AppColors.primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option[keyPath: name])
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}
