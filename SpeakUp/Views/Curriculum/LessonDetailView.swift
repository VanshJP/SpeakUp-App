import SwiftUI
import SwiftData

struct LessonDetailView: View {
    @Bindable var viewModel: CurriculumViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var userSettings: [UserSettings]
    /// Only the newest three are shown. Unbounded, this loaded every take on
    /// the main thread again on each save - several per lesson take while it
    /// scores under this page.
    @Query(LessonDetailView.recentRecordingsDescriptor) private var recentRecordings: [Recording]

    private static var recentRecordingsDescriptor: FetchDescriptor<Recording> {
        var descriptor = FetchDescriptor<Recording>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 3
        return descriptor
    }

    /// Mutable so "Next Lesson" can swap in place instead of dismissing back to the path.
    @State private var lesson: CurriculumLesson
    /// Seeded in `init`, never in `.onAppear`: popping a review take off the
    /// stack re-fires `onAppear`, and re-seeding there threw a finished lesson
    /// back to step 1.
    @State private var currentStepIndex: Int
    @State private var activeSheet: ActiveSheet?
    @State private var practiceResult: Recording?
    @State private var showingLessonCompletion = false
    @State private var showingBeforeAfter = false
    /// Set when a calm exercise reaches its last step. The step completes as
    /// the exercise closes, the way a warm-up's does.
    @State private var confidenceExerciseFinished = false
    @State private var stepCompleteMessage: String?
    @State private var completedActivityIds: Set<String>
    @State private var reviewTarget: ReviewTarget?
    /// Whether the lesson was already finished when it opened - captured, not
    /// computed. Finishing the last step completes the lesson too, and a live
    /// check swapped "Finish lesson" for "Done reviewing" at that moment, so
    /// the completion screen never showed.
    @State private var isRevisitingCompletedLesson: Bool

    private struct ReviewTarget: Identifiable, Hashable {
        let id: UUID
    }

    /// Reviews that compare the first take with the latest. The review list
    /// holds only the newest three, so these also open the then-and-now replay.
    private static let beforeAfterReviewIds: Set<String> = ["w4_l3_a2", "w4_l4_a1", "w8_l4_a1"]

    init(lesson: CurriculumLesson, viewModel: CurriculumViewModel) {
        self.viewModel = viewModel
        _lesson = State(initialValue: lesson)
        _currentStepIndex = State(initialValue: viewModel.initialStepIndex(for: lesson))
        _completedActivityIds = State(initialValue: Self.completedIds(in: lesson, viewModel: viewModel))
        _isRevisitingCompletedLesson = State(initialValue: viewModel.isLessonCompleted(lesson.id))
    }

    private static func completedIds(in lesson: CurriculumLesson, viewModel: CurriculumViewModel) -> Set<String> {
        Set(lesson.activities.filter { viewModel.isActivityCompleted($0.id) }.map(\.id))
    }

    private var lessonIdentity: LessonIdentity {
        LessonIdentity.forLesson(id: lesson.id)
    }

    // MARK: - ActiveSheet

    enum ActiveSheet: Identifiable {
        /// A lesson take. `brief` is the practice task, shown in the recorder.
        /// `opensAsPage` marks a repeat started from a take's own page: its
        /// result replaces that page instead of landing in the practice card.
        case recording(
            duration: RecordingDuration,
            framework: SpeechFramework?,
            prompt: Prompt? = nil,
            storyId: UUID? = nil,
            brief: String? = nil,
            opensAsPage: Bool = false
        )
        case drill(DrillViewModel)
        case warmUp(WarmUpViewModel)
        case confidence(ConfidenceExercise)

        var id: String {
            switch self {
            case .recording: return "recording"
            case .drill: return "drill"
            case .warmUp: return "warmUp"
            case .confidence(let ex): return "confidence_\(ex.id)"
            }
        }
    }

    private var currentActivity: CurriculumActivity {
        lesson.activities[currentStepIndex]
    }

    private var allActivitiesComplete: Bool {
        lesson.activities.allSatisfy { viewModel.isActivityCompleted($0.id) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if showingLessonCompletion {
                LessonCompletionView(
                    lesson: lesson,
                    nextLesson: viewModel.nextLesson(after: lesson.id),
                    onNextLesson: {
                        advanceToNextLessonInPlace()
                    },
                    onBackToCurriculum: {
                        dismiss()
                    }
                )
                // The step counter and its menu belong to the steps. Over the
                // completion screen the menu jumped to steps it could not show.
                .navigationTitle("Lesson complete")
            } else {
                lessonContent
                    .navigationTitle(stepTitle)
                    .toolbarTitleMenu { stepMenu }
            }

            // Step completion toast
            if let message = stepCompleteMessage {
                stepCompleteToast(message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .appBackground(.subtle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .fullScreenCover(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .sheet(isPresented: $showingBeforeAfter) {
            BeforeAfterReplayView()
        }
        .navigationDestination(item: $reviewTarget) { target in
            RecordingDetailView(
                recordingId: target.id.uuidString,
                source: .learn,
                onPracticeAgain: { recording in
                    // History's mapping: the take's own subject and length,
                    // so a Story take repeats its Story, not free talk.
                    activeSheet = .recording(
                        duration: RecordingDuration(rawValue: recording.targetDuration) ?? .sixty,
                        framework: SpeechFramework.fromCurriculumHint(recording.frameworkUsed),
                        prompt: recording.storyId == nil ? recording.prompt : nil,
                        storyId: recording.storyId,
                        opensAsPage: true
                    )
                }
            )
            // A repeat swaps this page for the new take. A fresh identity makes
            // the detail load that take instead of keeping the old one's state.
            .id(target.id)
            .restoresNavigationBar()
        }
        .onChange(of: practiceResult?.overallScore) {
            completePracticeIfScored(practiceResult)
        }
    }

    /// Swap this detail onto the next lesson without popping the nav stack.
    /// Dismiss only when the path is finished. Finishing the last step already
    /// moved the current lesson on (`CurriculumService.recordActivityCompletion`),
    /// so this moves the page, never the progress - doing both skipped a lesson.
    private func advanceToNextLessonInPlace() {
        guard let next = viewModel.nextLesson(after: lesson.id) else {
            dismiss()
            return
        }
        withAnimation(AppMotion.slide) {
            lesson = next
            isRevisitingCompletedLesson = viewModel.isLessonCompleted(next.id)
            showingLessonCompletion = false
            practiceResult = nil
            confidenceExerciseFinished = false
            activeSheet = nil
            stepCompleteMessage = nil
            currentStepIndex = viewModel.initialStepIndex(for: next)
            completedActivityIds = Self.completedIds(in: next, viewModel: viewModel)
        }
        Haptics.medium()
    }

    // MARK: - Step Complete Toast

    private func stepCompleteToast(_ message: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColors.success)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            // Not `.interactive()`: the toast is not a control.
            .glassEffect(.regular, in: .capsule)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .padding(.top, 8)

            Spacer()
        }
    }

    private func showStepCompletion() {
        let role = currentActivity.type.teacherRole
        let messages = [
            "\(role) done. Nice.",
            "Solid \(role.lowercased()).",
            "Locked in.",
            "That's the move.",
            "Keep that focus.",
        ]
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            stepCompleteMessage = messages[abs(currentActivity.id.hashValue) % messages.count]
        }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.3)) {
                stepCompleteMessage = nil
            }
        }
    }

    private func completeCurrentActivity() {
        let activityId = currentActivity.id
        viewModel.completeActivity(activityId, context: modelContext)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            _ = completedActivityIds.insert(activityId)
        }
        Haptics.success()
        showStepCompletion()
    }

    // MARK: - Lesson Takes

    /// Every lesson take lands here - from its result, or from Save & close
    /// while it is still analyzing. It counts as the day's session, like a
    /// take from Today. A finished take also gets Today's achievement check;
    /// a saved one waits for the next check, so no unlock interrupts a close.
    private func takeLanded(_ recording: Recording, opensAsPage: Bool, isFinished: Bool) {
        PracticeRoutineService.shared.complete(.session)
        if isFinished {
            Task { await AchievementService.shared.checkAchievements(context: modelContext) }
        }
        titleLessonTake(recording)
        if opensAsPage {
            reviewTarget = ReviewTarget(id: recording.id)
        } else {
            practiceResult = recording
        }
        completePracticeIfScored(recording)
        activeSheet = nil
    }

    /// A practice step finishes on a take that scored. An empty take - the
    /// zero-word gate scores 0 - leaves it open with the launch card still up
    /// for the retake. One still analyzing finishes when its score lands
    /// (`onChange(of: practiceResult?.overallScore)`); the history scan
    /// settles one that lands after you leave.
    private func completePracticeIfScored(_ recording: Recording?) {
        guard currentActivity.type == .practice,
              let score = recording?.overallScore, score > 0,
              !viewModel.isActivityCompleted(currentActivity.id) else { return }
        completeCurrentActivity()
    }

    /// A lesson take has no prompt, so History and the review list here
    /// called every one "Practice Session". It takes the activity's name.
    private func titleLessonTake(_ recording: Recording) {
        guard currentActivity.type == .practice,
              recording.prompt == nil, recording.storyId == nil,
              recording.customTitle?.isEmpty ?? true else { return }
        recording.customTitle = currentActivity.title
        try? modelContext.save()
    }

    // MARK: - Lesson Content

    private var resolvedCompletedIds: Set<String> {
        completedActivityIds.union(
            Set(lesson.activities.filter { viewModel.isActivityCompleted($0.id) }.map(\.id))
        )
    }

    private var lessonContent: some View {
        ScrollViewReader { proxy in
            PageScrollView {
                VStack(spacing: 14) {
                    Color.clear
                        .frame(height: 0)
                        .id("scrollTop")

                    LessonBoardHeader(
                        lesson: lesson,
                        identity: lessonIdentity,
                        isReviewing: isRevisitingCompletedLesson,
                        isCompact: currentStepIndex > 0
                    )

                    // A reading needs no cue: its header says "Learn · 2 min
                    // read", and "Read this first" under the roadmap's "We'll
                    // learn, then practice" said the plan a second time.
                    if currentActivity.type != .lesson {
                        LessonCoachCue(activity: currentActivity)
                    }

                    activityContent(for: currentActivity)

                    Spacer().frame(height: 16)
                }
                .padding(.horizontal, AppLayout.pageHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: currentStepIndex) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("scrollTop", anchor: .top)
                }
            }
        }
        // A bar, not an inset: the lesson scrolls under it with the same soft
        // edge the tab bar gives, where a material slab sat as a flat grey band
        // across the navy canvas.
        .safeAreaBar(edge: .bottom, spacing: 0) {
            bottomBar
        }
    }

    // MARK: - Activity Content Dispatch

    @ViewBuilder
    private func activityContent(for activity: CurriculumActivity) -> some View {
        let isCompleted = viewModel.isActivityCompleted(activity.id)

        switch activity.type {
        case .lesson:
            lessonActivityContent(activity, isCompleted: isCompleted)
        case .practice:
            practiceActivityContent(activity, isCompleted: isCompleted)
        case .drill:
            drillActivityContent(activity, isCompleted: isCompleted)
        case .exercise:
            exerciseActivityContent(activity, isCompleted: isCompleted)
        case .review:
            reviewActivityContent(activity, isCompleted: isCompleted)
        }
    }

    // MARK: - Lesson Activity

    private func lessonActivityContent(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            activityHeader(activity, isCompleted: isCompleted)

            if let content = activity.content {
                // One soft arrival for the whole reading, under a header that
                // is already there. A per-section cascade made the reader wait
                // on text that was already written.
                LessonContentView(content: content, accent: lessonIdentity.accent)
                    .introReveal()
            }
        }
    }

    // MARK: - Practice Activity

    private func practiceActivityContent(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        VStack(spacing: 16) {
            activityHeader(activity, isCompleted: isCompleted)

            if let result = practiceResult {
                practiceResultButton(result, activity: activity)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // Stays up under an empty take's result, so the retake is one tap.
            if !isCompleted {
                practiceLaunchCard(activity)
            } else if practiceResult == nil {
                repeatButton(for: activity)
            }
        }
    }

    /// The result opens the take's full page - playback, transcript, the next
    /// step. The card on its own was a dead end.
    private func practiceResultButton(_ result: Recording, activity: CurriculumActivity) -> some View {
        Button {
            Haptics.light()
            reviewTarget = ReviewTarget(id: result.id)
        } label: {
            PracticeResultsCard(recording: result, activity: activity)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityHint("Opens the full breakdown")
    }

    /// Launch controls only. The activity header above already prints the
    /// description and the board prints the objective; this card reprinting
    /// both is why the practice step read as the same paragraph three times.
    private func practiceLaunchCard(_ activity: CurriculumActivity) -> some View {
        GlassCard(tint: AppColors.primary.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 14) {
                if activity.targetDuration != nil || activity.frameworkHint != nil {
                    HStack(spacing: 16) {
                        if let duration = activity.targetDuration {
                            Label(durationLabel(duration), systemImage: "timer")
                        }

                        if let framework = activity.frameworkHint {
                            Label(framework, systemImage: "rectangle.3.group")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                GlassButton(title: "Start practice", icon: "mic.fill", style: .primary, fullWidth: true) {
                    Haptics.medium()
                    activeSheet = practiceSheet(for: activity)
                }
            }
        }
    }

    private func practiceSheet(for activity: CurriculumActivity) -> ActiveSheet {
        .recording(
            duration: recordingDuration(from: activity.targetDuration),
            framework: SpeechFramework.fromCurriculumHint(activity.frameworkHint),
            brief: activity.description
        )
    }

    // MARK: - Drill Activity

    private func drillActivityContent(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        VStack(spacing: 16) {
            activityHeader(activity, isCompleted: isCompleted)

            if !isCompleted, let modeRaw = activity.drillMode, let mode = DrillMode(rawValue: modeRaw) {
                drillLaunchCard(mode: mode)
            } else {
                repeatButton(for: activity)
            }
        }
    }

    private func drillLaunchCard(mode: DrillMode) -> some View {
        GlassCard(tint: mode.color.opacity(0.06)) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    IconChip(icon: mode.icon, tint: mode.color, size: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.title)
                            .font(.subheadline.weight(.semibold))

                        Text(mode.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                GlassButton(title: "Start drill", icon: "bolt.fill", style: .primary, fullWidth: true) {
                    Haptics.medium()
                    startDrill(mode)
                }
            }
        }
    }

    private func startDrill(_ mode: DrillMode) {
        let vm = DrillViewModel()
        vm.targetWPM = userSettings.first.resolvedTargetWPM
        vm.startDrill(mode: mode)
        activeSheet = .drill(vm)
    }

    // MARK: - Exercise Activity

    /// A done exercise shows nothing under its header: the Done pill says it.
    private func exerciseActivityContent(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        VStack(spacing: 16) {
            activityHeader(activity, isCompleted: isCompleted)

            if !isCompleted, let exerciseId = activity.exerciseId {
                if let warmUp = DefaultWarmUps.all.first(where: { $0.id == exerciseId }) {
                    exerciseLaunchCard(
                        icon: warmUp.category.icon,
                        tint: warmUp.category.color,
                        title: warmUp.title,
                        detail: warmUp.instructions
                    ) {
                        let vm = WarmUpViewModel()
                        vm.selectExercise(warmUp)
                        activeSheet = .warmUp(vm)
                    }
                } else if let calm = DefaultConfidenceExercises.all.first(where: { $0.id == exerciseId }) {
                    exerciseLaunchCard(
                        icon: calm.category.icon,
                        tint: calm.category.color,
                        title: calm.title,
                        detail: calm.description
                    ) {
                        activeSheet = .confidence(calm)
                    }
                }
            }
        }
    }

    /// Warm-up and calm launch. The chip is the exercise's own category badge,
    /// the one it wears in Library, not a stand-in per screen.
    private func exerciseLaunchCard(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        start: @escaping () -> Void
    ) -> some View {
        GlassCard(tint: tint.opacity(0.06)) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    IconChip(icon: icon, tint: tint, size: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))

                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                GlassButton(title: "Start exercise", icon: "play.fill", style: .primary, fullWidth: true) {
                    Haptics.medium()
                    start()
                }
            }
        }
    }

    // MARK: - Review Activity

    private func reviewActivityContent(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        let snapshots = Array(recentRecordings.prefix(3))

        return VStack(spacing: 16) {
            activityHeader(activity, isCompleted: isCompleted)

            // The lens only. The header above already says what to do, and its
            // Done pill says when it is done.
            GlassCard(tint: lessonIdentity.accent.opacity(0.06)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Listen for")
                        .eyebrowStyle(lessonIdentity.accent)

                    Text(lesson.objective)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if Self.beforeAfterReviewIds.contains(activity.id) {
                GlassButton(
                    title: "Play then and now",
                    icon: "arrow.left.arrow.right",
                    style: .secondary,
                    fullWidth: true
                ) {
                    Haptics.light()
                    showingBeforeAfter = true
                }
            }

            if snapshots.isEmpty {
                Text("Record a practice take first, then come back and listen with this lens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // One plate of rows, like History's weeks - not rows loose
                // inside the lens card, where they pressed with no feedback.
                GlassRowGroup(dividerInset: 52) {
                    ForEach(snapshots, id: \.id) { recording in
                        reviewRow(recording)
                    }
                }
            }

            if !isCompleted {
                GlassButton(title: "I reviewed these", icon: "checkmark", style: .primary, fullWidth: true) {
                    completeCurrentActivity()
                }
            }
        }
    }

    private func reviewRow(_ recording: Recording) -> some View {
        let date = recording.date.formatted(date: .abbreviated, time: .omitted)
        let spokenScore = recording.overallScore.map { ", score \($0)" } ?? ""

        return Button {
            Haptics.light()
            reviewTarget = ReviewTarget(id: recording.id)
        } label: {
            HStack(spacing: 10) {
                IconChip(icon: "waveform", tint: lessonIdentity.accent, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(recording.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let score = recording.overallScore {
                    Text("\(score)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppColors.scoreColor(for: score))
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: AppLayout.minHitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("\(recording.displayTitle), \(date)\(spokenScore)")
        .accessibilityHint("Opens the take")
    }

    // MARK: - Shared Subviews

    /// Role and Done on one line, then the title and description at full
    /// width. The chip used to sit beside the text and indent every line of
    /// it by a glyph's width, so the header never lined up with the reading.
    private func activityHeader(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconChip(icon: activity.type.teacherIcon, tint: activity.type.teacherColor, size: 28)

                headerKicker(for: activity)
                    .eyebrowStyle(activity.type.teacherColor)

                Spacer(minLength: 8)

                if isCompleted {
                    StatusPill(text: "Done", color: AppColors.success, glyph: .icon("checkmark"))
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(activity.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(activity.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCompleted)
    }

    /// "Learn · 2 min read" - a reading says how long it is up front.
    private func headerKicker(for activity: CurriculumActivity) -> Text {
        let role = activity.type.teacherRole
        guard let minutes = activity.content?.readingMinutes else { return Text(role) }
        return Text("\(role) · \(minutes) min read")
            .accessibilityLabel("\(role), \(minutes) minute read")
    }

    /// A done practice or drill step offers the rep again, and nothing else:
    /// the header's Done pill already says it is done, with the description
    /// right above it. The "Completed" card here said both a second time.
    @ViewBuilder
    private func repeatButton(for activity: CurriculumActivity) -> some View {
        switch activity.type {
        case .practice:
            GlassButton(
                title: "Practice again",
                icon: "mic.fill",
                style: repeatOwnsPrimary ? .primary : .secondary,
                fullWidth: true
            ) {
                Haptics.medium()
                activeSheet = practiceSheet(for: activity)
            }
            .transition(.opacity)
        case .drill:
            if let modeRaw = activity.drillMode, let mode = DrillMode(rawValue: modeRaw) {
                GlassButton(title: "Drill again", icon: "bolt.fill", style: .secondary, fullWidth: true) {
                    Haptics.medium()
                    startDrill(mode)
                }
                .transition(.opacity)
            }
        default:
            EmptyView()
        }
    }

    /// Revisiting a finished lesson opens on its practice step, and there
    /// "Practice again" is why you came back: it takes the page's one white
    /// CTA and the bottom bar steps down to secondary.
    private var repeatOwnsPrimary: Bool {
        isRevisitingCompletedLesson
            && currentActivity.type == .practice
            && practiceResult == nil
            && viewModel.isActivityCompleted(currentActivity.id)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            LessonProgressTrack(
                total: lesson.activities.count,
                currentIndex: currentStepIndex,
                completedIds: resolvedCompletedIds,
                activityIds: lesson.activities.map(\.id),
                accent: lessonIdentity.accent
            )

            bottomBarActions
        }
        .padding(.horizontal, AppLayout.pageHorizontal)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var bottomBarActions: some View {
        let isCurrentComplete = viewModel.isActivityCompleted(currentActivity.id)
        let isLastStep = currentStepIndex >= lesson.activities.count - 1
        let barStyle: GlassButton.GlassButtonVariant = repeatOwnsPrimary ? .secondary : .primary

        Group {
            if isLastStep && allActivitiesComplete {
                if isRevisitingCompletedLesson {
                    GlassButton(title: "Done reviewing", icon: "checkmark", style: barStyle, fullWidth: true) {
                        Haptics.light()
                        dismiss()
                    }
                } else {
                    GlassButton(title: "Finish lesson", icon: "flag.checkered", style: .primary, fullWidth: true) {
                        Haptics.success()
                        withAnimation(.spring(response: 0.4)) {
                            showingLessonCompletion = true
                        }
                    }
                }
            } else if currentActivity.type == .lesson && !isCurrentComplete {
                GlassButton(title: "Got it", icon: "checkmark", style: .primary, fullWidth: true) {
                    completeCurrentActivity()
                    advanceStep()
                }
            } else if isCurrentComplete && !isLastStep {
                GlassButton(
                    title: LessonTeachingCopy.nextCTA(after: currentStepIndex, in: lesson),
                    icon: "arrow.right",
                    iconPosition: .right,
                    style: barStyle,
                    fullWidth: true
                ) {
                    Haptics.light()
                    advanceStep()
                }
            } else if isCurrentComplete && isLastStep, let openIndex = viewModel.firstOpenStepIndex(for: lesson) {
                // The last step is done and an earlier one is not - reachable by
                // jumping ahead from the title menu. "Wrap up" no-oped here.
                GlassButton(
                    title: "Finish step \(openIndex + 1)",
                    icon: "arrow.uturn.backward",
                    style: .primary,
                    fullWidth: true
                ) {
                    Haptics.light()
                    goToStep(openIndex)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isActivityCompleted(currentActivity.id))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentStepIndex)
    }

    // MARK: - Navigation

    /// "Learn · 1 of 2". Its title menu is the way back to a step already
    /// reached - it replaced a strip of step tiles under the lesson board that
    /// drew the same facts as this title and the bottom bar's track.
    private var stepTitle: String {
        "\(currentActivity.type.teacherRole) · \(currentStepIndex + 1) of \(lesson.activities.count)"
    }

    @ViewBuilder
    private var stepMenu: some View {
        ForEach(Array(lesson.activities.enumerated()), id: \.element.id) { index, activity in
            let isDone = resolvedCompletedIds.contains(activity.id)
            Button {
                Haptics.light()
                goToStep(index)
            } label: {
                Label(
                    "\(index + 1). \(activity.type.teacherRole)",
                    systemImage: isDone ? "checkmark.circle.fill" : activity.type.teacherIcon
                )
            }
            // Only steps already reached; the lesson is taught in order.
            .disabled(index == currentStepIndex || !(isDone || index < currentStepIndex))
        }
    }

    private func advanceStep() {
        guard currentStepIndex < lesson.activities.count - 1 else {
            if allActivitiesComplete {
                withAnimation(.spring(response: 0.4)) {
                    showingLessonCompletion = true
                }
            }
            return
        }
        goToStep(currentStepIndex + 1)
    }

    private func goToStep(_ index: Int) {
        practiceResult = nil
        currentStepIndex = index
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .recording(let duration, let framework, let prompt, let storyId, let brief, let opensAsPage):
            RecordingView(
                prompt: prompt,
                duration: duration,
                timerEndBehavior: timerEndBehavior,
                countdownStyle: countdownStyle,
                storyId: storyId,
                initialFramework: framework,
                brief: brief,
                onSavedAndClosed: { recording in
                    takeLanded(recording, opensAsPage: opensAsPage, isFinished: false)
                },
                onComplete: { recording in
                    takeLanded(recording, opensAsPage: opensAsPage, isFinished: true)
                },
                onCancel: {
                    activeSheet = nil
                }
            )
        case .drill(let vm):
            DrillSessionView(viewModel: vm)
                .onDisappear {
                    if vm.isComplete {
                        completeCurrentActivity()
                    }
                }
        case .warmUp(let vm):
            WarmUpExerciseView(viewModel: vm)
                .onDisappear {
                    if vm.isComplete {
                        completeCurrentActivity()
                    }
                }
        case .confidence(let exercise):
            ConfidenceExerciseView(exercise: exercise, onComplete: {
                confidenceExerciseFinished = true
            })
            .onDisappear {
                guard confidenceExerciseFinished else { return }
                confidenceExerciseFinished = false
                CurriculumActivitySignalStore.markExerciseCompleted(exercise.id)
                completeCurrentActivity()
            }
        }
    }

    // MARK: - Helpers

    /// The user's session defaults, as Today's takes get them.
    private var timerEndBehavior: TimerEndBehavior {
        TimerEndBehavior(rawValue: userSettings.first?.timerEndBehavior ?? 0) ?? .saveAndStop
    }

    private var countdownStyle: CountdownStyle {
        CountdownStyle(rawValue: userSettings.first?.countdownStyle ?? 0) ?? .countDown
    }

    private func recordingDuration(from seconds: Int?) -> RecordingDuration {
        guard let seconds else { return .sixty }
        switch seconds {
        case ...30: return .thirty
        case 31...60: return .sixty
        case 61...90: return .ninety
        case 91...120: return .onetwenty
        case 121...180: return .threeMinutes
        case 181...300: return .fiveMinutes
        default: return .tenMinutes
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let mins = seconds / 60
            let secs = seconds % 60
            return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
        }
    }
}
