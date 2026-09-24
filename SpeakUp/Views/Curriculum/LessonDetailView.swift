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
    @State private var currentStepIndex: Int = 0
    @State private var activeSheet: ActiveSheet?
    @State private var practiceResult: Recording?
    @State private var showingLessonCompletion = false
    @State private var confidenceExerciseOpened = false
    @State private var stepCompleteMessage: String?
    @State private var completedActivityIds: Set<String> = []
    @State private var reviewTarget: ReviewTarget?

    private struct ReviewTarget: Identifiable, Hashable {
        let id: UUID
    }

    init(lesson: CurriculumLesson, viewModel: CurriculumViewModel) {
        self.viewModel = viewModel
        _lesson = State(initialValue: lesson)
    }

    private var lessonIdentity: LessonIdentity {
        LessonIdentity.forLesson(id: lesson.id)
    }

    private var isRevisitingCompletedLesson: Bool {
        viewModel.isLessonCompleted(lesson.id)
    }

    // MARK: - ActiveSheet

    enum ActiveSheet: Identifiable {
        case recording(duration: RecordingDuration, framework: SpeechFramework?)
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
            AppBackground()

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
            } else {
                lessonContent
            }

            // Step completion toast
            if let message = stepCompleteMessage {
                stepCompleteToast(message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .navigationTitle(stepTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarTitleMenu { stepMenu }
        .fullScreenCover(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .navigationDestination(item: $reviewTarget) { target in
            RecordingDetailView(
                recordingId: target.id.uuidString,
                source: .learn,
                onPracticeAgain: { recording in
                    activeSheet = .recording(
                        duration: RecordingDuration(rawValue: recording.targetDuration) ?? .sixty,
                        framework: SpeechFramework.fromCurriculumHint(recording.frameworkUsed)
                    )
                }
            )
                .restoresNavigationBar()
        }
        .onAppear {
            currentStepIndex = viewModel.initialStepIndex(for: lesson)
            completedActivityIds = Set(lesson.activities.filter { viewModel.isActivityCompleted($0.id) }.map(\.id))
        }
    }

    /// Swap this detail onto the next lesson without popping the nav stack.
    /// Dismiss only when the path is finished.
    private func advanceToNextLessonInPlace() {
        guard let next = viewModel.nextLesson(after: lesson.id) else {
            viewModel.advanceToNextLesson(context: modelContext)
            dismiss()
            return
        }
        viewModel.advanceToNextLesson(context: modelContext)
        withAnimation(AppMotion.slide) {
            lesson = next
            showingLessonCompletion = false
            practiceResult = nil
            confidenceExerciseOpened = false
            activeSheet = nil
            stepCompleteMessage = nil
            currentStepIndex = viewModel.initialStepIndex(for: next)
            completedActivityIds = Set(
                next.activities.filter { viewModel.isActivityCompleted($0.id) }.map(\.id)
            )
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
            .glassEffect(.regular.interactive(), in: .capsule)
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

                    LessonCoachCue(activity: currentActivity)

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
        VStack(spacing: 16) {
            activityHeader(activity, isCompleted: isCompleted)

            if let content = activity.content {
                LessonContentView(content: content)
            } else {
                GlassCard {
                    Text(activity.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Practice Activity

    private func practiceActivityContent(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        VStack(spacing: 16) {
            activityHeader(activity, isCompleted: isCompleted)

            if let result = practiceResult {
                PracticeResultsCard(recording: result, activity: activity)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else if !isCompleted {
                practiceLaunchCard(activity)
            } else {
                completedCard(activity)
            }
        }
    }

    /// Launch controls only. The activity header above already prints the
    /// description and the board prints the objective; this card reprinting
    /// both is why the practice step read as the same paragraph three times.
    private func practiceLaunchCard(_ activity: CurriculumActivity) -> some View {
        GlassCard(tint: AppColors.glassTintPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                if activity.targetDuration != nil || activity.frameworkHint != nil {
                    HStack(spacing: 16) {
                        if let duration = activity.targetDuration {
                            Label("\(durationLabel(duration))", systemImage: "timer")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppColors.primary)
                        }

                        if let framework = activity.frameworkHint {
                            Label(framework, systemImage: "rectangle.3.group")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppColors.categoryNeutralCool)
                        }
                    }
                }

                GlassButton(title: "Start practice", icon: "mic.fill", style: .primary, fullWidth: true) {
                    Haptics.medium()
                    let duration = recordingDuration(from: activity.targetDuration)
                    activeSheet = .recording(
                        duration: duration,
                        framework: SpeechFramework.fromCurriculumHint(activity.frameworkHint)
                    )
                }
            }
        }
    }

    // MARK: - Drill Activity

    private func drillActivityContent(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        VStack(spacing: 16) {
            activityHeader(activity, isCompleted: isCompleted)

            if !isCompleted, let modeRaw = activity.drillMode, let mode = DrillMode(rawValue: modeRaw) {
                drillLaunchCard(activity: activity, mode: mode)
            } else {
                completedCard(activity)
            }
        }
    }

    private func drillLaunchCard(activity: CurriculumActivity, mode: DrillMode) -> some View {
        GlassCard(tint: AppColors.warning.opacity(0.08)) {
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
                    let vm = DrillViewModel()
                    vm.targetWPM = userSettings.first.resolvedTargetWPM
                    vm.startDrill(mode: mode)
                    activeSheet = .drill(vm)
                }
            }
        }
    }

    // MARK: - Exercise Activity

    private func exerciseActivityContent(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        VStack(spacing: 16) {
            activityHeader(activity, isCompleted: isCompleted)

            if !isCompleted, let exerciseId = activity.exerciseId {
                if let warmUp = DefaultWarmUps.all.first(where: { $0.id == exerciseId }) {
                    warmUpLaunchCard(activity: activity, exercise: warmUp)
                } else if let confidence = DefaultConfidenceExercises.all.first(where: { $0.id == exerciseId }) {
                    confidenceLaunchCard(activity: activity, exercise: confidence)
                } else {
                    completedCard(activity)
                }
            } else {
                completedCard(activity)
            }
        }
    }

    private func warmUpLaunchCard(activity: CurriculumActivity, exercise: WarmUpExercise) -> some View {
        GlassCard(tint: AppColors.success.opacity(0.08)) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    IconChip(icon: "figure.walk", tint: AppColors.success, size: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.title)
                            .font(.subheadline.weight(.semibold))

                        Text(exercise.instructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                GlassButton(title: "Start exercise", icon: "play.fill", style: .primary, fullWidth: true) {
                    Haptics.medium()
                    let vm = WarmUpViewModel()
                    vm.selectExercise(exercise)
                    activeSheet = .warmUp(vm)
                }
            }
        }
    }

    private func confidenceLaunchCard(activity: CurriculumActivity, exercise: ConfidenceExercise) -> some View {
        GlassCard(tint: AppColors.categoryBrandBright.opacity(0.08)) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    IconChip(icon: "heart.fill", tint: AppColors.categoryBrandBright, size: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.title)
                            .font(.subheadline.weight(.semibold))

                        Text(exercise.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                if confidenceExerciseOpened {
                    GlassButton(title: "Mark as done", icon: "checkmark", style: .primary, fullWidth: true) {
                        CurriculumActivitySignalStore.markExerciseCompleted(activity.exerciseId ?? "")
                        completeCurrentActivity()
                    }
                } else {
                    GlassButton(title: "Start exercise", icon: "play.fill", style: .primary, fullWidth: true) {
                        Haptics.medium()
                        activeSheet = .confidence(exercise)
                    }
                }
            }
        }
    }

    // MARK: - Review Activity

    private func reviewActivityContent(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        let snapshots = Array(recentRecordings.prefix(3))

        return VStack(spacing: 16) {
            activityHeader(activity, isCompleted: isCompleted)

            GlassCard(tint: lessonIdentity.accent.opacity(0.08)) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(activity.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Listen for")
                            .eyebrowStyle(lessonIdentity.accent)

                        Text(lesson.objective)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if snapshots.isEmpty {
                        Text("Record a practice take first, then come back and listen with this lens.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(snapshots, id: \.id) { recording in
                                Button {
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
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open recording from \(recording.date.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
                    }

                    if !isCompleted {
                        GlassButton(title: "I reviewed these", icon: "checkmark", style: .primary, fullWidth: true) {
                            completeCurrentActivity()
                        }
                    } else {
                        Label("Review marked complete", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.success)
                    }
                }
            }
        }
    }

    // MARK: - Shared Subviews

    private func activityHeader(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconChip(icon: activity.type.teacherIcon, tint: activity.type.teacherColor, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.type.teacherRole)
                    .eyebrowStyle(activity.type.teacherColor)

                Text(activity.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(activity.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isCompleted {
                StatusPill(text: "Done", color: AppColors.success, glyph: .icon("checkmark"))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCompleted)
    }

    private func completedCard(_ activity: CurriculumActivity) -> some View {
        GlassCard(tint: AppColors.glassTintSuccess) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.success)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Completed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.success)

                        Text(activity.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                if activity.type == .practice {
                    GlassButton(title: "Practice again", icon: "mic.fill", style: .secondary, fullWidth: true) {
                        Haptics.medium()
                        let duration = recordingDuration(from: activity.targetDuration)
                        activeSheet = .recording(
                            duration: duration,
                            framework: SpeechFramework.fromCurriculumHint(activity.frameworkHint)
                        )
                    }
                } else if activity.type == .drill, let modeRaw = activity.drillMode, let mode = DrillMode(rawValue: modeRaw) {
                    GlassButton(title: "Drill again", icon: "bolt.fill", style: .secondary, fullWidth: true) {
                        Haptics.medium()
                        let vm = DrillViewModel()
                        vm.targetWPM = userSettings.first.resolvedTargetWPM
                        vm.startDrill(mode: mode)
                        activeSheet = .drill(vm)
                    }
                }
            }
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
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
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().opacity(0.35)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private var bottomBarActions: some View {
        let isCurrentComplete = viewModel.isActivityCompleted(currentActivity.id)
        let isLastStep = currentStepIndex >= lesson.activities.count - 1

        Group {
            if isLastStep && allActivitiesComplete {
                if isRevisitingCompletedLesson {
                    GlassButton(title: "Done reviewing", icon: "checkmark", style: .primary, fullWidth: true) {
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
                    style: .primary,
                    fullWidth: true
                ) {
                    Haptics.light()
                    advanceStep()
                }
            } else if isCurrentComplete && isLastStep {
                GlassButton(title: "Wrap up", icon: "arrow.right", iconPosition: .right, style: .primary, fullWidth: true) {
                    Haptics.light()
                    advanceStep()
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
                practiceResult = nil
                confidenceExerciseOpened = false
                currentStepIndex = index
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
        practiceResult = nil
        confidenceExerciseOpened = false
        currentStepIndex += 1
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .recording(let duration, let framework):
            RecordingView(
                prompt: nil,
                duration: duration,
                initialFramework: framework,
                onComplete: { recording in
                    practiceResult = recording
                    completeCurrentActivity()
                    activeSheet = nil
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
            ConfidenceExerciseView(exercise: exercise)
                .onDisappear {
                    confidenceExerciseOpened = true
                }
        }
    }

    // MARK: - Helpers

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
