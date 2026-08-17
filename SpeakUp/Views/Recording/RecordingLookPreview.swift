import Combine
import SwiftUI

/// Full-screen Recording Look preview. The picker card is a teaser; this is
/// the page the user will actually stand in. Stop lives at the bottom centre
/// and is the only way out — that is the control they will hunt for on the
/// real recording screen, so it has to work here.
struct RecordingLookPreview: View {
    enum Mode {
        case recording
        case countdown
    }

    let mode: Mode
    let waveformStyle: WaveformStyle
    let buttonStyle: RecordButtonStyle
    let countdownLook: CountdownLook
    let backdrop: CountdownBackdrop
    let countdownDuration: Int
    let countdownStyle: CountdownStyle

    @Environment(\.dismiss) private var dismiss
    @State private var elapsedSeconds = 0
    @State private var isPulsing = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var totalSeconds: Int { max(1, countdownDuration) }

    var body: some View {
        ZStack {
            switch mode {
            case .recording:
                recordingCanvas
            case .countdown:
                countdownCanvas
            }
        }
        .ignoresSafeArea()
        .onReceive(timer) { _ in
            guard mode == .countdown else { return }
            elapsedSeconds += 1
            if elapsedSeconds > totalSeconds {
                elapsedSeconds = 0
            }
        }
        .ambientLoop(AppMotion.ambient(duration: 1.0)) { isPulsing = true }
    }

    // MARK: - Recording mock

    private var recordingCanvas: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 0) {
                previewBadge
                    .padding(.top, 56)

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSinceReferenceDate.rounded(.down)) % 60
                    let remaining = TimeInterval(60 - elapsed)
                    TimerView(
                        remainingTime: remaining,
                        totalTime: 60,
                        progress: remaining / 60,
                        color: AppColors.recording,
                        isRecording: true,
                        timerLabel: "remaining"
                    )
                }

                Spacer()

                stopControl
            }
            .padding()
        }
    }

    // MARK: - Countdown mock

    private var countdownCanvas: some View {
        ZStack {
            CountdownBackdropView(backdrop: backdrop)

            VStack(spacing: 20) {
                previewBadge
                    .padding(.top, 56)

                CountdownDial(
                    look: countdownLook,
                    progress: progress,
                    number: displayNumber,
                    isPulsing: isPulsing
                )
                .padding(.top, 12)

                Spacer()

                stopControl
            }
        }
    }

    // MARK: - Stop (bottom middle)

    private var stopControl: some View {
        VStack(spacing: 16) {
            if mode == .recording {
                ZStack {
                    CircularWaveformView(style: waveformStyle, simulated: true)
                    RecordButton(isRecording: true, style: buttonStyle, onTap: stop)
                        .accessibilityLabel("Stop preview")
                }
            } else {
                RecordButton(isRecording: true, style: buttonStyle, onTap: stop)
                    .accessibilityLabel("Stop preview")
            }

            Text("Tap to stop")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
        }
        .padding(.bottom, 50)
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

    private func stop() {
        Haptics.heavy()
        dismiss()
    }

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
