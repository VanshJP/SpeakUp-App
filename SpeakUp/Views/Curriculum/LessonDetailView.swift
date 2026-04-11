import SwiftUI
import SwiftData

struct LessonDetailView: View {
    let lesson: CurriculumLesson
    @Bindable var viewModel: CurriculumViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var currentStepIndex: Int = 0
    @State private var activeSheet: ActiveSheet?
    @State private var practiceResult: Recording?
    @State private var showingLessonCompletion = false
    @State private var confidenceExerciseOpened = false
    @State private var stepCompleteMessage: String?
    @State private var completedActivityIds: Set<String> = []

    // MARK: - ActiveSheet

    enum ActiveSheet: Identifiable {
        case recording(duration: RecordingDuration)
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
                        viewModel.advanceToNextLesson(context: modelContext)
                        dismiss()
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 4) {
                    Text("Step \(currentStepIndex + 1) of \(lesson.activities.count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        ForEach(Array(lesson.activities.enumerated()), id: \.element.id) { index, activity in
                            Capsule()
                                .fill(dotColor(for: index, activity: activity))
                                .frame(maxWidth: 20, maxHeight: 3)
                                .contentShape(Rectangle().size(width: 20, height: 20))
                                .onTapGesture {
                                    if index <= currentStepIndex || viewModel.isActivityCompleted(activity.id) {
                                        Haptics.light()
                                        practiceResult = nil
                                        confidenceExerciseOpened = false
                                        currentStepIndex = index
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: 160)
                }
            }
        }
        .fullScreenCover(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .onAppear {
            currentStepIndex = viewModel.initialStepIndex(for: lesson)
            // Seed already-completed activity IDs so we don't animate pre-existing completions
            completedActivityIds = Set(lesson.activities.filter { viewModel.isActivityCompleted($0.id) }.map(\.id))
        }
    }

    // MARK: - Step Complete Toast

    private func stepCompleteToast(_ message: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private func showStepCompletion() {
        let messages = [
            "Nice work!",
            "Keep it up!",
            "One step closer!",
            "Great progress!",
            "You're on a roll!",
            "Looking good!",
            "Well done!",
            "Solid effort!",
        ]
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            stepCompleteMessage = messages.randomElement()
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

    private var lessonContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        // Scroll anchor
                        Color.clear
                            .frame(height: 0)
                            .id("scrollTop")

                        // Lesson header
                        VStack(alignment: .leading, spacing: 8) {
                            Text(lesson.title)
                                .font(.title2.weight(.bold))

                            Text(lesson.objective)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Current activity content
                        activityContent(for: currentActivity)

                        Spacer().frame(height: 80)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
                .onChange(of: currentStepIndex) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("scrollTop", anchor: .top)
                    }
                }
            }

            // Bottom action bar
            bottomBar
        }
    }

    private func dotColor(for index: Int, activity: CurriculumActivity) -> Color {
        if completedActivityIds.contains(activity.id) || viewModel.isActivityCompleted(activity.id) {
            return .green
        } else if index == currentStepIndex {
            return AppColors.primary
        } else {
            return .gray.opacity(0.3)
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

    private func practiceLaunchCard(_ activity: CurriculumActivity) -> some View {
        GlassCard(tint: AppColors.glassTintPrimary) {
            VStack(spacing: 16) {
                Text(activity.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 16) {
                    if let duration = activity.targetDuration {
                        Label("\(durationLabel(duration))", systemImage: "timer")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.teal)
                    }

                    if let framework = activity.frameworkHint {
                        Label(framework, systemImage: "rectangle.3.group")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.indigo)
                    }
                }

                GlassButton(title: "Start Practice", icon: "mic.fill", style: .primary, fullWidth: true) {
                    Haptics.medium()
                    let duration = recordingDuration(from: activity.targetDuration)
                    activeSheet = .recording(duration: duration)
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
        GlassCard(tint: Color.orange.opacity(0.08)) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: mode.icon)
                        .font(.title2)
                        .foregroundStyle(mode.color)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(mode.color.opacity(0.15)))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.title)
                            .font(.subheadline.weight(.semibold))

                        Text(mode.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Text(activity.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GlassButton(title: "Start Drill", icon: "bolt.fill", style: .primary, fullWidth: true) {
                    Haptics.medium()
                    let vm = DrillViewModel()
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
        GlassCard(tint: Color.green.opacity(0.08)) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.green.opacity(0.15)))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.title)
                            .font(.subheadline.weight(.semibold))

                        Text(exercise.instructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                Text(activity.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GlassButton(title: "Start Exercise", icon: "play.fill", style: .primary, fullWidth: true) {
                    Haptics.medium()
                    let vm = WarmUpViewModel()
                    vm.selectExercise(exercise)
                    activeSheet = .warmUp(vm)
                }
            }
        }
    }

    private func confidenceLaunchCard(activity: CurriculumActivity, exercise: ConfidenceExercise) -> some View {
        GlassCard(tint: Color.pink.opacity(0.08)) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.title2)
                        .foregroundStyle(.pink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.pink.opacity(0.15)))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.title)
                            .font(.subheadline.weight(.semibold))

                        Text(exercise.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                Text(activity.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if confidenceExerciseOpened {
                    GlassButton(title: "Mark as Done", icon: "checkmark", style: .primary, fullWidth: true) {
                        CurriculumActivitySignalStore.markExerciseCompleted(activity.exerciseId ?? "")
                        completeCurrentActivity()
                    }
                } else {
                    GlassButton(title: "Start Exercise", icon: "play.fill", style: .primary, fullWidth: true) {
                        Haptics.medium()
                        activeSheet = .confidence(exercise)
                    }
                }
            }
        }
    }

    // MARK: - Review Activity

    private func reviewActivityContent(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        VStack(spacing: 16) {
            activityHeader(activity, isCompleted: isCompleted)

            GlassCard(tint: Color.purple.opacity(0.08)) {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title2)
                            .foregroundStyle(.purple)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.purple.opacity(0.15)))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.title)
                                .font(.subheadline.weight(.semibold))

                            Text(activity.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    if !isCompleted {
                        GlassButton(title: "Mark as Done", icon: "checkmark", style: .primary, fullWidth: true) {
                            completeCurrentActivity()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared Subviews

    private func activityHeader(_ activity: CurriculumActivity, isCompleted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: activityIcon(for: activity.type))
                .font(.subheadline)
                .foregroundStyle(activityColor(for: activity.type))
                .frame(width: 28, height: 28)
                .background(Circle().fill(activityColor(for: activity.type).opacity(0.15)))

            Text(activity.title)
                .font(.headline)

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCompleted)
    }

    private func completedCard(_ activity: CurriculumActivity) -> some View {
        GlassCard(tint: AppColors.glassTintSuccess) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Completed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)

                    Text(activity.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.2)

            Group {
                let isCurrentComplete = viewModel.isActivityCompleted(currentActivity.id)
                let isLastStep = currentStepIndex >= lesson.activities.count - 1

                if isLastStep && allActivitiesComplete {
                    GlassButton(title: "Complete Lesson", icon: "trophy.fill", style: .primary, fullWidth: true) {
                        Haptics.success()
                        withAnimation(.spring(response: 0.4)) {
                            showingLessonCompletion = true
                        }
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else if currentActivity.type == .lesson && !isCurrentComplete {
                    GlassButton(title: "Mark as Read", icon: "checkmark", style: .primary, fullWidth: true) {
                        completeCurrentActivity()
                        advanceStep()
                    }
                } else if isCurrentComplete && !isLastStep {
                    GlassButton(title: "Next Step", icon: "arrow.right", iconPosition: .right, style: .primary, fullWidth: true) {
                        Haptics.light()
                        advanceStep()
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else if isCurrentComplete && isLastStep {
                    GlassButton(title: "Next Step", icon: "arrow.right", iconPosition: .right, style: .primary, fullWidth: true) {
                        Haptics.light()
                        advanceStep()
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isActivityCompleted(currentActivity.id))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentStepIndex)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Navigation

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
        case .recording(let duration):
            RecordingView(
                prompt: nil,
                duration: duration,
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

    private func activityIcon(for type: CurriculumActivityType) -> String {
        switch type {
        case .lesson: return "book"
        case .practice: return "mic"
        case .drill: return "bolt"
        case .exercise: return "figure.walk"
        case .review: return "arrow.counterclockwise"
        }
    }

    private func activityColor(for type: CurriculumActivityType) -> Color {
        switch type {
        case .lesson: return .blue
        case .practice: return .teal
        case .drill: return .orange
        case .exercise: return .green
        case .review: return .purple
        }
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
