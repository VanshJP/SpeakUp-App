import SwiftUI
import SwiftData

struct LessonDetailView: View {
    let lesson: CurriculumLesson
    @Bindable var viewModel: CurriculumViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    // Lesson header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lesson.title)
                            .font(.title2.weight(.bold))

                        Text(lesson.objective)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Activities
                    ForEach(lesson.activities) { activity in
                        activityCard(activity)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func activityCard(_ activity: CurriculumActivity) -> some View {
        let isCompleted = viewModel.isActivityCompleted(activity.id)

        return GlassCard {
            HStack(spacing: 12) {
                // Type icon
                Image(systemName: activityIcon(for: activity.type))
                    .font(.title3)
                    .foregroundStyle(activityColor(for: activity.type))
                    .frame(width: 36, height: 36)
                    .background {
                        Circle().fill(activityColor(for: activity.type).opacity(0.15))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(activity.title)
                            .font(.subheadline.weight(.medium))

                        if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    Text(activity.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer()

                if !isCompleted {
                    Button {
                        viewModel.completeActivity(activity.id, context: modelContext)
                    } label: {
                        Text("Done")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.teal))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func activityIcon(for type: CurriculumActivityType) -> String {
        switch type {
        case .lesson: return "book"
        case .practice: return "mic"
        case .drill: return "bolt"
        case .exercise: return "figure.walk"
        case .review: return "arrow.counterclockwise"
        }
    }

    private func activityColor(for type: CurriculumActivityType) -> Color {
        switch type {
        case .lesson: return .blue
        case .practice: return .teal
        case .drill: return .orange
        case .exercise: return .green
        case .review: return .purple
        }
    }
}
