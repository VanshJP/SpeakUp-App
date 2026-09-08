import SwiftUI

enum AppMotion {

    static let snap = Animation.spring(response: 0.3, dampingFraction: 0.7)

    static let settle = Animation.spring(response: 0.4, dampingFraction: 0.85)

    static let slide = Animation.spring(response: 0.38, dampingFraction: 0.82)

    static let reveal = Animation.easeOut(duration: 0.9)

    /// Looping ambient motion.
    /// Never drive this through a bare `withAnimation`. Use `.ambientLoop`,
    /// which skips the state change entirely under Reduce Motion — passing a
    static let ambient = ambient(duration: 0.8)

    static func ambient(duration: Double, autoreverses: Bool = true) -> Animation {
        .easeInOut(duration: duration).repeatForever(autoreverses: autoreverses)
    }
}

// MARK: - Reduce-Motion-aware modifiers

private struct AmbientLoopModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onAppear {
            guard !reduceMotion else { return }
            withAnimation(animation) { action() }
        }
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Starts a looping ambient animation on appear, and does nothing at all
    /// when Reduce Motion is on — leaving the driven value at its resting state.
    func ambientLoop(
        _ animation: Animation = AppMotion.ambient,
        perform action: @escaping () -> Void
    ) -> some View {
        modifier(AmbientLoopModifier(animation: animation, action: action))
    }

    /// `.animation(_:value:)` that goes still under Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}
