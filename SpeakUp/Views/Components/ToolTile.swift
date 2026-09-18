import SwiftUI

// MARK: - Compact Tool Tile

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

// MARK: - Library Category Card

/// The card face, without a gesture. Split out so a caller can wrap it in a
/// `NavigationLink(value:)` — Library's practice cards push a value-based
/// route, because the outcome browser pushes the same routes on top of itself.
struct ToolCategoryCardLabel: View {
    let icon: String
    let title: String
    let meta: String
    /// Optional second line. Practice cards use it for the tool's *format* —
    /// what the next few minutes cost and whether the mic opens — because the
    /// format is the only thing that actually separates the four tools.
    var detail: String? = nil
    var tint: Color = AppColors.primary

    var body: some View {
        GlassCard(cornerRadius: 16, tint: tint.opacity(0.06), padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle().fill(tint.opacity(0.18))
                    }

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(meta)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shared so a Button and a NavigationLink wrapping this face read the
    /// same to VoiceOver.
    static func voiceOverLabel(
        title: String,
        detail: String?,
        meta: String,
        secondary: String?
    ) -> String {
        [title, detail, meta, secondary]
            .compactMap { $0 }
            .joined(separator: ". ")
    }
}

/// Tap-to-act variant, for cards that open a sheet rather than push.
struct ToolCategoryCard: View {
    let icon: String
    let title: String
    let meta: String
    var detail: String? = nil
    var tint: Color = AppColors.primary
    var accessibilityDetail: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            ToolCategoryCardLabel(
                icon: icon,
                title: title,
                meta: meta,
                detail: detail,
                tint: tint
            )
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(
            ToolCategoryCardLabel.voiceOverLabel(
                title: title,
                detail: accessibilityDetail,
                meta: meta,
                secondary: detail
            )
        )
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
