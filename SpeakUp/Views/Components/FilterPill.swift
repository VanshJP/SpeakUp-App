import SwiftUI

/// A selectable filter chip for a horizontal category strip.
///
/// Promoted out of `ReadAloudSelectionView`, where it was private, after
/// `WarmUpListView` and `ConfidenceToolsView` turned out to have re-typed it
/// character for character — same 12/8 padding, same caption fonts, same
/// solid-fill-when-selected treatment. Selection haptics come along for free,
/// which the two inline copies never had.
///
/// This is the *filter* chip. For a non-interactive state or identity badge,
/// use `StatusPill`.
struct FilterPill: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    var color: Color = AppColors.primary
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(
                isSelected ? .regular.tint(color).interactive() : .regular.interactive(),
                in: .capsule
            )
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    HStack(spacing: 8) {
        FilterPill(title: "All", isSelected: true) {}
        FilterPill(title: "Breathing", icon: "wind", isSelected: false) {}
        FilterPill(title: "Vocal", icon: "waveform", isSelected: false, color: AppColors.toolWarmUp) {}
    }
    .padding(40)
    .background(AppBackground())
}
