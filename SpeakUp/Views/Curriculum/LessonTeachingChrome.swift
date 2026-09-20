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
///
/// Past the first step it shrinks to a name plate. The board states what the
/// lesson is; once you are inside an activity the activity is the subject, and
/// repeating the objective and the roadmap above every card was pushing the
/// actual teaching below the fold.
struct LessonBoardHeader: View {
    let lesson: CurriculumLesson
    let identity: LessonIdentity
    var isReviewing: Bool = false
    var isCompact: Bool = false

    var body: some View {
        GlassCard(tint: identity.accent.opacity(0.10), padding: isCompact ? 12 : 18) {
            if isCompact {
                compactBody
            } else {
                fullBody
            }
        }
    }

    // MARK: Compact

    private var compactBody: some View {
        HStack(spacing: 12) {
            glyphPlate(size: 40, glyph: 22, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(lesson.objective)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lesson.title). \(lesson.objective)")
    }

    // MARK: Full

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                glyphPlate(size: 60, glyph: 32, cornerRadius: 16)

                VStack(alignment: .leading, spacing: 5) {
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

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(identity.accent.opacity(0.7))
                    .padding(.top, 2)

                Text(LessonTeachingCopy.roadmap(for: lesson))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Lesson plan overview")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func glyphPlate(size: CGFloat, glyph: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(identity.accent.opacity(0.45), lineWidth: 1)
                }

            LessonGlyphView(
                identity: identity,
                state: isReviewing ? .completed : .current
            )
            .frame(width: glyph, height: glyph)
        }
        .frame(width: size, height: size)
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
///
/// The chips *are* the track: they already carry current, done and locked per
/// step, so an eyebrow count and a segmented bar above them were the same
/// three facts drawn three times. The thin bar survives in the sticky bottom
/// bar, where it is the only progress on screen once this scrolls away.
struct LessonPlanStrip: View {
    let lesson: CurriculumLesson
    let currentIndex: Int
    let completedIds: Set<String>
    let accent: Color
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(lesson.activities.enumerated()), id: \.element.id) { index, activity in
                planChip(index: index, activity: activity)
            }
        }
        .padding(10)
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
/// Kept to one quiet line: it frames the card under it, it is not a card.
struct LessonCoachCue: View {
    let activity: CurriculumActivity

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(activity.type.teacherColor)

            Text(activity.type.teacherCue)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(activity.type.teacherColor.opacity(0.08))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.type.teacherRole). \(activity.type.teacherCue)")
    }
}
