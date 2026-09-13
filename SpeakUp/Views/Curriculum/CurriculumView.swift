import SwiftUI
import SwiftData

/// Learn tab — skill studio of capability chapters. Detail: `LessonDetailView`.
///
/// Not a Duolingo-style path. Speaking gains come from proving one skill with your
/// voice, so the page surfaces outcomes and modalities (learn / drill / speak),
/// not decorative rails between nodes.
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
                    studioSessionCard(lesson: currentLesson, phase: currentPhase)

                    if let reviewLesson = suggestedReviewLesson(before: currentLesson) {
                        reinforceNudge(lesson: reviewLesson)
                    }
                }

                ForEach(viewModel.phases) { phase in
                    chapterSection(phase)
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
            Text("Finish the earlier lessons first — each skill builds on the last.")
        }
    }

    // MARK: - Header

    /// Page name + trophy. Learn hides the nav bar like every root tab.
    private var awardsRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Learn")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.8)

                Text("Skill studio")
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

    // MARK: - Studio Session

    /// One skill to prove with your voice. Outcome first; progress is accessory.
    private func studioSessionCard(lesson: CurriculumLesson, phase: CurriculumPhase) -> some View {
        let identity = LessonIdentity.forLesson(id: lesson.id)
        let isReviewing = viewModel.isLessonCompleted(lesson.id)

        return NavigationLink {
            LessonDetailView(lesson: lesson, viewModel: viewModel)
                .restoresNavigationBar()
        } label: {
            // Not `elevated`: white `GlassButtonLabel` already casts its own shadow.
            GlassCard(tint: identity.accent.opacity(0.08), padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: isReviewing ? "arrow.counterclockwise" : "mic.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isReviewing ? "Reinforce" : "Studio session")
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

                    Text(LessonTeachingCopy.roadmap(for: lesson))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    LessonModalityStrip(types: lesson.studioPlan)

                    GlassButtonLabel(
                        title: isReviewing
                            ? "Practice again · \(Self.lessonMeta(lesson))"
                            : "Start · \(Self.lessonMeta(lesson))",
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
                ? "Practice again \(lesson.title), \(Self.lessonMeta(lesson))"
                : "Start \(lesson.title), \(Self.lessonMeta(lesson))"
        )
        .accessibilityHint(lesson.objective)
    }

    // MARK: - Reinforce

    /// Prior completed lesson — keep review in the first viewport.
    private func suggestedReviewLesson(before current: CurriculumLesson) -> CurriculumLesson? {
        let ordered = viewModel.phases.flatMap(\.lessons)
        guard let index = ordered.firstIndex(where: { $0.id == current.id }), index > 0 else {
            return nil
        }
        return ordered[..<index].last(where: { viewModel.isLessonCompleted($0.id) })
    }

    private func reinforceNudge(lesson: CurriculumLesson) -> some View {
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
                        Text("Prove it again")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(identity.accent)
                        Text(lesson.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Text(lesson.objective)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "ear.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Prove it again, \(lesson.title)")
        .accessibilityHint(lesson.objective)
    }

    // MARK: - Capability Chapters

    private func chapterSection(_ phase: CurriculumPhase) -> some View {
        let completedInPhase = phase.lessons.filter { viewModel.isLessonCompleted($0.id) }.count
        let isLocked = !isPreviousPhaseCompleted(before: phase) && phase.week > 1
        let isPhaseComplete = completedInPhase == phase.lessons.count && !phase.lessons.isEmpty
        let phaseAccent = LessonIdentity.forPhase(week: phase.week)

        return VStack(alignment: .leading, spacing: 12) {
            chapterHeader(
                phase,
                completed: completedInPhase,
                isLocked: isLocked,
                isComplete: isPhaseComplete,
                accent: phaseAccent
            )

            VStack(spacing: 10) {
                ForEach(phase.lessons) { lesson in
                    let isAccessible = viewModel.isLessonAccessible(lesson, in: phase)

                    if isAccessible {
                        NavigationLink {
                            LessonDetailView(lesson: lesson, viewModel: viewModel)
                                .restoresNavigationBar()
                        } label: {
                            lessonStudioRow(lesson, in: phase, isLocked: false)
                        }
                        .buttonStyle(GlassPressStyle())
                    } else {
                        Button {
                            Haptics.warning()
                            showingLockedInfo = true
                        } label: {
                            lessonStudioRow(lesson, in: phase, isLocked: true)
                        }
                        .buttonStyle(GlassPressStyle())
                    }
                }
            }
        }
    }

    private func chapterHeader(
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

                Text("Chapter \(phase.week)")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Chapter \(phase.week), \(phase.title), \(completed) of \(phase.lessons.count) complete"
        )
    }

    private func lessonStudioRow(
        _ lesson: CurriculumLesson,
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
            case .current: return "Current skill"
            case .available: return "Available"
            }
        }()

        return GlassCard(
            tint: rowTint(for: state, accent: identity.accent),
            padding: 14
        ) {
            HStack(alignment: .top, spacing: 12) {
                lessonGlyphPlate(identity: identity, state: state)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(lesson.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(state == .locked ? Color.secondary : Color.white)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)

                        statusChip(for: state)
                    }

                    Text(lesson.objective)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(state == .locked ? 0.7 : 1)

                    HStack(spacing: 8) {
                        LessonModalityStrip(types: lesson.studioPlan, compact: true)
                        Spacer(minLength: 0)
                        Text(Self.lessonMeta(lesson))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .opacity(state == .locked ? 0.72 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lesson.title), \(stateLabel)")
        .accessibilityHint(lesson.objective)
    }

    private func lessonGlyphPlate(identity: LessonIdentity, state: LessonNodeState) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(glyphFill(for: state, accent: identity.accent))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(glyphStroke(for: state, accent: identity.accent), lineWidth: state == .current ? 2 : 1)
                }

            if state == .locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            } else if state == .current {
                ZStack {
                    LessonGlyphView(identity: identity, state: state)
                        .frame(width: 22, height: 22)
                        .opacity(0.35)
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(identity.accent)
                }
            } else {
                LessonGlyphView(
                    identity: identity,
                    state: state,
                    showsCheckBadge: state == .completed
                )
                .frame(width: 22, height: 22)
            }
        }
        .frame(width: 48, height: 48)
    }

    private func statusChip(for state: LessonNodeState) -> some View {
        Group {
            switch state {
            case .completed:
                Text("Spoken")
                    .foregroundStyle(AppColors.success)
            case .current:
                Text("Now")
                    .foregroundStyle(AppColors.primary)
            case .available:
                Text("Open")
                    .foregroundStyle(.tertiary)
            case .locked:
                Text("Locked")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .tracking(0.4)
    }

    private func rowTint(for state: LessonNodeState, accent: Color) -> Color {
        switch state {
        case .completed: return AppColors.success.opacity(0.06)
        case .current: return accent.opacity(0.10)
        case .available: return accent.opacity(0.05)
        case .locked: return .white.opacity(0.02)
        }
    }

    private func glyphFill(for state: LessonNodeState, accent: Color) -> Color {
        switch state {
        case .completed: return AppColors.success.opacity(0.18)
        case .current: return accent.opacity(0.22)
        case .available: return accent.opacity(0.12)
        case .locked: return .white.opacity(0.05)
        }
    }

    private func glyphStroke(for state: LessonNodeState, accent: Color) -> Color {
        switch state {
        case .completed: return AppColors.success.opacity(0.5)
        case .current: return accent
        case .available: return accent.opacity(0.4)
        case .locked: return AppColors.cardStroke
        }
    }

    // MARK: - Helpers

    private static func lessonMeta(_ lesson: CurriculumLesson) -> String {
        var parts: [String] = []

        let practiceSeconds = lesson.practiceSeconds
        if practiceSeconds > 0 {
            let minutes = max(1, Int((Double(practiceSeconds) / 60).rounded()))
            parts.append("\(minutes) min speak")
        } else {
            let count = lesson.activities.count
            parts.append("\(count) step\(count == 1 ? "" : "s")")
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

// MARK: - Modality Strip

/// Ordered unique activity roles for a lesson — the interactive plan at a glance.
struct LessonModalityStrip: View {
    let types: [CurriculumActivityType]
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(Array(types.enumerated()), id: \.offset) { index, type in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: compact ? 7 : 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 3) {
                    Image(systemName: type.teacherIcon)
                        .font(.system(size: compact ? 8 : 9, weight: .semibold))
                    Text(type.teacherRole)
                        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                }
                .foregroundStyle(type.teacherColor.opacity(0.95))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(types.map(\.teacherRole).joined(separator: ", then "))
    }
}
