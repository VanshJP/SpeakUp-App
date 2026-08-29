import SwiftUI

struct AchievementUnlockedView: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var showContent = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    Haptics.light()
                    onDismiss()
                }

            VStack(spacing: 24) {
                if !reduceMotion {
                    ConfettiView()
                        .frame(height: 120)
                }

                Image(systemName: achievement.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(AppColors.primary)
                    .symbolEffect(.bounce, value: reduceMotion ? false : showContent)

                VStack(spacing: 8) {
                    Text("Achievement Unlocked!")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .textCase(.uppercase)
                        .tracking(1.5)

                    Text(achievement.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
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
            .padding(32)
            .background {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial)
            }
            .padding(.horizontal, 32)
            .scaleEffect(showContent ? 1 : 0.8)
            .opacity(showContent ? 1 : 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            Haptics.light()
            onDismiss()
        }
        .onAppear {
            Haptics.success()
            if reduceMotion {
                showContent = true
            } else {
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                    showContent = true
                }
            }
            titleFocused = true
        }
    }
}
