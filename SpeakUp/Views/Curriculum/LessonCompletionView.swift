import SwiftUI

struct LessonCompletionView: View {
    let lesson: CurriculumLesson
    let nextLesson: CurriculumLesson?
    let onNextLesson: () -> Void
    let onBackToCurriculum: () -> Void

    @State private var showConfetti = false
    @State private var trophyScale: CGFloat = 0.3
    @State private var trophyOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    private var identity: LessonIdentity {
        LessonIdentity.forLesson(id: lesson.id)
    }

    private var encouragement: String {
        let messages = [
            "You crushed it!",
            "That's real progress!",
            "You should be proud!",
            "Another one in the books!",
            "Your future self thanks you!",
        ]
        return messages[abs(lesson.id.hashValue) % messages.count]
    }

    var body: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 40)

                    ZStack {
                        Circle()
                            .fill(identity.accent.opacity(0.18))
                            .frame(width: 96, height: 96)
                        LessonGlyphView(identity: identity, state: .completed)
                            .frame(width: 44, height: 44)
                            .scaleEffect(trophyScale)
                            .opacity(trophyOpacity)
                    }
                    .shadow(color: identity.accent.opacity(0.35), radius: 12)

                    VStack(spacing: 8) {
                        Text("Lesson Complete!")
                            .font(.title.weight(.bold))

                        Text(lesson.title)
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Text(encouragement)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(identity.accent)
                            .padding(.top, 2)
                    }
                    .opacity(contentOpacity)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What You Completed")
                                .font(.subheadline.weight(.semibold))

                            ForEach(lesson.activities) { activity in
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(AppColors.success)

                                    Text(activity.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Spacer()
                                }
                            }
                        }
                    }
                    .opacity(contentOpacity)

                    if let nextLesson {
                        let nextIdentity = LessonIdentity.forLesson(id: nextLesson.id)
                        GlassCard(tint: nextIdentity.accent.opacity(0.08)) {
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(nextIdentity.accent.opacity(0.18))
                                    LessonGlyphView(identity: nextIdentity, state: .available)
                                        .frame(width: 24, height: 24)
                                }
                                .frame(width: 44, height: 44)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Up Next")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(nextIdentity.accent)

                                    Text(nextLesson.title)
                                        .font(.headline)

                                    Text(nextLesson.objective)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(contentOpacity)
                    }

                    VStack(spacing: 12) {
                        if nextLesson != nil {
                            GlassButton(title: "Next Lesson", icon: "arrow.right", iconPosition: .right, style: .primary, fullWidth: true) {
                                Haptics.medium()
                                onNextLesson()
                            }
                        }

                        GlassButton(title: "Back to Learning Path", style: .secondary, fullWidth: true) {
                            Haptics.light()
                            onBackToCurriculum()
                        }
                    }
                    .opacity(contentOpacity)

                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)

            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            Haptics.success()

            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                trophyScale = 1.0
                trophyOpacity = 1.0
            }

            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                contentOpacity = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showConfetti = true
            }
        }
    }
}
