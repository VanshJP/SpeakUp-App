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
/// `NavigationLink(value:)` - Library's practice cards push a value-based
/// route, because the outcome browser pushes the same routes on top of itself.
///
/// Every line reserves its space whether or not it is filled, so a grid of
/// these is a matrix rather than a ragged wall: the meta and format lines
/// wrap to different counts per tool, and a `LazyVGrid` sizes each row to its
/// own tallest cell, which is what made Warm-Ups tower over Drills and the
/// Review pair sit shorter than the Practice pair above it.
struct ToolCategoryCardLabel: View {
    let icon: String
    let title: String
    let meta: String
    /// Optional second line. Practice cards use it for the tool's *format* - 
    /// what the next few minutes cost and whether the mic opens - because the
    /// format is the only thing that actually separates the four tools.
    /// The slot is drawn either way so the Review grid lines up with Practice.
    var detail: String? = nil
    var tint: Color = AppColors.primary

    var body: some View {
        GlassCard(cornerRadius: 16, tint: tint.opacity(0.06), padding: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(tint.opacity(0.18))
                    }

                Spacer(minLength: 12)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(meta)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 3)

                Text(detail ?? "")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2, reservesSpace: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
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
