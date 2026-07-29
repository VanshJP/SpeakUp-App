import SwiftUI

/// A small tinted capsule carrying one word of state or identity.
///
/// Covers both jobs the app was doing with separate hand-written copies: a
/// *status* readout ("Done", "Active", "Good") that reports how something is
/// going, and an *identity* badge ("Hard", "Storytelling") that names what
/// something is. They differ only in fill weight — identity badges sit next to
/// body text and need to hold their own, status pills sit inside a card that is
/// already carrying the emphasis.
struct StatusPill: View {
    enum Glyph: Equatable {
        case none
        case dot
        case icon(String)
    }

    let text: String
    let color: Color
    var glyph: Glyph = .none
    /// 0.12 for status readouts, 0.2 for identity badges.
    var fillOpacity: Double = 0.12

    var body: some View {
        HStack(spacing: 4) {
            switch glyph {
            case .none:
                EmptyView()
            case .dot:
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            case .icon(let name):
                Image(systemName: name)
                    .font(.system(size: 8, weight: .bold))
            }

            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(fillOpacity)))
    }
}

// MARK: - Convenience

extension StatusPill {
    /// Identity badge for a prompt difficulty. Replaces the standalone
    /// `DifficultyBadge` and the read-aloud copy that reached for raw
    /// `.green`/`.orange`/`.red` instead of the tuned palette.
    static func difficulty(_ difficulty: PromptDifficulty) -> StatusPill {
        StatusPill(
            text: difficulty.displayName,
            color: AppColors.difficultyColor(difficulty),
            fillOpacity: 0.2
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusPill(text: "Done", color: AppColors.success, glyph: .icon("checkmark"))
        StatusPill(text: "Active", color: AppColors.primary, glyph: .dot)
        StatusPill(text: "Good", color: AppColors.success, glyph: .dot)
        StatusPill(text: "Hard", color: AppColors.error, fillOpacity: 0.2)
    }
    .padding(40)
    .background(AppBackground())
}
