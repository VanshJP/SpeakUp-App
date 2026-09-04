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
                // Continue first. Progress rides inside that card. The path
                // list follows — no intro card and no second stats card fighting
                // the one action that matters.
                LazyVStack(spacing: AppLayout.chapterSpacing) {
                    if let currentLesson = viewModel.currentLesson,
                       let currentPhase = viewModel.currentPhase {
                        continueCard(lesson: currentLesson, phase: currentPhase)
                    }

                    ForEach(viewModel.phases) { phase in
                        phaseSection(phase)
                    }
                }
                .padding(.top, 4)
                .pageContentInsets()
            }
            .scrollIndicators(.hidden)
        }
        // No root title — the tab bar already says Learn. "Learning Path" as a
        // large title left the trophy alone on an empty nav row with the name
        // dropped underneath. Continue card is the page's first voice.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    showingAwards = true
                } label: {
                    // Gold and filled: awards are the one celebratory affordance
                    // in the chrome, so it reads as a prize rather than a setting.
                    Image(systemName: "trophy.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.scoreGood)
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

    // MARK: - Continue Card

    /// The single action on this screen. Progress is a quiet accessory in the
    /// header row so the primary CTA is not buried under intro + stats cards.
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
                        Text("\(viewModel.completedLessonsCount)/\(viewModel.totalLessonsCount) · Week \(phase.week)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
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

                    GlassButtonLabel(
                        title: "Continue · \(Self.lessonMeta(lesson))",
                        icon: "play.fill",
                        style: .primary,
                        fullWidth: true
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Continue \(lesson.title), \(Self.lessonMeta(lesson))")
        .accessibilityHint(lesson.objective)
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
        let stateLabel: String = {
            switch state {
            case .completed: return "Completed"
            case .locked: return "Locked"
            case .current: return "Current lesson"
            case .available: return "Available"
            }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lesson.title), \(stateLabel)")
        .accessibilityHint(lesson.objective)
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
                .fixedSize(horizontal: false, vertical: true)
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
