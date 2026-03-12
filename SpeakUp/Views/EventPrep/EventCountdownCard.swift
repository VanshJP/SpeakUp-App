import SwiftUI

struct EventCountdownCard: View {
    let event: SpeakingEvent
    var nextTaskTitle: String?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FeaturedGlassCard(gradientColors: [AppColors.primary.opacity(0.12), .cyan.opacity(0.06)]) {
                HStack(spacing: 14) {
                    // Readiness mini ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 4)
                            .frame(width: 48, height: 48)

                        Circle()
                            .trim(from: 0, to: Double(event.readinessScore) / 100.0)
                            .stroke(
                                AppColors.scoreColor(for: event.readinessScore),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 48, height: 48)
                            .rotationEffect(.degrees(-90))

                        Text("\(event.readinessScore)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.scoreColor(for: event.readinessScore))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)

                        Text(event.daysRemainingText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(event.daysRemaining <= 3 ? AppColors.warning : AppColors.primary)

                        if let taskTitle = nextTaskTitle {
                            Text("Next: \(taskTitle)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
