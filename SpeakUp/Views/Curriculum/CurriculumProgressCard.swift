import SwiftUI

struct CurriculumProgressCard: View {
    var viewModel: CurriculumViewModel
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            FeaturedGlassCard {
                HStack(spacing: 14) {
                    // Progress ring
                    ZStack {
                        RingProgress(
                            progress: viewModel.overallProgress,
                            color: AppColors.primary,
                            lineWidth: 4
                        )

                        Image(systemName: "book.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.primary)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Continue Learning")
                            .font(.subheadline.weight(.semibold))

                        if let lesson = viewModel.currentLesson {
                            Text(lesson.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text("\(viewModel.completedLessonsCount)/\(viewModel.totalLessonsCount) lessons")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
    }
}
