import SwiftUI

struct ChallengeAcceptView: View {
    let challenge: SocialChallenge
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "trophy.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("You've Been Challenged!")
                .font(.title2.weight(.bold))

            VStack(spacing: 8) {
                Text("\(challenge.challengerName) scored")
                    .foregroundStyle(.secondary)

                Text("\(challenge.challengerScore)/100")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(AppColors.scoreColor(for: challenge.challengerScore))

                Text("Can you beat it?")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if !challenge.promptText.isEmpty {
                GlassCard(tint: .teal.opacity(0.1)) {
                    Text(challenge.promptText)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                GlassButton(
                    title: "Accept Challenge",
                    icon: "mic.fill",
                    style: .primary,
                    fullWidth: true
                ) {
                    onAccept()
                }

                Button("Not Now") {
                    onDismiss()
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
