import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let onTap: () -> Void
    
    @State private var isPressing = false
    @State private var pulseScale: CGFloat = 1.0
    
    private let buttonSize: CGFloat = 80
    private let innerSize: CGFloat = 64
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer pulsing ring (when recording)
                if isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: buttonSize + 20, height: buttonSize + 20)
                        .scaleEffect(pulseScale)
                }
                
                // Outer glass ring
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 2)
                    }
                
                // Inner content
                if isRecording {
                    // Stop icon (rounded square)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red)
                        .frame(width: 28, height: 28)
                } else {
                    // Record icon (circle)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.red.opacity(0.9), Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: innerSize, height: innerSize)
                }
            }
            .scaleEffect(isPressing ? 0.92 : 1.0)
            .animation(.spring(duration: 0.2), value: isPressing)
        }
        .buttonStyle(.plain)
        .pressEvents {
            isPressing = true
        } onRelease: {
            isPressing = false
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isRecording)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startPulseAnimation()
            } else {
                stopPulseAnimation()
            }
        }
    }
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseScale = 1.2
        }
    }
    
    private func stopPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            pulseScale = 1.0
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

// MARK: - Mini Record Button (for other uses)

struct MiniRecordButton: View {
    let isRecording: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)
                
                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.red)
                        .frame(width: 20, height: 20)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Record Button") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 40) {
            RecordButton(isRecording: false, onTap: {})
            RecordButton(isRecording: true, onTap: {})
            
            HStack(spacing: 20) {
                MiniRecordButton(isRecording: false, onTap: {})
                MiniRecordButton(isRecording: true, onTap: {})
            }
        }
    }
}
