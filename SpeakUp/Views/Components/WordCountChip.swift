import SwiftUI

/// A word and how often it happened — the vocabulary chip.
///
/// One recipe for every place the app shows tracked words: the History vocab
/// strip, the Words tab impact/content chips. A filled count badge on tinted
/// capsule when the count is the point; a quiet secondary count when it is not.
struct WordCountChip: View {
    let word: String
    let count: Int
    var color: Color = AppColors.success
    /// Filled badge (count is the headline) vs plain caption (word list).
    var showsBadge = true

    var body: some View {
        HStack(spacing: 5) {
            Text(word)
                .font(.caption.weight(.medium))

            if showsBadge {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(color))
            } else {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(showsBadge ? 0.12 : 0)))
        .overlay {
            if !showsBadge {
                Capsule().stroke(AppColors.cardStroke, lineWidth: 0.5)
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        WordCountChip(word: "delivered", count: 12)
        WordCountChip(word: "migration", count: 4, color: AppColors.primary, showsBadge: false)
        WordCountChip(word: "negotiated", count: 3, color: AppColors.warning)
    }
    .padding(40)
    .background(AppBackground())
}
