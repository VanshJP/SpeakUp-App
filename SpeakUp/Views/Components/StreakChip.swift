import SwiftUI

/// Compact streak indicator pinned to the Today header. Designed to be
/// wrapped by a `NavigationLink` — purely visual, no embedded button.
struct StreakChip: View {
    let streak: Int

    private var isActive: Bool { streak >= 1 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive ? AppColors.warning : Color.white.opacity(0.35))

            Text("\(streak)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(streak)))

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: AppLayout.minHitTarget)
        .contentShape(Capsule())
        .glassEffect(
            isActive ? .regular.tint(AppColors.warning.opacity(0.35)).interactive() : .regular.interactive(),
            in: .capsule
        )
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(streak) day streak")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ZStack {
        AppBackground()
        HStack(spacing: 12) {
            StreakChip(streak: 0)
            StreakChip(streak: 5)
            StreakChip(streak: 42)
        }
    }
}
