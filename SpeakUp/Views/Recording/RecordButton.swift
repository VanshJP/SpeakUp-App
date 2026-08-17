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
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isRecording)
    }

    // MARK: - Shell

    @ViewBuilder
    private var shell: some View {
        switch style {
        case .classic:
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: buttonSize, height: buttonSize)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.3), lineWidth: 2)
                }

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
                // The glow is the whole point of this one — it reads as lit
                // rather than printed on the dark recording canvas.
                .shadow(color: AppColors.recording.opacity(0.55), radius: 20)

        case .minimal:
            Circle()
                .strokeBorder(.white.opacity(0.45), lineWidth: 1.5)
                .frame(width: buttonSize, height: buttonSize)
        }
    }

    // MARK: - Inner

    @ViewBuilder
    private var inner: some View {
        switch (style, isRecording) {
        case (.classic, true):
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.recording)
                .frame(width: 28, height: 28)

        case (.classic, false):
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.recording.opacity(0.9), AppColors.recording],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: innerSize, height: innerSize)

        case (.ring, true):
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.recording)
                .frame(width: 26, height: 26)

        case (.ring, false):
            Circle()
                .fill(AppColors.recording)
                .frame(width: 46, height: 46)

        case (.orb, true):
            RoundedRectangle(cornerRadius: 7)
                .fill(.white)
                .frame(width: 26, height: 26)

        case (.orb, false):
            // Nothing — the lit orb is the record dot.
            EmptyView()

        case (.minimal, true):
            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.recording)
                .frame(width: 20, height: 20)

        case (.minimal, false):
            Circle()
                .fill(AppColors.recording)
                .frame(width: 26, height: 26)
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
