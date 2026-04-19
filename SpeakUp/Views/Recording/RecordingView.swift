import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    @Environment(SpeechService.self) private var speechService
    @Environment(LLMService.self) private var llmService
    @State private var viewModel = RecordingViewModel()
    @State private var selectedFramework: SpeechFramework?
    @State private var showingVocabOverlay = false
    @State private var completedRecording: Recording?
    @State private var hasNavigated = false
    @Query private var goals: [UserGoal]

    let prompt: Prompt?
    let duration: RecordingDuration
    var timerEndBehavior: TimerEndBehavior = .saveAndStop
    var countdownStyle: CountdownStyle = .countUp
    var goalId: UUID? = nil
    var storyId: UUID? = nil
    let onComplete: (Recording) -> Void
    let onCancel: () -> Void

    private var selectedGoal: UserGoal? {
        guard let goalId else { return nil }
        return goals.first { $0.id == goalId }
    }

    var body: some View {
        ZStack {
            if let completedRecording {
                feedbackGateContent(for: completedRecording)
                    .transition(.opacity)
                    .zIndex(5)
            } else {
                recordingContent
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: completedRecording?.id)
        .task {
            viewModel.configure(
                with: modelContext,
                prompt: prompt,
                duration: duration,
                timerEndBehavior: timerEndBehavior,
                countdownStyle: countdownStyle
            )
            viewModel.goalId = goalId
            viewModel.storyId = storyId
            if let settings = userSettings.first {
                viewModel.fillerConfig = FillerWordConfig(
                    customFillers: Set(settings.customFillerWords),
                    customContextFillers: Set(settings.customContextFillerWords),
                    removedDefaults: Set(settings.removedDefaultFillers)
                )
                viewModel.coachingService.isEnabled = settings.hapticCoachingEnabled
            }
            await viewModel.checkPermissions()
            // Auto-start recording after countdown
            if !viewModel.isRecording {
                await viewModel.startRecording()
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .onChange(of: viewModel.autoSavedRecording) { _, recording in
            if let recording {
                handleRecordingCompletion(recording)
            }
        }
        .alert("Permission Required", isPresented: $viewModel.showingPermissionAlert) {
            Button("Cancel") { onCancel() }
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(viewModel.permissionAlertMessage)
        }
    }

    // MARK: - Recording Content

    private var recordingContent: some View {
        ZStack {
            audioBackground

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerContent
                Spacer()
                bottomControls
            }
            .padding()

            if showingVocabOverlay, let vocabWords = userSettings.first?.vocabWords, !vocabWords.isEmpty {
                VocabOverlayPanel(words: vocabWords) {
                    withAnimation(.spring(response: 0.3)) {
                        showingVocabOverlay = false
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
        }
    }

    // MARK: - Feedback Gate (pre-navigation)
    //
    // Presented in-place after the user stops recording. The analysis job runs
    // in the background via RecordingProcessingCoordinator; this view blocks
    // navigation to the detail screen until feedback is submitted or skipped
    // (when enabled), or until analysis lands (when feedback is off).

    private var feedbackEnabled: Bool {
        userSettings.first?.sessionFeedbackEnabled ?? false
    }

    private var feedbackQuestions: [FeedbackQuestion] {
        let custom = userSettings.first?.customFeedbackQuestions ?? []
        return DefaultFeedbackQuestions.questions + custom
    }

    private var feedbackGateActive: Bool {
        feedbackEnabled && !feedbackQuestions.isEmpty
    }

    @ViewBuilder
    private func feedbackGateContent(for recording: Recording) -> some View {
        ZStack {
            AppBackground(style: .subtle)

            AnalyzingView(
                recording: recording,
                isModelLoading: !speechService.isModelLoaded,
                feedbackEnabled: feedbackEnabled,
                feedbackQuestions: feedbackQuestions,
                existingFeedback: recording.sessionFeedback,
                onFeedbackSubmitted: { feedback in
                    recording.sessionFeedback = feedback
                    try? modelContext.save()
                },
                onFeedbackCompleted: {
                    SessionFeedbackGateStore.markDismissed(recording.id)
                    finishAndNavigate(recording)
                },
                analysisReady: recording.analysis != nil
            )
        }
        // When feedback is off: auto-navigate once processing completes.
        // `try? await Task.sleep` + `Task.isCancelled` guard prevents fall-through
        // navigation if the key changes mid-sleep (coordinator lag race condition).
        .task(id: gateStateKey(for: recording)) {
            // Feedback active: wait for user to submit — onFeedbackCompleted drives navigation
            if feedbackGateActive { return }

            // Feedback disabled: wait for processing to complete before navigating
            let stillProcessing =
                recording.isProcessing ||
                RecordingProcessingCoordinator.shared.isProcessing(recording.id)
            guard !stillProcessing else { return }

            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            SessionFeedbackGateStore.markDismissed(recording.id)
            finishAndNavigate(recording)
        }
    }

    private func gateStateKey(for recording: Recording) -> [Bool] {
        [
            recording.isProcessing,
            RecordingProcessingCoordinator.shared.isProcessing(recording.id)
        ]
    }

    private func finishAndNavigate(_ recording: Recording) {
        guard !hasNavigated else { return }
        hasNavigated = true
        onComplete(recording)
    }

    // MARK: - Audio Background

    private var audioBackground: some View {
        AppBackground(style: .recording)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                // Close button
                Button {
                    Haptics.warning()
                    if viewModel.isRecording {
                        viewModel.cancelRecording()
                    }
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                        }
                }

                Spacer()

                // Framework picker button
                Menu {
                    Button("None") {
                        selectedFramework = nil
                    }
                    ForEach(SpeechFramework.allCases) { framework in
                        Button {
                            selectedFramework = framework
                        } label: {
                            Label(framework.displayName, systemImage: framework.icon)
                        }
                    }
                } label: {
                    Image(systemName: selectedFramework?.icon ?? "list.bullet.rectangle")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                        }
                }

                // Goal badge (if goal selected)
                if let goal = selectedGoal {
                    HStack(spacing: 4) {
                        Image(systemName: goal.type.iconName)
                            .font(.caption2.weight(.semibold))
                        Text(goal.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: 140)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule()
                                    .strokeBorder(.teal.opacity(0.3), lineWidth: 0.5)
                            }
                    }
                    .layoutPriority(-1)
                }

                // Vocab overlay button (only if user has vocab words)
                if let vocabWords = userSettings.first?.vocabWords, !vocabWords.isEmpty {
                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.3)) {
                            showingVocabOverlay.toggle()
                        }
                    } label: {
                        Image(systemName: "character.book.closed")
                            .font(.body.weight(.medium))
                            .foregroundStyle(showingVocabOverlay ? .teal : .white)
                            .frame(width: 36, height: 36)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                            }
                    }
                }

                // Voice activity indicator (top right)
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.audioLevel > -40 ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.15), value: viewModel.audioLevel > -40)

                    Text(viewModel.audioLevel > -40 ? "Speaking" : "Silent")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(viewModel.audioLevel > -40 ? .white : .white.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }

            // Compact prompt card at top (during recording)
            if let prompt, viewModel.isRecording {
                compactPromptCard(prompt)
            }
        }
        .padding(.top, 50)
    }

    private func compactPromptCard(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prompt.category)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))

            Text(prompt.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
        .padding(.horizontal, 4)
    }

    // MARK: - Center Content

    private var centerContent: some View {
        VStack(spacing: 24) {
            // Framework overlay
            if let framework = selectedFramework, viewModel.isRecording {
                FrameworkOverlayView(
                    framework: framework,
                    elapsedTime: viewModel.recordingDuration,
                    totalDuration: TimeInterval(duration.seconds)
                )
            }

            // Timer
            TimerView(
                remainingTime: viewModel.displayTime,
                totalTime: TimeInterval(duration.seconds),
                progress: viewModel.progress,
                color: viewModel.timerColor,
                isRecording: viewModel.isRecording,
                isOvertime: viewModel.isOvertime,
                timerLabel: viewModel.timerLabel
            )

            // Prompt Card (if available) - show only before recording starts
            if let prompt, !viewModel.isRecording {
                promptCard(prompt)
            }
        }
    }

    private func coachingCueView(_ cue: CoachingCue) -> some View {
        HStack(spacing: 8) {
            Image(systemName: cue.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(cue.tint)

            Text(cue.message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(cue.tint.opacity(0.4), lineWidth: 0.5)
                }
        }
    }

    private func promptCard(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(prompt.category)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text(prompt.difficulty.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(AppColors.difficultyColor(prompt.difficulty).opacity(0.3))
                    }
                    .foregroundStyle(AppColors.difficultyColor(prompt.difficulty))
            }

            Text(prompt.text)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
        .padding(.horizontal)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 24) {
            // Coaching cue
            if let cue = viewModel.coachingService.currentCue, viewModel.isRecording {
                coachingCueView(cue)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(cue.message)
            }

            // Live filler counter
            if viewModel.isRecording {
                FillerCounterOverlay(count: viewModel.liveFillerCount)
            }

            // Record Button with circular waveform
            ZStack {
                // Circular waveform around button
                if viewModel.isRecording {
                    CircularWaveformView(audioLevel: viewModel.audioLevel)
                }

                RecordButton(
                    isRecording: viewModel.isRecording,
                    onTap: {
                        Task {
                            if viewModel.isRecording {
                                if let recording = await viewModel.stopRecording() {
                                    handleRecordingCompletion(recording)
                                }
                            } else {
                                await viewModel.startRecording()
                            }
                        }
                    }
                )
            }

            // Hint text
            Text(viewModel.isRecording ? "Tap to stop" : "Tap to start recording")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
                .id(viewModel.isRecording)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
        }
        .padding(.bottom, 40)
    }

    private func handleRecordingCompletion(_ recording: Recording) {
        guard completedRecording == nil, !hasNavigated else { return }
        RecordingProcessingCoordinator.shared.enqueue(
            recordingID: recording.id,
            modelContext: modelContext,
            speechService: speechService,
            llmService: llmService
        )
        Haptics.success()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            completedRecording = recording
        }
    }
}

// MARK: - Circular Waveform View (surrounds record button)

/// Radial waveform drawn in a single Canvas node inside a TimelineView.
/// One draw per frame, 48 capsule paths, no per-bar view diffing.
///
/// - `audioLevel`: incoming dB reading, smoothed to avoid jitter.
/// - `autoAnimate`: when true, ignores `audioLevel` and renders a synthetic
///   resting motion. Used by the post-recording skeleton so the visual reads
///   as "same screen, just processing."
struct CircularWaveformView: View {
    var audioLevel: Float = 0
    var autoAnimate: Bool = false

    private let barCount = 48
    private let baseRadius: CGFloat = 70
    private let maxBarHeight: CGFloat = 35
    private let barWidth: CGFloat = 3
    private let canvasSize: CGFloat = 200

    @State private var smoothedLevel: CGFloat = 0.15

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { graphics, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = context.date.timeIntervalSinceReferenceDate
                let baseLevel: CGFloat = autoAnimate ? 0.55 : smoothedLevel
                let gradient = Gradient(colors: [.teal, .cyan])

                for i in 0..<barCount {
                    let angle = (Double(i) / Double(barCount)) * 2 * .pi
                    let wave = sin(time * 3.0 + Double(i) * 0.35) * 0.22
                    let variation = sin(Double(i) * 1.7 + time * 1.1) * 0.12
                    let h = max(0.12, min(1.0, baseLevel + CGFloat(wave) + CGFloat(variation)))
                    let barLength = maxBarHeight * h

                    var layer = graphics
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .radians(angle))

                    let rect = CGRect(
                        x: -barWidth / 2,
                        y: -(baseRadius + barLength),
                        width: barWidth,
                        height: barLength
                    )
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    layer.fill(
                        path,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: 0, y: -baseRadius),
                            endPoint: CGPoint(x: 0, y: -(baseRadius + maxBarHeight))
                        )
                    )
                }
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .allowsHitTesting(false)
        .onChange(of: audioLevel) { _, newLevel in
            guard !autoAnimate else { return }
            let normalized = CGFloat(max(0, min(1, (Double(newLevel) + 60) / 60)))
            smoothedLevel = smoothedLevel * 0.7 + normalized * 0.3
        }
    }
}

// MARK: - Vocab Overlay Panel

struct VocabOverlayPanel: View {
    let words: [String]
    let onDismiss: () -> Void

    @State private var autoHideTask: Task<Void, Never>?

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Your Words", systemImage: "character.book.closed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                FlowLayout(spacing: 6) {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                Capsule()
                                    .fill(.teal.opacity(0.2))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(.teal.opacity(0.3), lineWidth: 0.5)
                                    }
                            }
                    }
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 110)

            Spacer()
        }
        .onTapGesture { onDismiss() }
        .onAppear {
            autoHideTask = Task {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await MainActor.run { onDismiss() }
            }
        }
        .onDisappear {
            autoHideTask?.cancel()
        }
    }
}

#Preview {
    RecordingView(
        prompt: nil,
        duration: .sixty,
        onComplete: { _ in },
        onCancel: {}
    )
    .modelContainer(for: [Recording.self, Prompt.self, UserSettings.self], inMemory: true)
}
