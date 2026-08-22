import SwiftUI
import SwiftData

struct CurriculumView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CurriculumViewModel()
    @State private var showingAwards = false
    @State private var showingLockedInfo = false

    var body: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                // Same grammar as Today: where you stand, then the one thing
                // to do next, then the browsable list. Previously two gradient
                // hero cards stacked here and competed for the same attention.
                LazyVStack(spacing: 20) {
                    progressHeader

                    if let currentLesson = viewModel.currentLesson,
                       let currentPhase = viewModel.currentPhase {
                        continueCard(lesson: currentLesson, phase: currentPhase)
                    }

                    ForEach(viewModel.phases) { phase in
                        phaseSection(phase)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Learning Path")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    showingAwards = true
                } label: {
                    Image(systemName: "trophy")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Achievements")
            }
        }
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

    // MARK: - Progress Header

    /// Stats card, not a hero. Same shape as the score hero on the detail
    /// screen: one dominant numeral, a tick meter, supporting counts.
    /// One row, not a card-sized dashboard.
    ///
    /// This used to be an eyebrow, a 46pt percentage, a lesson count, a week
    /// chip, and a full-width meter stacked in 20pt padding — the tallest thing
    /// on a screen whose actual content is the path below it. A small ring
    /// carries the fraction and the numeral at once, so the whole header costs
    /// one line.
    private var progressHeader: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RingProgress(
                        progress: viewModel.overallProgress,
                        color: AppColors.primary,
                        lineWidth: 4
                    )
                    Text("\(Int(viewModel.overallProgress * 100))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: viewModel.overallProgress))
                }
                .frame(width: 40, height: 40)

                Text("\(viewModel.completedLessonsCount) of \(viewModel.totalLessonsCount) lessons")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                if let week = viewModel.currentPhase?.week {
                    Text("Week \(week)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Course progress: \(Int(viewModel.overallProgress * 100)) percent, \(viewModel.completedLessonsCount) of \(viewModel.totalLessonsCount) lessons complete")
    }

    // MARK: - Continue Card

    /// The single action on this screen, styled like every other primary CTA
    /// in the app: light pill, ink text.
    private func continueCard(lesson: CurriculumLesson, phase: CurriculumPhase) -> some View {
        NavigationLink {
            LessonDetailView(lesson: lesson, viewModel: viewModel)
        } label: {
            GlassCard(padding: 18, elevated: true) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Up next")
                            .font(.system(size: 10, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Spacer()
                        Text("Week \(phase.week)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)

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

                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Continue · \(Self.lessonMeta(lesson))")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background { Capsule().fill(Color.white.opacity(0.94)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(GlassPressStyle())
    }

    // MARK: - Phase Section

    private func phaseSection(_ phase: CurriculumPhase) -> some View {
        let completedInPhase = phase.lessons.filter { viewModel.isLessonCompleted($0.id) }.count
        let isLocked = !isPreviousPhaseCompleted(before: phase) && phase.week > 1
        let isPhaseComplete = completedInPhase == phase.lessons.count && !phase.lessons.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            phaseHeader(
                phase,
                completed: completedInPhase,
                isLocked: isLocked,
                isComplete: isPhaseComplete
            )

            VStack(spacing: 0) {
                ForEach(Array(phase.lessons.enumerated()), id: \.element.id) { index, lesson in
                    let isAccessible = viewModel.isLessonAccessible(lesson, in: phase)

                    if isAccessible {
                        NavigationLink {
                            LessonDetailView(lesson: lesson, viewModel: viewModel)
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

    /// Nodes alternate sides down the scroll. The side is derived from the
    /// index rather than stored, so the rail and the node can never disagree.
    private func isLeading(_ index: Int) -> Bool { index.isMultiple(of: 2) }

    private func lessonPathRow(
        _ lesson: CurriculumLesson,
        at index: Int,
        in phase: CurriculumPhase,
        isLocked: Bool
    ) -> some View {
        let isCompleted = viewModel.isLessonCompleted(lesson.id)
        let isCurrent = viewModel.currentLesson?.id == lesson.id && !isCompleted && !isLocked

        let state: LessonNodeState = {
            if isCompleted { return .completed }
            if isLocked { return .locked }
            if isCurrent { return .current }
            return .available
        }()

        return LessonPathRow(
            state: state,
            icon: "text.book.closed",
            isLeading: isLeading(index),
            hasNext: index < phase.lessons.count - 1,
            nextIsLeading: isLeading(index + 1)
        ) {
            lessonLabel(lesson, isLocked: isLocked, alignedLeading: isLeading(index))
        }
    }

    /// Text hugs the node, so it flips alignment with it.
    private func lessonLabel(
        _ lesson: CurriculumLesson,
        isLocked: Bool,
        alignedLeading: Bool
    ) -> some View {
        VStack(alignment: alignedLeading ? .leading : .trailing, spacing: 3) {
            Text(lesson.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isLocked ? Color.secondary : Color.white)

            // The "N activities · M min practice" line was dropped from here.
            // Repeated down all 36 rows it read as texture rather than
            // information, and the Continue CTA above already states it for the
            // one lesson you're about to open — which is the only place the
            // number can still change a decision.
            Text(lesson.objective)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .multilineTextAlignment(alignedLeading ? .leading : .trailing)
        .opacity(isLocked ? 0.55 : 1.0)
    }

    /// One line of identity, one line of meaning. The original header carried a
    /// badge, a week label, a title, a count pill, a progress bar, and a
    /// description — six competing elements repeated per phase.
    private func phaseHeader(
        _ phase: CurriculumPhase,
        completed: Int,
        isLocked: Bool,
        isComplete: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.success)
                } else if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text("Week \(phase.week)")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)

                Text(phase.title)
                    .font(.headline)
                    .foregroundStyle(isLocked ? Color.secondary : Color.white)

                Spacer(minLength: 0)

                Text("\(completed)/\(phase.lessons.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isComplete ? AppColors.success : .secondary)
            }

            // Description only where it can still change a decision — on a
            // finished phase it is just noise above a list of checkmarks.
            //
            // The phase tick meter used to sit here too. With the course meter
            // in the header above and a "1/4" count on this very row, the page
            // was drawing the same fraction three ways before you reached a
            // single lesson. The count stays; the second meter goes.
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

    /// "3 activities · 4 min practice". Practice minutes come from the real
    /// `targetDuration` values, so the estimate never claims time the
    /// curriculum does not actually schedule.
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
