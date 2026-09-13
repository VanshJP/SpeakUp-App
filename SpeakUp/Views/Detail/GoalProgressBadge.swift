import SwiftUI
import SwiftData

struct GoalProgressBadge: View {
    let goalId: UUID

    @Query private var goals: [UserGoal]

    private var goal: UserGoal? {
        goals.first { $0.id == goalId }
    }

    var body: some View {
        if let goal {
            GlassCard(tint: AppColors.primary.opacity(0.08)) {
                HStack(spacing: 12) {
                    Image(systemName: goal.type.iconName)
                        .font(.title3)
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title)
                            .font(.subheadline.weight(.medium))
                        Text("\(goal.progressPercentage)% complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    RingProgress(progress: goal.progress, color: AppColors.primary, lineWidth: 3)
                        .frame(width: 32, height: 32)
                }
            }
        }
    }
}
