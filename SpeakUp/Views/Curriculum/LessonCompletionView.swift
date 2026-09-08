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
                        Text("Lesson wrapped")
                            .font(.title.weight(.bold))

                        Text(lesson.title)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(contentOpacity)

                    GlassCard(tint: identity.accent.opacity(0.08)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("You can now")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(identity.accent)
                                .textCase(.uppercase)
                                .tracking(0.4)

                            Text(lesson.objective)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(LessonTeachingCopy.roadmap(for: lesson))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .opacity(contentOpacity)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What you worked")
                                .font(.subheadline.weight(.semibold))

                            ForEach(Array(lesson.activities.enumerated()), id: \.element.id) { index, activity in
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(AppColors.success)

                                    Text("\(index + 1). \(activity.type.teacherRole)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(activity.type.teacherColor)
                                        .frame(width: 72, alignment: .leading)

                                    Text(activity.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Spacer(minLength: 0)
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
                                    Text("Tomorrow's board")
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
                            GlassButton(title: "Next lesson", icon: "arrow.right", iconPosition: .right, style: .primary, fullWidth: true) {
                                Haptics.medium()
                                onNextLesson()
                            }
                        }

                        GlassButton(title: "Back to path", style: .secondary, fullWidth: true) {
                            Haptics.light()
                            onBackToCurriculum()
                        }
                    }
                    .opacity(contentOpacity)

                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, AppLayout.pageHorizontal)
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
