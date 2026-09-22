import SwiftUI

/// The ✕ on a card the user can wave off: coach notes, friend challenges, the
/// weekly recap, the routine handoff.
///
/// Every transient card closes the same way - the glyph at caption weight in a
/// 44pt target that lays out at 28pt, so the header row it sits in keeps the
/// height of its text. The four cards used to carry three different ✕s (bare,
/// on a disc, and one with a 28pt target).
struct DismissButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .padding(-8)
        .accessibilityLabel(label)
    }
}
