import SwiftUI

struct EventPrepTaskRow: View {
    let task: EventPrepTask
    var onStart: (() -> Void)?
    var onComplete: (() -> Void)?

    private var taskColor: Color {
        switch task.type {
        case .fullRehearsal: return .teal
        case .sectionPractice: return .blue
        case .fillerDrill: return .orange
        case .paceDrill: return .blue
        case .pauseDrill: return .purple
        case .warmUp: return .cyan
        case .confidenceExercise: return .pink
        case .scriptReview: return .indigo
        case .impromptuVariation: return .red
        case .dayOfPrep: return .yellow
        }
    }

    var body: some View {
        GlassCard(tint: task.isCompleted ? AppColors.glassTintSuccess : taskColor.opacity(0.06), padding: 12) {
            HStack(spacing: 12) {
                // Completion toggle
                Button {
                    Haptics.success()
                    onComplete?()
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? AppColors.success : .secondary)
                }
                .buttonStyle(.plain)

                // Icon
                Image(systemName: task.type.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(taskColor)
                    .frame(width: 28)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)

                    Text(task.taskDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if task.isOverdue {
                        Text("Overdue")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.warning)
                    }
                }

                Spacer()

                // Start button
                if !task.isCompleted, let onStart {
                    Button {
                        Haptics.medium()
                        onStart()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle()
                                    .fill(taskColor)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
