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
            return "Read this first. Then put it into a take."
        case .practice:
            return "Your turn. Keep today's focus in mind while you speak."
        case .drill:
            return "Short reps. Chase one skill only and ignore everything else."
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
        GlassCard(tint: identity.accent.opacity(0.10), padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        identity.accent.opacity(0.28),
                                        identity.accent.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(identity.accent.opacity(0.45), lineWidth: 1)
                            }

                        LessonGlyphView(
                            identity: identity,
                            state: isReviewing ? .completed : .current
                        )
                        .frame(width: 36, height: 36)
                    }
                    .frame(width: 68, height: 68)
                    .shadow(color: identity.accent.opacity(0.25), radius: 12, y: 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(isReviewing ? "Reviewing" : "Today's focus")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.8)
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

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "quote.opening")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(identity.accent.opacity(0.7))
                        .padding(.top, 2)

                    Text(LessonTeachingCopy.roadmap(for: lesson))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .accessibilityLabel("Lesson plan overview")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Segmented lesson progress - Speak / Duolingo-style track above the step chips.
struct LessonProgressTrack: View {
    let total: Int
    let currentIndex: Int
    let completedIds: Set<String>
    let activityIds: [String]
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(height: 4)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentIndex)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: completedIds)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lesson progress")
        .accessibilityValue("Step \(currentIndex + 1) of \(total)")
    }

    private func fill(for index: Int) -> Color {
        let done = index < activityIds.count && completedIds.contains(activityIds[index])
        if done { return AppColors.success }
        if index == currentIndex { return accent }
        if index < currentIndex { return accent.opacity(0.55) }
        return Color.white.opacity(0.12)
    }
}

/// Labeled step strip - Learn / Practice / Review. Icons always visible;
/// completion is a corner badge, never a replacement for the role glyph.
struct LessonPlanStrip: View {
    let lesson: CurriculumLesson
    let currentIndex: Int
    let completedIds: Set<String>
    let accent: Color
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lesson plan")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)

                Text("\(completedIds.intersection(Set(lesson.activities.map(\.id))).count)/\(lesson.activities.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            LessonProgressTrack(
                total: lesson.activities.count,
                currentIndex: currentIndex,
                completedIds: completedIds,
                activityIds: lesson.activities.map(\.id),
                accent: accent
            )

            HStack(spacing: 10) {
                ForEach(Array(lesson.activities.enumerated()), id: \.element.id) { index, activity in
                    planChip(index: index, activity: activity)
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColors.cardStroke, lineWidth: 1)
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
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(chipFill(isCompleted: isCompleted, isCurrent: isCurrent, color: color))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    chipStroke(isCompleted: isCompleted, isCurrent: isCurrent, color: color),
                                    lineWidth: isCurrent ? 1.5 : 1
                                )
                        }

                    Image(systemName: activity.type.teacherIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isCurrent || isCompleted ? color : .white.opacity(0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppColors.success)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.65))
                                    .padding(-2)
                            )
                            .offset(x: 5, y: -5)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: 44)
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
        if isCompleted { return AppColors.success.opacity(0.12) }
        return Color.white.opacity(0.05)
    }

    private func chipStroke(isCompleted: Bool, isCurrent: Bool, color: Color) -> Color {
        if isCurrent { return color }
        if isCompleted { return AppColors.success.opacity(0.4) }
        return AppColors.cardStroke
    }
}

/// Coach line above the current activity - cue only, no second title row.
struct LessonCoachCue: View {
    let activity: CurriculumActivity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(activity.type.teacherColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(activity.type.teacherColor.opacity(0.15)))

            Text(activity.type.teacherCue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(activity.type.teacherColor.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(activity.type.teacherColor.opacity(0.18), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.type.teacherRole). \(activity.type.teacherCue)")
    }
}
