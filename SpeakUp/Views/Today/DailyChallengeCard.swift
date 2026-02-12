import SwiftUI

struct DailyChallengeCard: View {
    let challenge: DailyChallenge

    @State private var glowPulse = false

    private var accentColor: Color {
        challenge.isCompleted ? .green : .orange
    }

    var body: some View {
        FeaturedGlassCard(
            gradientColors: challenge.isCompleted
                ? [.green.opacity(0.15), .green.opacity(0.05)]
                : [.orange.opacity(0.18), .yellow.opacity(0.08)]
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Header row
                HStack {
                    Label("Daily Challenge", systemImage: "star.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accentColor)

                    Spacer()

                    if challenge.isCompleted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                            Text("Done")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 7, height: 7)
                                .scaleEffect(glowPulse ? 1.4 : 1.0)
                                .opacity(glowPulse ? 0.6 : 1.0)
                            Text("Active")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.orange)
                    }
                }

                // Challenge content
                HStack(spacing: 14) {
                    ZStack {
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
