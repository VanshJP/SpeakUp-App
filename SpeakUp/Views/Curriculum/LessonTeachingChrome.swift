import SwiftUI

/// Teacher-facing labels for curriculum activity types. Used by lesson detail chrome.
extension CurriculumActivityType {
    var teacherRole: String {
        switch self {
        case .lesson: return "Learn"
        case .practice: return "Practice"
        case .drill: return "Drill"
        case .exercise: return "Warm-up"
        case .review: return "Review"
        }
    }

    var teacherIcon: String {
        switch self {
        case .lesson: return "book.fill"
        case .practice: return "mic.fill"
        case .drill: return "bolt.fill"
        case .exercise: return "figure.mind.and.body"
        case .review: return "ear.fill"
        }
    }

    var teacherCue: String {
        switch self {
        case .lesson:
            return "Read this first — then you'll put it into a take."
        case .practice:
            return "Your turn. Keep today's focus in mind while you speak."
        case .drill:
            return "Short reps. Chase one skill only — ignore everything else."
        case .exercise:
            return "Prep the voice and body before the scored take."
        case .review:
            return "Listen like a coach. Hunt for today's focus in the take."
        }
    }

    var teacherColor: Color {
        switch self {
        case .lesson: return AppColors.info
        case .practice: return AppColors.primary
        case .drill: return AppColors.warning
        case .exercise: return AppColors.success
        case .review: return AppColors.categoryBrandBright
        }
    }
}

enum LessonTeachingCopy {
    /// One-line plan a teacher would say before opening the first card.
    static func roadmap(for lesson: CurriculumLesson) -> String {
        let roles = lesson.activities.map(\.type.teacherRole)
        guard !roles.isEmpty else { return lesson.objective }

        if roles.count == 1 {
            return "Today is one clear move: \(roles[0].lowercased())."
        }

        let head = roles.dropLast().joined(separator: ", ")
        let last = roles.last!
        return "We'll \(head.lowercased()), then \(last.lowercased())."
    }

    static func nextCTA(after index: Int, in lesson: CurriculumLesson) -> String {
        let nextIndex = index + 1
        guard nextIndex < lesson.activities.count else { return "Wrap up" }
        let role = lesson.activities[nextIndex].type.teacherRole
        return "Next · \(role)"
    }
}

/// Hero board: glyph + today's focus + objective + roadmap sentence.
struct LessonBoardHeader: View {
    let lesson: CurriculumLesson
    let identity: LessonIdentity
    var isReviewing: Bool = false

    var body: some View {
        GlassCard(tint: identity.accent.opacity(0.08), padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(identity.accent.opacity(0.18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(identity.accent.opacity(0.4), lineWidth: 1)
                            }
                        LessonGlyphView(
                            identity: identity,
                            state: isReviewing ? .completed : .current
                        )
                        .frame(width: 32, height: 32)
                    }
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(isReviewing ? "Reviewing" : "Today's focus")
                            .font(.system(size: 10, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(identity.accent)

                        Text(lesson.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(lesson.objective)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(LessonTeachingCopy.roadmap(for: lesson))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Lesson plan overview")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Labeled step strip — Learn / Practice / Review — not anonymous capsules.
struct LessonPlanStrip: View {
    let lesson: CurriculumLesson
    let currentIndex: Int
    let completedIds: Set<String>
    let accent: Color
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lesson plan")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                ForEach(Array(lesson.activities.enumerated()), id: \.element.id) { index, activity in
                    planChip(index: index, activity: activity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lesson plan, step \(currentIndex + 1) of \(lesson.activities.count)")
    }

    private func planChip(index: Int, activity: CurriculumActivity) -> some View {
        let isCompleted = completedIds.contains(activity.id)
        let isCurrent = index == currentIndex
        let canSelect = isCompleted || index <= currentIndex
        let color = activity.type.teacherColor

        return Button {
            guard canSelect else { return }
            Haptics.light()
            onSelect(index)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(chipFill(isCompleted: isCompleted, isCurrent: isCurrent, color: color))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    chipStroke(isCompleted: isCompleted, isCurrent: isCurrent, color: color),
                                    lineWidth: isCurrent ? 1.5 : 1
                                )
                        }

                    if isCompleted && !isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.success)
                    } else {
                        Image(systemName: activity.type.teacherIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isCurrent || isCompleted ? color : .white.opacity(0.45))
                    }
                }
                .frame(height: 40)
                .shadow(
                    color: isCurrent ? accent.opacity(0.35) : .clear,
                    radius: isCurrent ? 8 : 0,
                    y: 2
                )

                Text("\(index + 1) \(activity.type.teacherRole)")
                    .font(.system(size: 10, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? Color.white : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .opacity(canSelect || isCurrent ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
        .accessibilityLabel("\(activity.type.teacherRole), step \(index + 1)")
        .accessibilityValue(isCompleted ? "Completed" : (isCurrent ? "Current" : "Upcoming"))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func chipFill(isCompleted: Bool, isCurrent: Bool, color: Color) -> Color {
        if isCurrent { return color.opacity(0.22) }
        if isCompleted { return AppColors.success.opacity(0.14) }
        return Color.white.opacity(0.05)
    }

    private func chipStroke(isCompleted: Bool, isCurrent: Bool, color: Color) -> Color {
        if isCurrent { return color }
        if isCompleted { return AppColors.success.opacity(0.45) }
        return AppColors.cardStroke
    }
}

/// Coach line above the current activity card.
struct LessonCoachCue: View {
    let activity: CurriculumActivity

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: activity.type.teacherIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(activity.type.teacherColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(activity.type.teacherColor.opacity(0.15)))

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.type.teacherRole)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(activity.type.teacherColor)
                    .textCase(.uppercase)
                    .tracking(0.4)

                Text(activity.type.teacherCue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
