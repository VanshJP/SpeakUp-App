import SwiftUI

struct BreathingAnimationView: View {
    let animation: StepAnimation
    let isRunning: Bool
    var duration: TimeInterval = 4.0

    @State private var scale: CGFloat = 0.6

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.teal.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 40,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .scaleEffect(scale)

            // Inner circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.teal.opacity(0.6), .cyan.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .scaleEffect(scale)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                        .scaleEffect(scale)
                }
        }
        .onChange(of: animation) { _, newAnimation in
            guard isRunning else { return }
            animateForPhase(newAnimation)
        }
        .onChange(of: isRunning) { _, running in
            if running {
                animateForPhase(animation)
            }
        }
        .onAppear {
            animateForPhase(animation)
        }
    }

    private func animateForPhase(_ phase: StepAnimation) {
        withAnimation(.easeInOut(duration: duration)) {
            switch phase {
            case .expand:
                scale = 1.0
            case .hold:
                break
            case .contract:
                scale = 0.6
            }
        }
    }
}
