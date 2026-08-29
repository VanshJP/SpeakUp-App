import SwiftUI

/// Waiting on Today when a friend-challenge link arrived during onboarding,
/// or the recipient cancelled the countdown. Tapping starts the same prompt
/// with challenge chrome still attached.
struct FriendChallengeCard: View {
    let challenge: SharedChallenge
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GlassCard(tint: AppColors.primary, padding: 16, elevated: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Friend challenge")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                        .textCase(.uppercase)
                        .tracking(0.7)

                    Spacer(minLength: 0)

                    Button("Dismiss", systemImage: "xmark") {
                        Haptics.light()
                        onDismiss()
                    }
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Dismiss friend challenge")
                }

                Text(challenge.promptText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if let score = challenge.beatScore {
                        Text("They scored \(score)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    GlassButton(
                        title: "Accept",
                        icon: "bolt.fill",
                        style: .primary,
                        size: .small
                    ) {
                        Haptics.medium()
                        onAccept()
                    }
                    .accessibilityLabel("Accept friend challenge")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ZStack {
        AppBackground()
        FriendChallengeCard(
            challenge: SharedChallenge(
                promptID: "prof-1",
                promptText: "Describe a challenging project you completed and what you learned from it.",
                beatScore: 78
            ),
            onAccept: {},
            onDismiss: {}
        )
        .padding()
    }
}
