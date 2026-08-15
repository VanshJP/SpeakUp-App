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
    @State private var showingDiscardConfirm = false
    /// Set once analysis lands, to hold the score reveal on screen before the
    /// detail page. Nil when there is nothing worth revealing.
    @State private var revealRecording: Recording?
    @State private var revealBaselines = PersonalAverage.Baselines()

    let prompt: Prompt?
    let duration: RecordingDuration
    var timerEndBehavior: TimerEndBehavior = .saveAndStop
    var countdownStyle: CountdownStyle = .countUp
    var goalId: UUID? = nil
    var storyId: UUID? = nil
    /// `share` when this session is answering a friend-challenge link.
    var sessionSource: String? = nil
    let onComplete: (Recording) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            if let revealRecording {
                scoreReveal(for: revealRecording)
                    .transition(.opacity)
                    .zIndex(10)
            } else if let completedRecording {
                feedbackGateContent(for: completedRecording)
                    .transition(.opacity)
                    .zIndex(5)
            } else {
                recordingContent
            }
        }
        .ignoresSafeArea()
        .animation(AppMotion.settle, value: completedRecording?.id)
        .animation(AppMotion.settle, value: revealRecording?.id)
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
            viewModel.sessionSource = sessionSource
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

    // MARK: - Score Reveal

    @ViewBuilder
    private func scoreReveal(for recording: Recording) -> some View {
        ScoreRevealView(
            score: recording.analysis?.speechScore.overall ?? 0,
            baselines: revealBaselines,
            weakestAxisLabel: weakestAxisLabel(for: recording),
            onDismiss: { navigate(to: recording) }
        )
    }

    /// Only the building band names a lever, so this is nil above 60 — the
    /// reveal shows the delta there instead.
    private func weakestAxisLabel(for recording: Recording) -> String? {
        guard let analysis = recording.analysis,
              analysis.speechScore.overall < 60 else { return nil }

        let axes = SubscoreRadarChart.Axis.from(
            subscores: analysis.speechScore.subscores,
            isPromptRelevance: analysis.promptRelevanceScore != nil && prompt != nil
        )
        return axes.min(by: { $0.value < $1.value })?.label
    }

    /// Holds on the reveal when there is a score to show, then hands off to the
    /// detail page. A session with no analysis (transcription failed, silence)
    /// skips straight through — there is nothing to reveal.
    private func finishAndNavigate(_ recording: Recording) {
        guard !hasNavigated, revealRecording == nil else { return }

        guard recording.analysis?.speechScore.overall != nil else {
            navigate(to: recording)
            return
        }

        let container = modelContext.container
        let id = recording.id
        Task {
            // Resolve the baseline *before* the reveal appears. The context
            // line reads it about a second in, and letting it pop mid-animation
            // is exactly the jitter this screen exists to avoid.
            revealBaselines = await PersonalAverage.all(
                excluding: id,
                container: container
            )
            withAnimation(AppMotion.settle) { revealRecording = recording }
        }
    }

    private func navigate(to recording: Recording) {
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
                    // A few seconds in, a mis-tap would destroy the take —
                    // confirm before discarding anything substantial.
                    if viewModel.isRecording && viewModel.recordingDuration > 5 {
                        showingDiscardConfirm = true
                    } else {
                        if viewModel.isRecording {
                            viewModel.cancelRecording()
                        }
                        onCancel()
                    }
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
                .accessibilityLabel("Cancel recording")
                .confirmationDialog(
                    "Discard this recording?",
                    isPresented: $showingDiscardConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Discard", role: .destructive) {
                        viewModel.cancelRecording()
                        onCancel()
                    }
                    Button("Keep Recording", role: .cancel) {}
                } message: {
                    Text("Your recording so far will be lost.")
                }

                Spacer()

                // Voice activity indicator — extracted so it only re-renders
                // when the boolean flips, not on every 0.1 s audioLevel write.
                VoiceActivityPill(isSpeaking: viewModel.audioLevel > -40)

                sessionOptionsMenu
            }

            // Compact prompt card at top (during recording)
            if let prompt, viewModel.isRecording {
                compactPromptCard(prompt)
            }
        }
        .padding(.top, 50)
    }

    /// Framework and vocab used to sit in the top bar as their own circular
    /// buttons, alongside a read-only goal badge — five controls competing with
    /// the timer and waveform for a screen whose entire job is "talk now".
    /// They're mid-session adjustments, not primary actions, so they collapse
    /// into one overflow. The goal badge is gone outright: it was pure context,
    /// and the countdown screen showed it seconds earlier.
    private var sessionOptionsMenu: some View {
        Menu {
            Picker("Framework", selection: $selectedFramework) {
                Text("No framework").tag(SpeechFramework?.none)
                ForEach(SpeechFramework.allCases) { framework in
                    Label(framework.displayName, systemImage: framework.icon)
                        .tag(SpeechFramework?.some(framework))
                }
            }

            if let vocabWords = userSettings.first?.vocabWords, !vocabWords.isEmpty {
                Toggle(isOn: $showingVocabOverlay) {
                    Label("Vocabulary words", systemImage: "character.book.closed")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background { Circle().fill(.ultraThinMaterial) }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Session options")
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

    // `promptCard` lived here, rendered only `if !viewModel.isRecording`. But
    // `.task` auto-starts recording on appear, so it flashed for milliseconds
    // while the permission check ran, duplicating the prompt card the countdown
    // screen had shown two seconds earlier. Deleted rather than fixed — there
    // was no moment at which the user was meant to read it.

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        // Snapshot observable reads into locals. Each child subview receives
        // only the fields it needs as plain values — SwiftUI short-circuits
        // child diffs when inputs are unchanged, so waveform (driven by
        // audioLevel) doesn't re-render on filler-count / coaching-cue
        // updates, and vice versa.
        let cue = viewModel.coachingService.currentCue
        let isRecording = viewModel.isRecording
        let fillerCount = viewModel.liveFillerCount
        let level = viewModel.audioLevel

        return VStack(spacing: 24) {
            // Coaching cue
            if let cue, isRecording {
                coachingCueView(cue)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(cue.message)
            }

            // Live filler counter
            if isRecording {
                FillerCounterOverlay(count: fillerCount)
            }

            RecordButtonWaveformStack(
                audioLevel: level,
                isRecording: isRecording,
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

            // Hint text
            Text(isRecording ? "Tap to stop" : "Tap to start recording")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
                .id(isRecording)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeInOut(duration: 0.2), value: isRecording)
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
        withAnimation(AppMotion.settle) {
            completedRecording = recording
        }
    }
}

// MARK: - Circular Waveform View (surrounds record button)

/// Radial waveform drawn in a single Canvas node inside a TimelineView.
/// One draw per frame, 48 capsule paths, no per-bar view diffing.
///
/// - `audioLevel`: incoming dB reading, smoothed to avoid jitter.
struct CircularWaveformView: View {
    var audioLevel: Float = 0

    private let barCount = 54
    private let baseRadius: CGFloat = 72
    private let maxBarHeight: CGFloat = 44
    private let minBarHeight: CGFloat = 8
    private let barWidth: CGFloat = 3
    private let canvasSize: CGFloat = 220

    @State private var smoothedLevel: CGFloat = 0.18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { graphics, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = context.date.timeIntervalSinceReferenceDate
                let baseLevel: CGFloat = smoothedLevel
                let gradient = Gradient(colors: [AppColors.primary, AppColors.categoryBrandBright])

                for i in 0..<barCount {
                    let angle = (Double(i) / Double(barCount)) * 2 * .pi
                    // Two detuned sines give each bar an organic, non-repeating
                    // bob that still tracks the incoming audio envelope.
                    let wave = sin(time * 3.0 + Double(i) * 0.35) * 0.22
                    let variation = sin(Double(i) * 1.7 + time * 1.1) * 0.12
                    let h = max(0.15, min(1.0, baseLevel + CGFloat(wave) + CGFloat(variation)))
                    let barLength = minBarHeight + (maxBarHeight - minBarHeight) * h
                    let half = barLength / 2

                    var layer = graphics
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .radians(angle))

                    // Capsule centered on the ring perimeter — half extends
                    // inward, half outward, producing a mirrored spoke.
                    let rect = CGRect(
                        x: -barWidth / 2,
                        y: -(baseRadius + half),
                        width: barWidth,
                        height: barLength
                    )
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    layer.fill(
                        path,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: 0, y: -(baseRadius + half)),
                            endPoint: CGPoint(x: 0, y: -(baseRadius - half))
                        )
                    )
                }
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .allowsHitTesting(false)
        .onChange(of: audioLevel) { _, newLevel in
            let normalized = CGFloat(max(0, min(1, (Double(newLevel) + 60) / 60)))
            smoothedLevel = smoothedLevel * 0.72 + normalized * 0.28
        }
    }
}

// MARK: - Voice Activity Pill

/// Isolated so the capsule + dot only re-render when the speaking boolean
/// flips, not on every 0.1 s audioLevel write.
private struct VoiceActivityPill: View {
    let isSpeaking: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isSpeaking ? AppColors.success : AppColors.scoreEmpty)
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.15), value: isSpeaking)

            Text(isSpeaking ? "Speaking" : "Silent")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSpeaking ? .white : .white.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Record Button + Waveform Stack

/// POD container for the circular waveform and record button. Isolated so
/// the waveform subtree does not re-diff when filler-count / coaching-cue
/// state changes further up in `bottomControls`.
private struct RecordButtonWaveformStack: View {
    let audioLevel: Float
    let isRecording: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            if isRecording {
                CircularWaveformView(audioLevel: audioLevel)
            }

            RecordButton(isRecording: isRecording, onTap: onTap)
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
                        .foregroundStyle(AppColors.primary)
                    Spacer()
                    Button("Dismiss vocabulary overlay", systemImage: "xmark") {
                        onDismiss()
                    }
                    .labelStyle(.iconOnly)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
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
                                    .fill(AppColors.primary.opacity(0.2))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(AppColors.primary.opacity(0.3), lineWidth: 0.5)
                                    }
                            }
                    }
                }
            }
            .padding(14)
            .glassCard(cornerRadius: 16)
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
