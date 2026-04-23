import SwiftUI

// MARK: - Liquid Glass Effects (iOS 26+)

extension View {
    /// Applies a liquid glass effect with optional tint
    /// This will use the native .glassEffect() modifier on iOS 26+
    @ViewBuilder
    func liquidGlass(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect()
                .overlay {
                    if let tint {
                        Color.clear
                            .background(tint.opacity(0.1))
                    }
                }
        } else {
            self
                .background(.ultraThinMaterial)
        }
    }
    
    /// Applies a prominent liquid glass effect for important UI elements
    @ViewBuilder
    func prominentGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(true))
        } else {
            self.background(.thickMaterial)
        }
    }
}

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
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
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
    func glow(color: Color = .white, radius: CGFloat = 10) -> some View {
        self
            .shadow(color: color.opacity(0.5), radius: radius / 2)
            .shadow(color: color.opacity(0.3), radius: radius)
    }
    
    func pulsingGlow(color: Color = .red, isActive: Bool) -> some View {
        self
            .shadow(color: isActive ? color.opacity(0.6) : .clear, radius: isActive ? 15 : 0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isActive)
    }
}
