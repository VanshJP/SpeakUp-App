import SwiftUI

/// A word and how often it happened — the vocabulary chip.
///
/// ONE recipe for every tracked-word list on the Progress page. The former
/// filled-badge variant made each group look like a different component, so
/// three stacked word lists read as three unrelated systems shouting at once.
/// Now the shape is fixed and only the tint changes: the group's label says
/// what the words are, the tint agrees with it, and the count stays quiet.
struct WordCountChip: View {
    let word: String
    let count: Int
    var color: Color = AppColors.success

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            Text("\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay { Capsule().stroke(color.opacity(0.22), lineWidth: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(word), \(count) time\(count == 1 ? "" : "s")")
    }
}

#Preview {
    VStack(spacing: 12) {
        WordCountChip(word: "delivered", count: 12)
        WordCountChip(word: "migration", count: 4, color: AppColors.primary)
        WordCountChip(word: "negotiated", count: 3, color: AppColors.warning)
    }
    .padding(40)
    .background(AppBackground())
}
