import SwiftUI

/// A selectable filter chip for a horizontal category strip.
///
/// Promoted out of `ReadAloudSelectionView`, where it was private, after
/// `WarmUpListView` and `ConfidenceToolsView` turned out to have re-typed it
/// character for character. Selection haptics come along for free, which the
/// two inline copies never had.
///
/// Selected is the same solid white pill `FilterChip` / `SectionPicker` use —
/// a full-tint glass capsule was the louder dialect, and two filter systems
/// on neighboring pages then disagreed. Identity color lives on the idle
/// glyph. For a non-interactive state or identity badge, use `StatusPill`.
struct FilterPill: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    var color: Color = AppColors.primary
    let action: () -> Void

    /// Ink on a selected (solid white) chip. Same token as `FilterChip`.
    private static let onLight = Color(red: 0.07, green: 0.07, blue: 0.08)

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Self.onLight) : AnyShapeStyle(color))
                }
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Self.onLight) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: AppLayout.minHitTarget)
            .contentShape(Capsule())
            .modifier(SelectedFilterChrome(isSelected: isSelected))
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Selected matches `SectionPicker` (solid white). Idle is quiet glass.
struct SelectedFilterChrome: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content
                .background { Capsule().fill(Color.white.opacity(0.92)) }
                .clipShape(Capsule())
        } else {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        }
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
