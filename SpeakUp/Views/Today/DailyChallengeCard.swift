import SwiftUI

struct DailyChallengeCard: View {
    let challenge: DailyChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Challenge")
                .font(.headline)

            GlassCard(tint: challenge.isCompleted ? .green.opacity(0.1) : .orange.opacity(0.1), padding: 14) {
                HStack(spacing: 14) {
                    Image(systemName: challenge.icon)
                        .font(.title2)
                        .foregroundStyle(challenge.isCompleted ? .green : .orange)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.title)
                            .font(.subheadline.weight(.semibold))

                        Text(challenge.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if challenge.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }
}
