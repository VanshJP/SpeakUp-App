import SwiftUI

struct AchievementUnlockedView: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    @State private var showContent = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 24) {
                // Confetti
                ConfettiView()
                    .frame(height: 120)

                Image(systemName: achievement.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(.teal)
                    .symbolEffect(.bounce, value: showContent)

                VStack(spacing: 8) {
                    Text("Achievement Unlocked!")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                        .textCase(.uppercase)
                        .tracking(1.5)

                    Text(achievement.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)

                    Text(achievement.descriptionText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Awesome!")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.teal)
                        )
                }
                .padding(.horizontal, 40)
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
        .onAppear {
            Haptics.success()
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                showContent = true
            }
        }
    }
}
