import SwiftUI

// MARK: - Compact Tool Tile

/// Compact action tile for secondary tool grids — the Today quick-action
/// recipe (material tile, identity-tinted icon, caption label) extracted so
/// History's Practice Tools grid renders the same dialect instead of a
/// full-width list of rows.
///
/// Label-only by design: wrap in `Button` / `NavigationLink` and apply
/// `.buttonStyle(GlassPressStyle())` at the call site, so tiles can push a
/// destination or run a closure with identical chrome.
struct ToolTileLabel: View {
    let icon: String
    let title: String
    var tint: Color = AppColors.primary

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(height: 22)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.surfaceLift)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColors.cardStroke, lineWidth: 0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

#Preview("Tool Tiles") {
    HStack(spacing: 10) {
        ToolTileLabel(icon: "arrow.left.arrow.right", title: "Compare", tint: AppColors.categoryIndigo)
        ToolTileLabel(icon: "headphones", title: "Listen to Progress", tint: AppColors.categoryPlum)
        ToolTileLabel(icon: "target", title: "Goals", tint: AppColors.categorySage)
    }
    .padding()
    .background(AppBackground())
}
