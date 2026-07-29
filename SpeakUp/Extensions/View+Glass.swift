import SwiftUI

// MARK: - Shimmer Effect
//
// Wrap a block of shimmering primitives in `ShimmerHost` so one animation +
// zero GeometryReaders drive the entire tree via an environment value. The
// modifier animates a LinearGradient through the content's own bounds via
// UnitPoint — no GeometryReader, no per-instance timing.

private struct ShimmerPhaseKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    fileprivate var shimmerPhase: CGFloat {
        get { self[ShimmerPhaseKey.self] }
        set { self[ShimmerPhaseKey.self] = newValue }
    }
}

struct ShimmerHost<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var phase: CGFloat = 0

    var body: some View {
        content
            .environment(\.shimmerPhase, phase)
            // Under Reduce Motion the sweep never starts and the highlight
            // stays parked off-frame, leaving plain skeleton bars.
            .ambientLoop(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
    }
}

struct ShimmerModifier: ViewModifier {
    @Environment(\.shimmerPhase) private var phase: CGFloat

    func body(content: Content) -> some View {
        let start = UnitPoint(x: -0.6 + phase * 1.6, y: 0.5)
        let end = UnitPoint(x: 0.4 + phase * 1.6, y: 0.5)

        content
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.3), .clear],
                    startPoint: start,
                    endPoint: end
                )
                .mask(content)
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Glow Effect

extension View {
    func pulsingGlow(color: Color = AppColors.recording, isActive: Bool) -> some View {
        self
            .shadow(color: isActive ? color.opacity(0.45) : .clear, radius: isActive ? 15 : 0)
            .motion(AppMotion.ambient, value: isActive)
    }
}
