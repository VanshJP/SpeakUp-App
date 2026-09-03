import SwiftUI

/// Day streak, top-right of Today. Neutral glass — the flame is the only
/// colored thing on it.
///
/// The capsule used to be tinted `warning` at 0.35, which made a two-digit
/// number the loudest object on the page and put a saturated orange slab
/// beside a graphite header. The streak is one number; it does not need a
/// billboard to be found, and the glyph alone carries the "you're on a run"
/// signal. Zero-streak drops the flame to grey rather than swapping chrome, so
/// the chip never changes shape underneath the user.
struct StreakChip: View {
    let streak: Int

    private var isActive: Bool { streak >= 1 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive ? AppColors.warning : Color.white.opacity(0.35))

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
        .glassEffect(.regular.interactive(), in: .capsule)
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
