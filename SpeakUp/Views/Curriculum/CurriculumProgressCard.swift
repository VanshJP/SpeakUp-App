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
                        Circle()
                            .stroke(Color.white.opacity(0.07), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: viewModel.overallProgress)
                            .stroke(AppColors.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))

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
