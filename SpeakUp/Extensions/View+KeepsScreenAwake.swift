import SwiftUI
import UIKit

// MARK: - Keep Screen Awake

extension View {
    /// Holds the screen awake while `isActive`, and lets it sleep again when
    /// the view goes away.
    ///
    /// Every timed practice screen needs this. Reading a passage, running a
    /// breathing round or talking through a drill is a minute or more of
    /// speaking without touching the glass, which is exactly what Auto-Lock
    /// waits for. A Read Aloud past the thirty-second mark used to dim, lock,
    /// and take the microphone with it.
    func keepsScreenAwake(_ isActive: Bool) -> some View {
        modifier(KeepsScreenAwake(isActive: isActive))
    }
}

private struct KeepsScreenAwake: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive, initial: true) { _, active in
                UIApplication.shared.isIdleTimerDisabled = active
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }
}
