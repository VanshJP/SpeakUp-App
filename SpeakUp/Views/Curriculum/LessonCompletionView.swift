import SwiftUI

struct LessonCompletionView: View {
    let lesson: CurriculumLesson
    let nextLesson: CurriculumLesson?
    let onNextLesson: () -> Void
    let onBackToCurriculum: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConfetti = false
    @State private var trophyScale: CGFloat = 0.3

    private var identity: LessonIdentity {
        LessonIdentity.forLesson(id: lesson.id)
    }

    var body: some View {
        // No canvas of its own: `LessonDetailView` paints it, and a second one
        // here stacked another full-screen pass under the same pixels.
        ZStack {
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
                            .introReveal()
                    }
                    .shadow(color: identity.accent.opacity(0.35), radius: 12)

                    VStack(spacing: 8) {
                        Text("Lesson wrapped")
                            .font(.title.weight(.bold))

                        Text(lesson.title)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .introReveal(delay: .milliseconds(300))

                    // The objective only. The roadmap line under it ("We'll learn,
                    // then practice") was future tense on a finished lesson and
                    // repeated the list below.
                    GlassCard(tint: identity.accent.opacity(0.06)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("You can now")
                                .eyebrowStyle(identity.accent)

                            Text(lesson.objective)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .introReveal(delay: .milliseconds(300))

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GlassCardTitle("What you worked")

                            // A grid, not a fixed 72pt role column: the column
                            // takes its widest label, so "3. Warm-up" is never
                            // clipped at large text sizes.
                            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
                                ForEach(Array(lesson.activities.enumerated()), id: \.element.id) { index, activity in
                                    GridRow(alignment: .firstTextBaseline) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(AppColors.success)

                                        Text("\(index + 1). \(activity.type.teacherRole)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(activity.type.teacherColor)

                                        Text(activity.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .introReveal(delay: .milliseconds(300))

                    if let nextLesson {
                        let nextIdentity = LessonIdentity.forLesson(id: nextLesson.id)
                        GlassCard(tint: nextIdentity.accent.opacity(0.06)) {
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(nextIdentity.accent.opacity(0.18))
                                    LessonGlyphView(identity: nextIdentity, state: .available)
                                        .frame(width: 24, height: 24)
                                }
                                .frame(width: 44, height: 44)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Up next")
                                        .eyebrowStyle(nextIdentity.accent)

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
                        .introReveal(delay: .milliseconds(300))
                    }

                    VStack(spacing: 12) {
                        if nextLesson != nil {
                            GlassButton(title: "Next lesson", icon: "arrow.right", iconPosition: .right, style: .primary, fullWidth: true) {
                                Haptics.medium()
                                onNextLesson()
                            }
                        }

                        GlassButton(title: "Back to Learn", style: .secondary, fullWidth: true) {
                            Haptics.light()
                            onBackToCurriculum()
                        }
                    }
                    .introReveal(delay: .milliseconds(300))

                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, AppLayout.pageHorizontal)
            }
            .scrollIndicators(.hidden)

            if showConfetti {
                // Bursts from the lesson glyph at the top of the page.
                ConfettiView(origin: UnitPoint(x: 0.5, y: 0.16))
            }
        }
        // The arrival is decoration; both exits ride `.introReveal`, which
        // renders them at rest if the animation never runs. They used to share
        // one `contentOpacity` raised inside `onAppear`, which is one missed
        // callback away from a screen with no way off it.
        .onAppear {
            Haptics.success()
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6)) {
                trophyScale = 1.0
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            showConfetti = true
        }
    }
}
