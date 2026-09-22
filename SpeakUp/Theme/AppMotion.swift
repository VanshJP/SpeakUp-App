import SwiftUI

/// Named motion tokens.
///
/// Every value below already existed in the app, retyped at each call site - 
/// `.spring(response: 0.3, dampingFraction: 0.7)` was written out independently
/// in the button press style, the recording view, the prompt list, and
/// onboarding. Naming them is what makes motion read as one system instead of
/// several independent guesses that happen to be close.
enum AppMotion {

    /// Press and selection feedback. The shortest motion that still reads as motion.
    static let snap = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Content arriving or rearranging - cards, sheet contents, list inserts.
    static let settle = Animation.spring(response: 0.4, dampingFraction: 0.85)

    /// Matched-geometry travel, e.g. the selected pill in `SectionPicker`.
    static let slide = Animation.spring(response: 0.38, dampingFraction: 0.82)

    /// A value drawing itself in - the score numeral, the radar wedges.
    static let reveal = Animation.easeOut(duration: 0.9)

    /// Looping ambient motion.
    ///
    /// Never drive this through a bare `withAnimation`. Use `.ambientLoop`,
    /// which skips the state change entirely under Reduce Motion - passing a
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

// MARK: - Intro Reveal

/// A fade-in that fails *visible*.
///
/// The naive version of this (`@State opacity = 0`, raised inside `onAppear`)
/// has bricked two screens now. A first install reported the welcome cover
/// as an orb on an empty background with no button to tap, because content the
/// user cannot proceed without was parked at opacity 0 waiting on a callback
/// and an animation clock. The lesson completion screen hid both of its exits
/// the same way.
///
/// So the resting state here is *shown*. Nothing is hidden until `onAppear`
/// has actually run, which is also the moment responsibility for showing it
/// again is taken on, and a backstop lands the final state with animation off
/// if the reveal is interrupted. Reduce Motion skips the whole dance.
private struct IntroRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let delay: Duration
    let animation: Animation

    private enum Phase { case pending, hidden, shown }

    @State private var phase: Phase = .pending

    func body(content: Content) -> some View {
        content
            .opacity(phase == .hidden ? 0 : 1)
            // Runs before the first frame is committed, so hiding costs no flash.
            .onAppear(perform: begin)
            .task { await landFailSafe() }
    }

    private func begin() {
        guard phase == .pending, !reduceMotion else { return }
        phase = .hidden

        // `try?` rather than `try`: a cancelled sleep must still land the
        // reveal. Bailing out of this task is what leaves content hidden.
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            withAnimation(animation) { phase = .shown }
        }
    }

    private func landFailSafe() async {
        try? await Task.sleep(for: .seconds(2))
        guard phase != .shown else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { phase = .shown }
    }
}

extension View {
    /// Staggered fade-in for arriving hero content. Safe on controls: if the
    /// reveal never runs, the content is simply already there.
    func introReveal(
        delay: Duration = .zero,
        animation: Animation = .easeOut(duration: 0.45)
    ) -> some View {
        modifier(IntroRevealModifier(delay: delay, animation: animation))
    }

    /// Starts a looping ambient animation on appear, and does nothing at all
    /// when Reduce Motion is on - leaving the driven value at its resting state.
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

    /// Marks a control as the origin of a zoom presentation when the host
    /// hands one down. Views that are also built in previews or in contexts
    /// with no presentation pass nil and render untouched.
    @ViewBuilder
    func zoomSource(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
