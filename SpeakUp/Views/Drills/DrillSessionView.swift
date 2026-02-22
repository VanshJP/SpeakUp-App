import SwiftUI

struct DrillSessionView: View {
    var viewModel: DrillViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

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
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                viewModel.cleanup()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial))
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
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.audioLevel > -40 ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.15), value: viewModel.audioLevel > -40)

                    Text(viewModel.audioLevel > -40 ? "Speaking" : "Silent")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(viewModel.audioLevel > -40 ? .white : .white.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
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
                switch mode {
                case .fillerElimination: fillerDisplay
                case .paceControl:       paceDisplay
                case .pausePractice:     pauseDisplay
                case .impromptuSprint:   impromptuDisplay
                }
            }

            TimerView(
                remainingTime: TimeInterval(viewModel.timeRemaining),
                totalTime: TimeInterval(viewModel.selectedMode?.defaultDurationSeconds ?? 60),
                progress: viewModel.progress,
                color: viewModel.selectedMode?.color ?? .teal,
                isRecording: viewModel.isActive,
                timerLabel: "remaining"
            )
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 8) {
            // Stop button (same style as RecordButton when recording)
            ZStack {
                if viewModel.isActive {
                    CircularWaveformView(audioLevel: viewModel.audioLevel)
                }

                RecordButton(isRecording: true) {
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
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(viewModel.liveWPM)) WPM")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(
                        viewModel.liveWPM >= 130 && viewModel.liveWPM <= 170 ? .green :
                        viewModel.liveWPM >= 115 && viewModel.liveWPM <= 185 ? .yellow : .red
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
                    .foregroundStyle(viewModel.pauseMarkerActive ? .yellow : .purple)
                    .contentTransition(.symbolEffect(.replace))

                Text(viewModel.pauseMarkerActive ? "PAUSE NOW" : "Keep Speaking")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(viewModel.pauseMarkerActive ? .yellow : .white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().fill(viewModel.pauseMarkerActive ? Color.yellow.opacity(0.12) : .clear)
                    }
            )
            .animation(.easeInOut(duration: 0.25), value: viewModel.pauseMarkerActive)

            HStack(spacing: 8) {
                ForEach(0..<viewModel.pauseMarkersTotal, id: \.self) { i in
                    Circle()
                        .fill(i < viewModel.pauseMarkersHit ? Color.green : Color.white.opacity(0.2))
                        .frame(width: 10, height: 10)
                }

                Text("\(viewModel.pauseMarkersHit)/\(viewModel.pauseMarkersTotal)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var impromptuDisplay: some View {
        VStack(spacing: 12) {
            Text(viewModel.impromptuPrompt)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.liveFillerCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("\(viewModel.liveFillerCount) filler\(viewModel.liveFillerCount == 1 ? "" : "s")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
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
}
