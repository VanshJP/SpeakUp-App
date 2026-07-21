import SwiftUI

struct DailyChallengeCard: View {
    let challenge: DailyChallenge

    private var accentColor: Color {
        challenge.isCompleted ? AppColors.success : AppColors.warning
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                // Header row: caption left, status pill right
                HStack {
                    Text("Daily Challenge")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Spacer()

                    HStack(spacing: 4) {
                        if challenge.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                        } else {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 5, height: 5)
                        }
                        Text(challenge.isCompleted ? "Done" : "Active")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(accentColor.opacity(0.12)))
                }

                // Challenge content
                HStack(spacing: 14) {
                    Image(systemName: challenge.icon)
                        .font(.title3)
                        .foregroundStyle(accentColor)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .overlay {
                                    Circle().stroke(AppColors.cardStroke, lineWidth: 0.5)
                                }
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(challenge.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily challenge: \(challenge.title), \(challenge.isCompleted ? "completed" : "active")")
    }
}
