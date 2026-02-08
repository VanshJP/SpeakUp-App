import SwiftUI

struct DailyChallengeCard: View {
    let challenge: DailyChallenge

    @State private var glowPulse = false

    private var accentColor: Color {
        challenge.isCompleted ? .green : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Daily Challenge", systemImage: "star.circle.fill")
                .font(.headline)

            GlassCard(
                tint: accentColor.opacity(0.12),
                accentBorder: accentColor.opacity(0.35)
            ) {
                HStack(spacing: 14) {
                    // Challenge icon with gradient background + glow
                    ZStack {
                        // Ambient glow behind icon
                        Circle()
                            .fill(accentColor.opacity(glowPulse ? 0.25 : 0.12))
                            .frame(width: 56, height: 56)
                            .blur(radius: 8)

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: challenge.isCompleted
                                        ? [.green.opacity(0.3), .green.opacity(0.12)]
                                        : [.orange.opacity(0.3), .yellow.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .overlay {
                                Circle()
                                    .stroke(accentColor.opacity(0.3), lineWidth: 0.5)
                            }

                        Image(systemName: challenge.icon)
                            .font(.title3)
                            .foregroundStyle(accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.title)
                            .font(.subheadline.weight(.semibold))

                        Text(challenge.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    if challenge.isCompleted {
                        VStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            Text("Done")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.green)
                        }
                    } else {
                        // Active indicator with subtle pulse
                        VStack(spacing: 2) {
                            Image(systemName: "circle.dashed")
                                .font(.title2)
                                .foregroundStyle(.orange.opacity(glowPulse ? 0.7 : 0.4))
                            Text("Active")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !challenge.isCompleted else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }
}
