import SwiftUI
import SwiftData
import UIKit

struct DrillSessionView: View {
    var viewModel: DrillViewModel
    @Environment(\.dismiss) private var dismiss
    @Query private var userSettings: [UserSettings]
    @State private var showingExitConfirm = false

    var body: some View {
        ZStack {
            // Carries the backdrop over from the drill countdown instead of
            // swapping it out the moment the drill starts.
            RecordingBackdropView(
                backdrop: RecordingBackdrop(rawValue: userSettings.first?.countdownBackdrop ?? 0) ?? .base
            )

            VStack(spacing: 0) {
                topBar

                Spacer()

                if viewModel.isComplete, let result = viewModel.result {
                    DrillResultView(result: result) {
                        if let mode = viewModel.selectedMode {
                            viewModel.startDrill(mode: mode)
                        }
                    } onDone: {
                        viewModel.cleanup()
                        dismiss()
                    }
                } else {
                    drillContent
                }

                Spacer()

                if viewModel.isActive {
                    bottomControls
                }
            }
            .padding()
        }
        .onChange(of: viewModel.isActive) { _, active in
            if active { ChirpPlayer.shared.play(.tick) }
        }
        .onChange(of: viewModel.timeRemaining) { _, remaining in
            if remaining <= 5 && remaining > 0 && viewModel.isActive {
                ChirpPlayer.shared.play(.tick)
            }
        }
        .onChange(of: viewModel.liveFillerCount) { old, new in
            if new > old && viewModel.isActive {
                ChirpPlayer.shared.play(.exhale)
            }
        }
        .onChange(of: viewModel.pauseMarkerActive) { _, active in
            if viewModel.isActive {
                ChirpPlayer.shared.play(active ? .hold : .tick)
            }
        }
        // A drill whose audio/recognition stack failed must not linger as a
        // frozen timer — say why, then leave.
        .alert(
            "Couldn't start the drill",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("Close", role: .cancel) {
                viewModel.cleanup()
                dismiss()
            }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Check microphone and Speech Recognition access, then try again when you're ready.")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                if viewModel.isActive {
                    Haptics.warning()
                    showingExitConfirm = true
                } else {
                    viewModel.cleanup()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .accessibilityLabel("End drill")
            .confirmationDialog(
                "End this drill?",
                isPresented: $showingExitConfirm,
                titleVisibility: .visible
            ) {
                Button("End Drill", role: .destructive) {
                    viewModel.cleanup()
                    dismiss()
                }
                Button("Keep Going", role: .cancel) {}
            } message: {
                Text("Progress in this drill won't be saved.")
            }

            Spacer()

            if let mode = viewModel.selectedMode {
                Text(mode.title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Spacer()

            // Voice activity indicator
            if viewModel.isActive {
                MicLevelPill(isHearing: viewModel.audioService.isHearingInput)
            } else {
                Spacer().frame(width: 44)
            }
        }
        .padding(.top, 50)
    }

    // MARK: - Drill Content

    private var drillContent: some View {
        VStack(spacing: 28) {
            // Mode-specific metric
            if let mode = viewModel.selectedMode {
                Group {
                    switch mode {
                    case .fillerElimination: fillerDisplay
                    case .paceControl:       paceDisplay
                    case .pausePractice:     pauseDisplay
                    case .impromptuSprint, .qaSprint: promptedDisplay
                    case .vocalVariety:      vocalVarietyDisplay
                    case .emphasis:          emphasisDisplay
                    }
                }
                .accessibilityElement(children: .combine)
            }

            TimerView(
                remainingTime: TimeInterval(viewModel.timeRemaining),
                progress: viewModel.progress,
                color: viewModel.selectedMode?.color ?? AppColors.primary,
                isRecording: viewModel.isActive,
                timerLabel: "remaining",
                look: TimerLook(rawValue: userSettings.first?.countdownLook ?? 0) ?? .ring
            )
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 8) {
            // Stop button (same style as RecordButton when recording)
            ZStack {
                if viewModel.isActive {
                    CircularWaveformView(
                        audioLevel: viewModel.audioLevel,
                        style: WaveformStyle(rawValue: userSettings.first?.waveformStyle ?? 0) ?? .rings
                    )
                }

                RecordButton(
                    isRecording: true,
                    style: RecordButtonStyle(rawValue: userSettings.first?.recordButtonStyle ?? 0) ?? .classic
                ) {
                    viewModel.finishDrill()
                }
            }

            Text("Tap to stop")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.bottom, 20)
    }

    // MARK: - Mode Displays

    private var fillerDisplay: some View {
        FillerCounterOverlay(count: viewModel.liveFillerCount)
    }

    private var paceDisplay: some View {
        HStack(spacing: 8) {
            Image(systemName: "speedometer")
                .foregroundStyle(AppColors.info)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(viewModel.liveWPM)) WPM")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(
                        viewModel.liveWPM >= 130 && viewModel.liveWPM <= 170 ? AppColors.success :
                        viewModel.liveWPM >= 115 && viewModel.liveWPM <= 185 ? AppColors.warning : AppColors.error
                    )
                    .contentTransition(.numericText())
                    .animation(.default, value: Int(viewModel.liveWPM))

                Text("target 130–170")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    private var pauseDisplay: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.pauseMarkerActive ? "pause.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.pauseMarkerActive ? AppColors.warning : AppColors.categoryBrandBright)
                    .contentTransition(.symbolEffect(.replace))

                Text(viewModel.pauseMarkerActive ? "PAUSE NOW" : "Keep Speaking")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(viewModel.pauseMarkerActive ? AppColors.warning : .white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().fill(viewModel.pauseMarkerActive ? AppColors.warning.opacity(0.12) : .clear)
                    }
            )
            .animation(.easeInOut(duration: 0.25), value: viewModel.pauseMarkerActive)

            HStack(spacing: 8) {
                ForEach(0..<viewModel.pauseMarkersTotal, id: \.self) { i in
                    Circle()
                        .fill(i < viewModel.pauseMarkersHit ? AppColors.success : Color.white.opacity(0.2))
                        .frame(width: 10, height: 10)
                }

                Text("\(viewModel.pauseMarkersHit)/\(viewModel.pauseMarkersTotal)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pause markers")
            .accessibilityValue("\(viewModel.pauseMarkersHit) of \(viewModel.pauseMarkersTotal)")
        }
    }

    private var promptedDisplay: some View {
        VStack(spacing: 12) {
            if let beat = viewModel.structureBeat {
                Text(beat.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.categoryCopper)
            }

            Text(viewModel.impromptuPrompt)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.liveFillerCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                    Text("\(viewModel.liveFillerCount) filler\(viewModel.liveFillerCount == 1 ? "" : "s")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.warning)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.ultraThinMaterial))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
        )
        .animation(.easeOut(duration: 0.2), value: viewModel.liveFillerCount)
    }

    private var vocalVarietyDisplay: some View {
        VStack(spacing: 12) {
            Text(viewModel.impromptuPrompt)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(AppColors.categoryTeal)
                Text(viewModel.isAnalyzingPitch ? "Scoring pitch…" : "Vary your pitch — glide low to high")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))

            if viewModel.liveEnergySwing > 0 {
                Text(String(format: "Energy swing %.0f dB", viewModel.liveEnergySwing))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
        )
    }

    private var emphasisDisplay: some View {
        VStack(spacing: 12) {
            emphasisPromptText
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "textformat.size")
                    .foregroundStyle(AppColors.categorySage)
                Text("Stress the highlighted word")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))

            if viewModel.liveEnergySwing > 0 {
                Text(String(format: "Swing %.0f dB", viewModel.liveEnergySwing))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
        )
    }

    @ViewBuilder
    private var emphasisPromptText: some View {
        let prompt = viewModel.impromptuPrompt
        let target = viewModel.emphasisTargetWord
        if target.isEmpty || !prompt.contains(target) {
            Text(prompt)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
        } else {
            let parts = prompt.components(separatedBy: target)
            (Text(parts.first ?? "")
                .font(.body.weight(.medium))
                .foregroundColor(.white)
            + Text(target)
                .font(.body.weight(.bold))
                .foregroundColor(AppColors.categorySage)
            + Text(parts.count > 1 ? parts[1] : "")
                .font(.body.weight(.medium))
                .foregroundColor(.white))
        }
    }
}
