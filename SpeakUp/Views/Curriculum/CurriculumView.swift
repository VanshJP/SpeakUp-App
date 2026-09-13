import SwiftUI
import SwiftData

/// Learn tab — path of phases/lessons. Detail: `LessonDetailView`.
struct CurriculumView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CurriculumViewModel()
    @State private var showingAwards = false
    @State private var showingLockedInfo = false

    var body: some View {
        PageScrollView {
            LazyVStack(spacing: AppLayout.chapterSpacing) {
                awardsRow

                if let currentLesson = viewModel.currentLesson,
                   let currentPhase = viewModel.currentPhase {
                    continueCard(lesson: currentLesson, phase: currentPhase)

                    if let reviewLesson = suggestedReviewLesson(before: currentLesson) {
                        reviewNudge(lesson: reviewLesson)
                    }
                }

                ForEach(viewModel.phases) { phase in
                    phaseSection(phase)
                }
            }
            .padding(.top, 4)
            .pageContentInsets()
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAwards) {
            NavigationStack {
                AchievementGalleryView()
                    .appBackground(.subtle)
            }
        }
        .onAppear {
            viewModel.loadProgress(context: modelContext)
        }
        .alert("Lesson Locked", isPresented: $showingLockedInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Finish the earlier lessons first, each one builds on the last.")
        }
    }

    // MARK: - Awards Row

    /// The page's one header row: what the tab is, and the trophy.
    ///
    /// Learn hides the navigation bar like every root tab, so without a title
    /// here the page opened on a lone icon floating over empty space. Same
    /// grammar as Today's header — eyebrow, name, trailing accessory — and the
    /// trophy wears `headerIconChrome()`, so it is the same 44pt plate as the
    /// filter buttons on Prompts, Stories and History.
    private var awardsRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Learn")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.8)

                Text("Your path")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            Button {
                Haptics.light()
                showingAwards = true
            } label: {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(AppColors.scoreGood)
                    .headerIconChrome()
            }
            .accessibilityLabel("Achievements")
        }
        .padding(.top, 4)
    }

    // MARK: - Continue Card

    private func continueCard(lesson: CurriculumLesson, phase: CurriculumPhase) -> some View {
        let identity = LessonIdentity.forLesson(id: lesson.id)
        let isReviewing = viewModel.isLessonCompleted(lesson.id)

        return NavigationLink {
            LessonDetailView(lesson: lesson, viewModel: viewModel)
                .restoresNavigationBar()
        } label: {
            // Not `elevated`: the white `GlassButtonLabel` inside already casts
            // its own shadow, and stacking the heavy card shadow under it read
            // as a second, doubled edge. Same reasoning as `CoachFocusCard`.
            GlassCard(tint: identity.accent.opacity(0.08), padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: isReviewing ? "arrow.counterclockwise" : "play.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isReviewing ? "Review" : "Up next")
                            .font(.system(size: 10, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Spacer()
                        Text("\(viewModel.completedLessonsCount)/\(viewModel.totalLessonsCount) · Week \(phase.week)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(identity.accent.opacity(0.18))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(identity.accent.opacity(0.45), lineWidth: 1)
                                }

                            LessonGlyphView(identity: identity, state: isReviewing ? .completed : .current)
                                .frame(width: 32, height: 32)
                        }
                        .frame(width: 58, height: 58)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(lesson.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)

                            Text(lesson.objective)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GlassButtonLabel(
                        title: isReviewing
                            ? "Review · \(Self.lessonMeta(lesson))"
                            : "Continue · \(Self.lessonMeta(lesson))",
                        icon: isReviewing ? "arrow.counterclockwise" : "play.fill",
                        style: .primary,
                        fullWidth: true
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(
            isReviewing
                ? "Review \(lesson.title), \(Self.lessonMeta(lesson))"
                : "Continue \(lesson.title), \(Self.lessonMeta(lesson))"
        )
        .accessibilityHint(lesson.objective)
    }

    // MARK: - Review Nudge

    /// Prior completed lesson — keeps review in the first viewport, not buried in the path.
    private func suggestedReviewLesson(before current: CurriculumLesson) -> CurriculumLesson? {
        let ordered = viewModel.phases.flatMap(\.lessons)
        guard let index = ordered.firstIndex(where: { $0.id == current.id }), index > 0 else {
            return nil
        }
        return ordered[..<index].last(where: { viewModel.isLessonCompleted($0.id) })
    }

    private func reviewNudge(lesson: CurriculumLesson) -> some View {
        let identity = LessonIdentity.forLesson(id: lesson.id)

        return NavigationLink {
            LessonDetailView(lesson: lesson, viewModel: viewModel)
                .restoresNavigationBar()
        } label: {
            GlassCard(tint: identity.accent.opacity(0.06), padding: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(identity.accent.opacity(0.18))
                        LessonGlyphView(identity: identity, state: .completed, showsCheckBadge: true)
                            .frame(width: 22, height: 22)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Review last lesson")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(identity.accent)
                        Text(lesson.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Review last lesson, \(lesson.title)")
        .accessibilityHint(lesson.objective)
    }

    // MARK: - Phase Section

    private func phaseSection(_ phase: CurriculumPhase) -> some View {
        let completedInPhase = phase.lessons.filter { viewModel.isLessonCompleted($0.id) }.count
        let isLocked = !isPreviousPhaseCompleted(before: phase) && phase.week > 1
        let isPhaseComplete = completedInPhase == phase.lessons.count && !phase.lessons.isEmpty
        let phaseAccent = LessonIdentity.forPhase(week: phase.week)

        return VStack(alignment: .leading, spacing: 12) {
            phaseHeader(
                phase,
                completed: completedInPhase,
                isLocked: isLocked,
                isComplete: isPhaseComplete,
                accent: phaseAccent
            )

            VStack(spacing: 0) {
                ForEach(Array(phase.lessons.enumerated()), id: \.element.id) { index, lesson in
                    let isAccessible = viewModel.isLessonAccessible(lesson, in: phase)

                    if isAccessible {
                        NavigationLink {
                            LessonDetailView(lesson: lesson, viewModel: viewModel)
                                .restoresNavigationBar()
                        } label: {
                            lessonPathRow(lesson, at: index, in: phase, isLocked: false)
                        }
                        .buttonStyle(GlassPressStyle())
                    } else {
                        Button {
                            Haptics.warning()
                            showingLockedInfo = true
                        } label: {
                            lessonPathRow(lesson, at: index, in: phase, isLocked: true)
                        }
                        .buttonStyle(GlassPressStyle())
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func isLeading(_ index: Int) -> Bool { index.isMultiple(of: 2) }

    private func lessonPathRow(
        _ lesson: CurriculumLesson,
        at index: Int,
        in phase: CurriculumPhase,
        isLocked: Bool
    ) -> some View {
        let isCompleted = viewModel.isLessonCompleted(lesson.id)
        let isCurrent = viewModel.currentLesson?.id == lesson.id && !isCompleted && !isLocked
        let identity = LessonIdentity.forLesson(id: lesson.id)

        let state: LessonNodeState = {
            if isCompleted { return .completed }
            if isLocked { return .locked }
            if isCurrent { return .current }
            return .available
        }()
        let stateLabel: String = {
            switch state {
            case .completed: return "Completed, tap to review"
            case .locked: return "Locked"
            case .current: return "Current lesson"
            case .available: return "Available"
            }
        }()

        return LessonPathRow(
            state: state,
            identity: identity,
            isLeading: isLeading(index),
            hasNext: index < phase.lessons.count - 1,
            nextIsLeading: isLeading(index + 1)
        ) {
            lessonLabel(lesson, state: state, alignedLeading: isLeading(index))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lesson.title), \(stateLabel)")
        .accessibilityHint(lesson.objective)
    }

    private func lessonLabel(
        _ lesson: CurriculumLesson,
        state: LessonNodeState,
        alignedLeading: Bool
    ) -> some View {
        VStack(alignment: alignedLeading ? .leading : .trailing, spacing: 3) {
            Text(lesson.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(state == .locked ? Color.secondary : Color.white)

            Text(caption(for: lesson, state: state))
                .font(.caption)
                .foregroundStyle(state == .completed ? AppColors.success.opacity(0.9) : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(alignedLeading ? .leading : .trailing)
        .opacity(state == .locked ? 0.55 : 1.0)
    }

    private func caption(for lesson: CurriculumLesson, state: LessonNodeState) -> String {
        switch state {
        case .completed:
            return "Tap to review"
        case .current:
            return lesson.objective
        case .available:
            return Self.lessonMeta(lesson)
        case .locked:
            return lesson.objective
        }
    }

    private func phaseHeader(
        _ phase: CurriculumPhase,
        completed: Int,
        isLocked: Bool,
        isComplete: Bool,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent.opacity(isLocked ? 0.25 : 0.85))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text("Week \(phase.week)")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)

                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.success)
                } else if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                Text("\(completed)/\(phase.lessons.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isComplete ? AppColors.success : .secondary)
            }

            Text(phase.title)
                .font(.headline)
                .foregroundStyle(isLocked ? Color.secondary : Color.white)
                .fixedSize(horizontal: false, vertical: true)

            if !isComplete {
                Text(phase.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private static func lessonMeta(_ lesson: CurriculumLesson) -> String {
        let count = lesson.activities.count
        var parts = ["\(count) activit\(count == 1 ? "y" : "ies")"]

        let practiceSeconds = lesson.activities.compactMap(\.targetDuration).reduce(0, +)
        if practiceSeconds > 0 {
            let minutes = max(1, Int((Double(practiceSeconds) / 60).rounded()))
            parts.append("\(minutes) min practice")
        }

        return parts.joined(separator: " · ")
    }

    private func isPreviousPhaseCompleted(before phase: CurriculumPhase) -> Bool {
        guard let index = viewModel.phases.firstIndex(where: { $0.id == phase.id }),
              index > 0 else { return true }
        let previousPhase = viewModel.phases[index - 1]
        return previousPhase.lessons.allSatisfy { viewModel.isLessonCompleted($0.id) }
    }
}
