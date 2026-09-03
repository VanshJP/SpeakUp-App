import SwiftUI

// MARK: - Compact Tool Tile

/// Compact action tile for secondary tool grids — the Today quick-action
/// recipe (glass tile, identity-tinted icon, caption label) extracted so
/// History's Review grid renders the same dialect instead of a full-width
/// list of rows.
///
/// Label-only by design: wrap in `Button` / `NavigationLink` and apply
/// `.buttonStyle(GlassPressStyle())` at the call site, so tiles can push a
/// destination or run a closure with identical chrome.
///
/// Color lives in the icon chip, not the tile. Tinting the whole glass slab at
/// 0.25 gave four saturated blocks in a 2x2 grid, which read as louder than
/// the prompt card above them and looked nothing like the same four tools in
/// the Library (`PracticeHubView.toolCategoryCard`, tint 0.06 with a 0.18
/// icon circle). Same tools, same dialect — match that card, not a highlighter.
struct ToolTileLabel: View {
    let icon: String
    let title: String
    var tint: Color = AppColors.primary

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background { Circle().fill(tint.opacity(0.18)) }

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(tint.opacity(0.06)), in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }
}

#Preview("Tool Tiles") {
    HStack(spacing: 10) {
        ToolTileLabel(icon: "arrow.left.arrow.right", title: "Compare", tint: AppColors.categoryIndigo)
        ToolTileLabel(icon: "headphones", title: "Listen back", tint: AppColors.categoryPlum)
        ToolTileLabel(icon: "target", title: "Goals", tint: AppColors.categorySage)
    }
    .padding()
    .background(AppBackground())
}
