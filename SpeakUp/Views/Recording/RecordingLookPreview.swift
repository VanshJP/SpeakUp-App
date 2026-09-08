import SwiftUI

/// Full-screen try-on for the Recording Look picker. It plays one session in
/// order — prepare countdown, then recording — on the chosen backdrop, because
/// that is the sequence the user actually stands in. Splitting it into a
/// "countdown preview" and a separate "recording preview" made one picker feel
/// like two unrelated screens.
///
/// The record button is the way out, in both phases, exactly where it sits on
/// the real screen.
struct RecordingLookPreview: View {
    let waveformStyle: WaveformStyle
    let buttonStyle: RecordButtonStyle
    let countdownLook: TimerLook
    let backdrop: RecordingBackdrop
    let countdownDuration: Int
    let countdownStyle: CountdownStyle

    @Environment(\.dismiss) private var dismiss
    @State private var elapsedSeconds = 0
    @State private var isRecording = false
    @State private var isPulsing = false

    /// Sitting through a real 15 s countdown to look at a dial is a waste. Five
    /// seconds reads the style, and a tap skips ahead like the real screen's
    /// Start Now.
    private var totalSeconds: Int { min(max(1, countdownDuration), 5) }

    var body: some View {
        ZStack {
            RecordingBackdropView(backdrop: backdrop)

            VStack(spacing: 0) {
                previewBadge

                if isRecording {
                    recordingPhase
                } else {
                    countdownPhase
                }

                controls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .overlay(alignment: .topLeading) {
            Button(action: exitPreview) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.ultraThinMaterial) }
            }
            .accessibilityLabel("Close preview")
            .padding(.leading, 20)
            .padding(.top, 8)
        }
        .animation(AppMotion.settle, value: isRecording)
        .task(id: isRecording) {
            guard !isRecording else { return }
            while !Task.isCancelled && !isRecording {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, !isRecording else { return }
                elapsedSeconds += 1
                if elapsedSeconds >= totalSeconds {
                    startRecordingPhase()
                    return
                }
            }
        }
        .ambientLoop(AppMotion.ambient(duration: 1.0)) { isPulsing = true }
    }

    // MARK: - Phases

    private var countdownPhase: some View {
        SessionDialSlot(spacing: 20) { diameter in
            TimerDial(
                look: countdownLook,
                progress: progress,
                text: "\(displayNumber)",
                caption: "sec",
                isPulsing: isPulsing,
                diameter: diameter
            )

            phaseLabel("Getting ready")
        }
    }

    private var recordingPhase: some View {
        SessionDialSlot(spacing: 20) { diameter in
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSinceReferenceDate.rounded(.down)) % 60
                let remaining = TimeInterval(60 - elapsed)
                TimerView(
                    remainingTime: remaining,
                    progress: remaining / 60,
                    color: AppColors.recording,
                    isRecording: true,
                    timerLabel: "remaining",
                    look: countdownLook,
                    diameter: diameter
                )
            }

            phaseLabel("Recording")
        }
    }

    private func phaseLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.55))
            .textCase(.uppercase)
            .tracking(1.2)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 16) {
            ZStack {
                if isRecording {
                    CircularWaveformView(style: waveformStyle, simulated: true)
                }

                RecordButton(isRecording: isRecording, style: buttonStyle) {
                    if isRecording {
                        exitPreview()
                    } else {
                        startRecordingPhase()
                    }
                }
                .accessibilityLabel(isRecording ? "Stop preview" : "Skip to recording")
            }

            Text(isRecording ? "Tap to stop" : "Tap to skip ahead")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    private var previewBadge: some View {
        StatusPill(
            text: "Preview",
            color: AppColors.primary,
            glyph: .icon("eye"),
            fillOpacity: 0.2
        )
    }

    // MARK: - Actions

    private func startRecordingPhase() {
        guard !isRecording else { return }
        Haptics.success()
        isRecording = true
    }

    private func exitPreview() {
        Haptics.heavy()
        dismiss()
    }

    // MARK: - Countdown maths

    private var displayNumber: Int {
        switch countdownStyle {
        case .countDown:
            return totalSeconds - elapsedSeconds
        case .countUp:
            return elapsedSeconds
        }
    }

    private var progress: Double {
        switch countdownStyle {
        case .countDown:
            return Double(totalSeconds - elapsedSeconds) / Double(totalSeconds)
        case .countUp:
            return Double(elapsedSeconds) / Double(totalSeconds)
        }
    }
}
