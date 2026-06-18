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
                .foregroundStyle(
                    LinearGradient(
                        colors: isActive
                            ? [AppColors.warning.opacity(0.85), AppColors.warning, AppColors.error.opacity(0.85)]
                            : [Color.white.opacity(0.4), Color.white.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("\(streak)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(streak)))

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(isActive ? AppColors.warning.opacity(0.12) : Color.clear)
                }
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                }
                .shadow(color: isActive ? AppColors.warning.opacity(0.25) : .clear, radius: 8, y: 2)
        }
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
