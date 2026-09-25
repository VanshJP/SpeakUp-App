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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes the glyph sits above the words. Beside them it
    /// took a quarter of the width and broke "The PREP Framework" mid-word.
    private var glyphAndText: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: isCompact ? 12 : 14))
    }

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
        glyphAndText {
            glyphPlate(size: 40, glyph: 22, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.85)

                Text(lesson.objective)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lesson.title). \(lesson.objective)")
    }

    // MARK: Full

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            glyphAndText {
                glyphPlate(size: 60, glyph: 32, cornerRadius: 16)

                VStack(alignment: .leading, spacing: 5) {
                    Text(isReviewing ? "Reviewing" : "Today's focus")
                        .eyebrowStyle(identity.accent)

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

            // VoiceOver reads the plan itself. A "Lesson plan overview" label
            // stood in for it, so the sentence was never spoken.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(identity.accent.opacity(0.7))
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                Text(LessonTeachingCopy.roadmap(for: lesson))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// Segmented lesson progress in the sticky bottom bar - the one track on the
/// lesson screen, Speak / Duolingo style.
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

/// Coach line above the current activity - cue only, no second title row.
/// Kept to one quiet line: it frames the card under it, it is not a card. It
/// had a tinted plate of its own, a card by another name in the role colour.
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.type.teacherRole). \(activity.type.teacherCue)")
    }
}
