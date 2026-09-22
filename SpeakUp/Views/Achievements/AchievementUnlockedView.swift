import SwiftUI

/// The award moment. A medal flips in edge-first, lands with a haptic, catches
/// the light once, and the confetti bursts from behind it.
///
/// Celebration surface: exempt from the no-glow rule, like the score reveal.
struct AchievementUnlockedView: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var flipped = false
    @State private var shine = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    Haptics.light()
                    onDismiss()
                }

            ConfettiView(origin: UnitPoint(x: 0.5, y: 0.38))
                .ignoresSafeArea()

            VStack(spacing: 22) {
                AchievementMedal(icon: achievement.icon, shine: shine)
                    .frame(width: 128, height: 128)
                    .rotation3DEffect(
                        .degrees(flipped ? 0 : -100),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.5
                    )
                    .scaleEffect(flipped ? 1 : 0.4)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Achievement unlocked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.warning)
                        .textCase(.uppercase)
                        .tracking(1.5)

                    Text(achievement.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityFocused($titleFocused)

                    Text(achievement.descriptionText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                GlassButton(
                    title: "Awesome!",
                    style: .primary,
                    fullWidth: true
                ) {
                    Haptics.medium()
                    onDismiss()
                }
                .padding(.horizontal, 8)
            }
            .padding(28)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .padding(.horizontal, 32)
            // The card and its only button must never wait on an animation
            // clock to exist (gotcha §23); only the medal's flip does.
            .introReveal()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            Haptics.light()
            onDismiss()
        }
        .task { await land() }
        .onAppear { titleFocused = true }
    }

    private func land() async {
        guard !reduceMotion else {
            flipped = true
            Haptics.success()
            return
        }
        withAnimation(.spring(duration: 0.7, bounce: 0.35)) { flipped = true }
        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled else { return }
        Haptics.success()
        withAnimation(.easeInOut(duration: 0.9)) { shine = true }
    }
}

// MARK: - Medal

/// Gold rim, graphite face, gilded glyph. `shine` sweeps one band of light
/// across the face when it flips true.
private struct AchievementMedal: View {
    let icon: String
    let shine: Bool

    private static let paleGold = Color(red: 1.0, green: 0.92, blue: 0.68)
    private static let deepGold = Color(red: 0.70, green: 0.42, blue: 0.13)

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [Self.paleGold, AppColors.warning, Self.deepGold, AppColors.warning, Self.paleGold],
                        center: .center
                    )
                )

            Circle()
                .inset(by: 7)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.21), Color(white: 0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Circle()
                .inset(by: 7)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)

            Image(systemName: icon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Self.paleGold, AppColors.warning],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // The band travels inside a medal-sized frame so the circular mask
            // is the medal's, not the band's own 54pt width.
            ZStack {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.5), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 54, height: 200)
                .rotationEffect(.degrees(20))
                .offset(x: shine ? 150 : -150)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask(Circle())
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        // Warm bloom behind the medal, outside its frame so it cannot push
        // the card's layout around.
        .background {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.warning.opacity(0.42), AppColors.warning.opacity(0.1), .clear],
                        center: .center,
                        startRadius: 40,
                        endRadius: 130
                    )
                )
                .frame(width: 270, height: 270)
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    AchievementUnlockedView(
        achievement: Achievement(
            id: "streak_7",
            title: "Weekly Warrior",
            descriptionText: "7 practice days in a row",
            icon: "flame.fill",
            isUnlocked: true
        ),
        onDismiss: {}
    )
    .background(AppBackground())
}
