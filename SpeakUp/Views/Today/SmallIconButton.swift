import SwiftUI

// MARK: - Small Icon Button (for card actions)

/// Circular icon control. 28pt glass face, 44pt hit target - same visual
/// height as `StatusPill` / `DurationPill` in prompt chrome.
struct SmallIconButton: View {
    let icon: String
    /// VoiceOver / Voice Control name - required so icon-only control is not silent.
    var label: String
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: icon) {
            Haptics.light()
            action()
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .glassEffect(.regular.interactive(), in: .circle)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .buttonStyle(GlassPressStyle())
    }
}
