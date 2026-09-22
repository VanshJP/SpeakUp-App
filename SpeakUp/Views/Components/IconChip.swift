import SwiftUI

/// An identity glyph: the icon at full tint on a disc of the same tint at
/// 0.18 (ui-design-system rule 12).
///
/// One recipe for every row, tile, and card. It was written out by hand at a
/// dozen call sites, at five sizes, two fill strengths, and - in the routine
/// editor and the handoff bar - a rounded square, so the same tool wore a
/// different badge on each screen it appeared on.
struct IconChip: View {
    let icon: String
    var tint: Color = AppColors.primary
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background { Circle().fill(tint.opacity(0.18)) }
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 12) {
        IconChip(icon: "wind", tint: AppColors.toolWarmUp, size: 30)
        IconChip(icon: "mic.fill", size: 36)
        IconChip(icon: "checkmark", tint: AppColors.success, size: 40)
    }
    .padding()
    .background(AppBackground())
}
