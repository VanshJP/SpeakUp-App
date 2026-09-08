import SwiftUI

/// A selectable filter chip for a horizontal category strip.
/// two inline copies never had.
struct FilterPill: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    var color: Color = AppColors.primary
    let action: () -> Void

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
            .modifier(SelectedFilterChrome(isSelected: isSelected))
            .frame(minHeight: AppLayout.minHitTarget)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Selected matches `SectionPicker` (solid white). Idle is quiet glass.
/// The chrome swap itself never animates. Call sites wrap selection in
struct SelectedFilterChrome: ViewModifier {
    let isSelected: Bool

    @Environment(\.glassAppearance) private var glassAppearance

    func body(content: Content) -> some View {
        Group {
            if isSelected {
                content
                    .background { Capsule().fill(Color.white.opacity(0.92)) }
                    .clipShape(Capsule())
            } else {
                content
                    .glassEffect(
                        .regular.tint(glassAppearance.glassTint).interactive(),
                        in: .capsule
                    )
            }
        }
        .transaction { $0.animation = nil }
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
