import SwiftUI

/// Named motion tokens.
///
/// Every value below already existed in the app, retyped at each call site —
/// `.spring(response: 0.3, dampingFraction: 0.7)` was written out independently
/// in the button press style, the recording view, the prompt list, and
/// onboarding. Naming them is what makes motion read as one system instead of
/// several independent guesses that happen to be close.
enum AppMotion {

    /// Press and selection feedback. The shortest motion that still reads as motion.
    static let snap = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Content arriving or rearranging — cards, sheet contents, list inserts.
    static let settle = Animation.spring(response: 0.4, dampingFraction: 0.85)

    /// Matched-geometry travel, e.g. the selected pill in `SectionPicker`.
    static let slide = Animation.spring(response: 0.38, dampingFraction: 0.82)

    /// A value drawing itself in — the score numeral, the radar wedges.
    static let reveal = Animation.easeOut(duration: 0.9)

    /// Looping ambient motion.
    ///
    /// Never drive this through a bare `withAnimation`. Use `.ambientLoop`,
    /// which skips the state change entirely under Reduce Motion — passing a
    /// nil animation instead would park the value at its animated extreme and
    /// leave a pulsing element permanently enlarged, which is worse than no
    /// animation at all.
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
