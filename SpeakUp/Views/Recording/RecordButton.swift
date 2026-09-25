import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    var style: RecordButtonStyle = .classic
    let onTap: () -> Void

    @State private var isPressing = false

    private let buttonSize: CGFloat = 80
    private let innerSize: CGFloat = 64

    var body: some View {
        Button(action: onTap) {
            ZStack {
                shell
                inner
            }
            .frame(width: buttonSize, height: buttonSize)
            .scaleEffect(isPressing ? 0.92 : 1.0)
            .animation(.spring(duration: 0.2), value: isPressing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .pressEvents {
            isPressing = true
        } onRelease: {
            isPressing = false
        }
        // No haptic of its own: every host's start and stop already buzzes
        // (`RecordingViewModel.startRecording` / `stopRecording`), and a
        // second one here made each press feel like two.
    }

    // MARK: - Shell

    @ViewBuilder
    private var shell: some View {
        switch style {
        case .classic:
            // Liquid Glass, which lights its own edge - no material fill and
            // no painted rim on top of it (ui-design-system rule 13).
            Color.clear
                .frame(width: buttonSize, height: buttonSize)
                .glassEffect(.regular, in: .circle)

        case .ring:
            Circle()
                .strokeBorder(AppColors.recording.opacity(0.85), lineWidth: 6)
                .frame(width: buttonSize, height: buttonSize)

        case .orb:
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.recording, AppColors.recording.opacity(0.35)],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 2,
                        endRadius: buttonSize * 0.85
                    )
                )
                .frame(width: buttonSize, height: buttonSize)
                .shadow(color: AppColors.recording.opacity(0.55), radius: 20)

        case .minimal:
            Circle()
                .strokeBorder(.white.opacity(0.45), lineWidth: 1.5)
                .frame(width: buttonSize, height: buttonSize)
        }
    }

    // MARK: - Inner

    /// One shape whose size and corner radius animate, so the dot morphs into
    /// the stop square the way Camera's shutter does. Separate `Circle` and
    /// `RoundedRectangle` branches could only cross-fade.
    private var inner: some View {
        let spec = innerSpec
        return RoundedRectangle(cornerRadius: spec.radius, style: .circular)
            .fill(spec.fill)
            .frame(width: spec.side, height: spec.side)
            .motion(.spring(duration: 0.38, bounce: 0.3), value: isRecording)
    }

    private var innerSpec: (side: CGFloat, radius: CGFloat, fill: AnyShapeStyle) {
        let red = AnyShapeStyle(AppColors.recording)
        switch (style, isRecording) {
        case (.classic, true):
            return (28, 8, red)
        case (.classic, false):
            return (innerSize, innerSize / 2, AnyShapeStyle(
                LinearGradient(
                    colors: [AppColors.recording.opacity(0.9), AppColors.recording],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ))
        case (.ring, true):
            return (26, 6, red)
        case (.ring, false):
            return (46, 23, red)
        case (.orb, true):
            return (26, 7, AnyShapeStyle(.white))
        case (.orb, false):
            // Nothing - the lit orb is the record dot.
            return (0, 0, AnyShapeStyle(.white))
        case (.minimal, true):
            return (20, 4, red)
        case (.minimal, false):
            return (26, 13, red)
        }
    }
}

// MARK: - Press Events Modifier

struct PressEventsModifier: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onRelease() }
            )
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventsModifier(onPress: onPress, onRelease: onRelease))
    }
}

#Preview("Record Button") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            RecordButton(isRecording: false, onTap: {})
            RecordButton(isRecording: true, onTap: {})
        }
    }
}
