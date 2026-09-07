import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    @Environment(SpeechService.self) private var speechService
    @Environment(LLMService.self) private var llmService
    @State private var viewModel = RecordingViewModel()
    @State private var selectedFramework: SpeechFramework?
    @State private var showingVocabStrip = true
    @State private var overlayWords: [String] = []
    @State private var overlayIntroduced: Set<String> = []
    @State private var overlayReviewing: Set<String> = []
    @State private var overlayTitle = "Your Words"
    @State private var completedRecording: Recording?
    @State private var hasNavigated = false
    @State private var showingDiscardConfirm = false
    /// Set once analysis lands, to hold the score reveal on screen before the
    /// detail page. Nil when there is nothing worth revealing.
    @State private var revealRecording: Recording?
    /// Snapshot for the reveal — never read `recording.analysis` from body.
    @State private var revealAnalysis: SpeechAnalysis?
    @State private var revealBaselines = PersonalAverage.Baselines()
    @State private var revealTask: Task<Void, Never>?
    /// What the speaker is meant to be working on this take. Loaded separately
    /// from the configure task so resolving it can never delay the countdown.
    @State private var focusPlan: CoachPlan?

    let prompt: Prompt?
    let duration: RecordingDuration
    var timerEndBehavior: TimerEndBehavior = .saveAndStop
    var countdownStyle: CountdownStyle = .countUp
    var goalId: UUID? = nil
    var storyId: UUID? = nil
    /// `share` when this session is answering a friend-challenge link.
    var sessionSource: String? = nil
    /// Pre-selects a structure overlay (curriculum PREP/STAR practice).
    var initialFramework: SpeechFramework? = nil
    /// Fires when the user leaves the analyzing stage without opening detail.
    /// The parent can evaluate achievements without forcing navigation.
    var onSavedAndClosed: ((Recording) -> Void)? = nil
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
        // No blanket `.ignoresSafeArea()`. Every backdrop this screen can wear
        // bleeds on its own (`RecordingBackdropView`, `AppBackground`), and
        // consuming the insets here is what pushed the prompt card under the
        // status bar and left the controls guessing with a hard-coded 50pt.
        .animation(AppMotion.settle, value: completedRecording?.id)
        .animation(AppMotion.settle, value: revealRecording?.id)
        .task {
            viewModel.configure(
                with: modelContext,
                prompt: prompt,
                duration: duration,
                timerEndBehavior: timerEndBehavior,
                countdownStyle: countdownStyle,
                speechService: speechService,
                llmService: llmService
            )
            viewModel.goalId = goalId
            viewModel.storyId = storyId
            viewModel.sessionSource = sessionSource
            if selectedFramework == nil, let initialFramework {
                selectedFramework = initialFramework
            }
            viewModel.frameworkUsed = selectedFramework
            if let settings = userSettings.first {
                viewModel.fillerConfig = FillerWordConfig(
                    customFillers: Set(settings.customFillerWords),
                    customContextFillers: Set(settings.customContextFillerWords),
                    removedDefaults: Set(settings.removedDefaultFillers)
                )
                viewModel.coachingService.isEnabled = settings.hapticCoachingEnabled
            }
            await viewModel.checkPermissions()
            refreshVocabOverlay()
            // Auto-start recording after countdown
            if !viewModel.isRecording {
                await viewModel.startRecording()
            }
        }
        .onChange(of: selectedFramework) { _, newValue in
            viewModel.frameworkUsed = newValue
        }
        // Deliberate practice needs the instruction going in. Reading the focus
        // afterwards on the results screen is always one take too late, so it
        // rides along here as well.
        .task {
            let container = modelContext.container
            let weights = ScoreWeights(from: userSettings.first)
            // No session to exclude — this runs before one exists.
            focusPlan = await PersonalAverage.snapshot(
                excluding: UUID(),
                container: container,
                weights: weights
            ).plan
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
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
        .alert("That Take Didn't Save", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                viewModel.error = nil
                onCancel()
            }
            Button("Try Again") {
                viewModel.error = nil
                Task { await viewModel.startRecording() }
            }
        } message: {
            Text("You didn't do anything wrong. Try once more, or come back when you're ready.")
        }
    }

    // MARK: - Recording Content

    private var recordingContent: some View {
        ZStack {
            audioBackground

            // Three slots, no spacers: status on top, dial in the middle
            // taking whatever is left, controls along the bottom. The old
            // `Spacer() / dial / Spacer()` parked a fixed 200pt dial in a
            // ~380pt gap and left the ~90pt on either side of it empty, on the
            // one screen that has nothing else to show.
            VStack(spacing: 0) {
                topBar
                sessionStage
                bottomControls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
        // Same activation rule as Recording Detail: never put a questionnaire
        // in front of the first scored take. Exclude the active recording so
        // its own transcriptionText landing mid-gate cannot flip the bypass off.
        guard let id = completedRecording?.id else {
            return feedbackEnabled && !feedbackQuestions.isEmpty
        }
        return feedbackEnabled && !feedbackQuestions.isEmpty && !isFirstAnalyzedSession(excluding: id)
    }

    /// True when no *prior* take has a transcript yet — this session is the
    /// activation moment. Counted on `transcriptionText` (never `#Predicate` on
    /// the analysis blob).
    private func isFirstAnalyzedSession(excluding recordingID: UUID) -> Bool {
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate {
                $0.transcriptionText != nil && $0.id != recordingID
            }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count == 0
    }

    @ViewBuilder
    private func feedbackGateContent(for recording: Recording) -> some View {
        ZStack {
            AppBackground(style: .subtle)

            AnalyzingView(
                recording: recording,
                isModelLoading: speechService.isLoadingModel,
                isDownloadingModel: speechService.isDownloadingModel,
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
                onSaveAndClose: {
                    SessionFeedbackGateStore.markDismissed(recording.id)
                    onSavedAndClosed?(recording)
                    onCancel()
                },
                analysisReady: recording.overallScore != nil || recording.transcriptionText != nil
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
            score: revealAnalysis?.speechScore.overall ?? recording.overallScore ?? 0,
            baselines: revealBaselines,
            weakestAxisLabel: weakestAxisLabel(from: revealAnalysis),
            onDismiss: { navigate(to: recording) }
        )
    }

    /// Only the building band names a lever, so this is nil above 60 — the
    /// reveal shows the delta there instead.
    private func weakestAxisLabel(from analysis: SpeechAnalysis?) -> String? {
        guard let analysis,
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

        // Snapshot once — body must not re-decode the Codable blob.
        let analysis = recording.analysis
        guard analysis?.speechScore.overall != nil || recording.overallScore != nil else {
            navigate(to: recording)
            return
        }
        revealAnalysis = analysis

        let container = modelContext.container
        let id = recording.id
        revealTask?.cancel()
        revealTask = Task {
            // Resolve the baseline *before* the reveal appears. The context
            // line reads it about a second in, and letting it pop mid-animation
            // is exactly the jitter this screen exists to avoid.
            let baselines = await PersonalAverage.all(
                excluding: id,
                container: container
            )
            guard !Task.isCancelled else { return }
            revealBaselines = baselines
            withAnimation(AppMotion.settle) { revealRecording = recording }
        }
    }

    private func navigate(to recording: Recording) {
        guard !hasNavigated else { return }
        hasNavigated = true
        onComplete(recording)
    }

    // MARK: - Audio Background

    /// Same canvas the prepare countdown just showed, so the session doesn't
    /// swap backgrounds under the user the second recording starts. `.base`
    /// resolves to `AppBackground(style: .recording)`, the old look.
    private var audioBackground: some View {
        RecordingBackdropView(
            backdrop: RecordingBackdrop(rawValue: userSettings.first?.countdownBackdrop ?? 0) ?? .base
        )
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

                // Status cluster: how many fillers so far, and whether the mic
                // is hearing anything. Both read state that changes rarely, so
                // neither re-renders on the 0.1 s audioLevel write.
                if viewModel.isRecording {
                    FillerCounterOverlay(count: viewModel.liveFillerCount)
                }

                MicLevelPill(isHearing: viewModel.audioService.isHearingInput)

                sessionOptionsMenu
            }

            // The focus rides on the prompt card's meta line rather than in a
            // pill of its own: two stacked capsules saying "Personal Growth"
            // and "Vocal variety" were two rows of chrome for one sentence of
            // context. Without a card it still needs somewhere to live.
            if let prompt, viewModel.isRecording {
                compactPromptCard(prompt)
            } else if let focusPlan, !focusPlan.isGraduating {
                focusIntentPill(focusPlan)
            }

            if showingVocabStrip, !overlayWords.isEmpty {
                VocabStrip(
                    words: overlayWords,
                    introduced: overlayIntroduced,
                    reviewing: overlayReviewing
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AppMotion.settle, value: showingVocabStrip)
    }

    /// The one thing to hold in mind during this take, for sessions with no
    /// prompt card to carry it (story practice, free takes).
    ///
    /// Names the technique before the countdown ends, then drops to just the
    /// area once recording starts — mid-take is the wrong moment to hand
    /// somebody a paragraph, but the reminder still has to be there, because
    /// that is the entire window in which they can act on it.
    @ViewBuilder
    private func focusIntentPill(_ plan: CoachPlan) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 10, weight: .semibold))

            Text(viewModel.isRecording
                 ? plan.focus.title
                 : "\(plan.focus.title) · \(plan.focus.technique.name)")
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay { Capsule().stroke(AppColors.cardStroke, lineWidth: 0.5) }
        .transition(.opacity)
        .accessibilityLabel("This take's focus: \(plan.focus.title). \(plan.focus.technique.name)")
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

            if !overlayWords.isEmpty {
                Toggle(isOn: $showingVocabStrip) {
                    Label(overlayTitle, systemImage: "character.book.closed")
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

    private func refreshVocabOverlay() {
        guard let settings = userSettings.first else {
            overlayWords = []
            overlayIntroduced = []
            overlayReviewing = []
            return
        }

        let prefs = settings.vocabChallengePreferences
        if prefs.isEnabled,
           let challenge = VocabChallengeService.todaysChallenge(preferences: prefs),
           !challenge.words.isEmpty {
            overlayWords = challenge.words.map(\.text)
            overlayIntroduced = Set(
                challenge.words
                    .filter { $0.source == .introduced }
                    .map(\.id)
            )
            overlayReviewing = Set(
                challenge.words
                    .filter { $0.isReview == true }
                    .map(\.id)
            )
            overlayTitle = "Use today"
            return
        }

        // Bank fallback for users with the workout off. Trimmed by the strip
        // itself — a fifty-word bank is not a recording-screen cue.
        overlayWords = settings.vocabWords
        overlayIntroduced = []
        overlayReviewing = []
        overlayTitle = "Your Words"
    }

    /// The prompt, mid-take. Two lines of `.subheadline` used to truncate the
    /// back half of anything longer than a sentence while a third of the screen
    /// below it sat empty; the space the dial slot doesn't need is better spent
    /// on the question being answered.
    private func compactPromptCard(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(prompt.category)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                if let focusPlan, !focusPlan.isGraduating {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))

                    Label(focusPlan.focus.title, systemImage: "scope")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            Text(prompt.text)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(promptCardAccessibilityLabel(prompt))
    }

    private func promptCardAccessibilityLabel(_ prompt: Prompt) -> String {
        var parts = ["\(prompt.category). \(prompt.text)"]
        if let focusPlan, !focusPlan.isGraduating {
            parts.append("This take's focus: \(focusPlan.focus.title)")
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Session Stage

    /// The dial, in a slot that owns everything the top bar and the controls
    /// didn't take. The countdown draws the identical slot at the identical
    /// size, so starting a take moves nothing but the prompt card.
    private var sessionStage: some View {
        SessionDialSlot(spacing: 24) { diameter in
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
                progress: viewModel.progress,
                color: viewModel.timerColor,
                isRecording: viewModel.isRecording,
                isOvertime: viewModel.isOvertime,
                timerLabel: viewModel.timerLabel,
                // Same dial the countdown just drew — the look is picked once
                // in Settings and has to survive the hand-off to recording.
                look: TimerLook(rawValue: userSettings.first?.countdownLook ?? 0) ?? .ring,
                diameter: diameter
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
        // child diffs when inputs are unchanged, so the waveform (driven by
        // audioLevel) doesn't re-render on coaching-cue updates, and vice
        // versa.
        let cue = viewModel.coachingService.currentCue
        let isRecording = viewModel.isRecording
        let level = viewModel.audioLevel

        return VStack(spacing: 24) {
            // Coaching cue
            if let cue, isRecording {
                coachingCueView(cue)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(cue.message)
            }

            RecordButtonWaveformStack(
                audioLevel: level,
                waveformStyle: WaveformStyle(rawValue: userSettings.first?.waveformStyle ?? 0) ?? .rings,
                buttonStyle: RecordButtonStyle(rawValue: userSettings.first?.recordButtonStyle ?? 0) ?? .classic,
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
        // The safe area already holds the controls clear of the home
        // indicator; the old 40pt on top of it was a second guess at the
        // same gap.
        .padding(.bottom, 8)
    }

    private func handleRecordingCompletion(_ recording: Recording) {
        guard completedRecording == nil, !hasNavigated else { return }
        viewModel.submitForAnalysis(recording)
        Haptics.success()
        withAnimation(AppMotion.settle) {
            completedRecording = recording
        }
    }
}

// MARK: - Circular Waveform View (surrounds record button)

/// Radial waveform drawn in a single Canvas node inside a TimelineView.
/// One draw per frame, no per-bar view diffing.
///
/// - `audioLevel`: incoming dB reading, smoothed to avoid jitter.
/// - `style`: user-chosen look (Settings → Waveform).
/// - `canvasSize`: geometry scales from the 220pt reference design, so the
///   same view doubles as a settings thumbnail.
/// - `simulated`: no mic — drive the envelope from a sine so previews move.
struct CircularWaveformView: View {
    var audioLevel: Float = 0
    var style: WaveformStyle = .rings
    var canvasSize: CGFloat = 220
    var simulated: Bool = false

    @State private var smoothedLevel: CGFloat = 0.18

    private var scale: CGFloat { canvasSize / 220 }

    var body: some View {
        // Off takes no frame at all, so the record button doesn't sit in the
        // middle of an invisible 220pt hole — and no 60 fps clock runs for a
        // canvas with nothing on it.
        if style == .off {
            EmptyView()
        } else {
            // Thumbnail-sized instances run at half rate — the picker shows six
            // of these at once, and nobody reads 60 fps off a 76pt swatch.
            TimelineView(.animation(minimumInterval: canvasSize < 120 ? 1.0 / 30.0 : 1.0 / 60.0)) { context in
                Canvas { graphics, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let time = context.date.timeIntervalSinceReferenceDate
                    let level = simulated
                        ? 0.45 + 0.28 * CGFloat(sin(time * 1.6))
                        : smoothedLevel
                    draw(in: &graphics, center: center, time: time, level: level)
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

    // MARK: - Drawing

    /// Two detuned sines give each bar an organic, non-repeating bob that
    /// still tracks the incoming audio envelope.
    private func amplitude(_ i: Int, time: Double, level: CGFloat) -> CGFloat {
        let wave = sin(time * 3.0 + Double(i) * 0.35) * 0.22
        let variation = sin(Double(i) * 1.7 + time * 1.1) * 0.12
        return max(0.15, min(1.0, level + CGFloat(wave) + CGFloat(variation)))
    }

    private func draw(in graphics: inout GraphicsContext, center: CGPoint, time: Double, level: CGFloat) {
        let gradient = Gradient(colors: [AppColors.primary, AppColors.categoryBrandBright])
        let radius = 72 * scale
        let minLength = 8 * scale
        let maxLength = 44 * scale

        switch style {
        case .rings, .bars, .spark:
            let barCount = style == .spark ? 80 : (style == .bars ? 40 : 54)
            let barWidth: CGFloat = (style == .spark ? 1.5 : (style == .bars ? 5.0 : 3.0)) * scale

            for i in 0..<barCount {
                let angle = (Double(i) / Double(barCount)) * 2 * .pi
                var h = amplitude(i, time: time, level: level)
                // Spark alternates hairline lengths for a sharper, spikier ring.
                if style == .spark && i.isMultiple(of: 2) { h *= 0.5 }
                let barLength = minLength + (maxLength - minLength) * h
                // Rings straddle the perimeter; the others grow outward only.
                let inset = style == .rings ? barLength / 2 : 0

                var layer = graphics
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .radians(angle))

                let rect = CGRect(
                    x: -barWidth / 2,
                    y: -(radius + barLength - inset),
                    width: barWidth,
                    height: barLength
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                if style == .spark {
                    layer.fill(path, with: .color(AppColors.categoryBrandBright.opacity(Double(0.3 + 0.6 * h))))
                } else {
                    layer.fill(
                        path,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: 0, y: -(radius + barLength - inset)),
                            endPoint: CGPoint(x: 0, y: -(radius - inset))
                        )
                    )
                }
            }

        case .dots:
            for i in 0..<36 {
                let angle = (Double(i) / 36.0) * 2 * .pi - .pi / 2
                let h = amplitude(i, time: time, level: level)
                let distance = radius + maxLength * 0.5 * h
                let dotRadius = (2 + 4 * h) * scale
                let rect = CGRect(
                    x: center.x + CGFloat(cos(angle)) * distance - dotRadius,
                    y: center.y + CGFloat(sin(angle)) * distance - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                graphics.fill(
                    Path(ellipseIn: rect),
                    with: .color(AppColors.categoryBrandBright.opacity(Double(0.4 + 0.6 * h)))
                )
            }

        case .ribbon:
            // Two phase-offset closed curves — the trailing one reads as echo.
            for pass in 0..<2 {
                var path = Path()
                let samples = 120
                for i in 0...samples {
                    let angle = (Double(i) / Double(samples)) * 2 * .pi - .pi / 2
                    let h = amplitude(i, time: time + Double(pass) * 0.45, level: level)
                    let r = radius + maxLength * 0.5 * (h - 0.4)
                    let point = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                graphics.stroke(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: center.x, y: center.y - radius),
                        endPoint: CGPoint(x: center.x, y: center.y + radius)
                    ),
                    lineWidth: (pass == 0 ? 2.5 : 1.0) as CGFloat * scale
                )
            }

        case .pulse:
            let base = Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
            graphics.stroke(base, with: .color(AppColors.primary.opacity(0.45)), lineWidth: 2 * scale)

            // Rings born at the button edge, expanding outward and fading.
            for ring in 0..<4 {
                let phase = (time * 0.5 + Double(ring) * 0.25).truncatingRemainder(dividingBy: 1)
                let r = radius + (maxLength + 16 * scale) * CGFloat(phase)
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                graphics.stroke(
                    Path(ellipseIn: rect),
                    with: .color(AppColors.categoryBrandBright.opacity((1 - phase) * Double(0.2 + 0.6 * level))),
                    lineWidth: (1 + 2 * level) * scale
                )
            }

        case .off:
            break  // body never builds the canvas for this one
        }
    }
}

// MARK: - Mic Level Pill

/// Answers one question — is the mic hearing me? — and stays quiet otherwise.
///
/// This used to read Speaking / Silent off the instantaneous level, so it
/// strobed between every two words: a label that changes four times a sentence
/// is read as broken, not informative. `AudioService.isHearingInput` starts a
/// take green, drops to the warning only if the first few seconds bring in
/// nothing at all, and latches green for good the moment the mic is proven to
/// work — so this changes at most twice a take, and the words only appear when
/// there is something to say.
///
/// Not private: the drill screen shows the same indicator, driven by the same
/// service state.
struct MicLevelPill: View {
    let isHearing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isHearing ? "mic.fill" : "mic.slash.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isHearing ? AppColors.success : AppColors.warning)

            if !isHearing {
                Text("No sound")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.warning)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(isHearing ? .clear : AppColors.warning.opacity(0.4), lineWidth: 1)
                }
        }
        .animation(AppMotion.settle, value: isHearing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isHearing ? "Microphone is picking up sound" : "No sound reaching the microphone")
    }
}

// MARK: - Record Button + Waveform Stack

/// POD container for the circular waveform and record button. Isolated so
/// the waveform subtree does not re-diff when coaching-cue state changes
/// further up in `bottomControls`.
private struct RecordButtonWaveformStack: View {
    let audioLevel: Float
    let waveformStyle: WaveformStyle
    let buttonStyle: RecordButtonStyle
    let isRecording: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            if isRecording {
                CircularWaveformView(audioLevel: audioLevel, style: waveformStyle)
            }

            RecordButton(isRecording: isRecording, style: buttonStyle, onTap: onTap)
        }
    }
}

// MARK: - Vocab Strip

/// Today's spotlight words, inline in the top bar.
///
/// This used to be a glass panel floating over the top of the screen, which
/// landed squarely on the compact prompt card and hid the thing the speaker was
/// supposed to be answering. A chip row that takes its own space costs a few
/// points of height and blocks nothing.
private struct VocabStrip: View {
    let words: [String]
    let introduced: Set<String>
    let reviewing: Set<String>

    /// Mid-sentence is no time to read a list. Anything past a few chips is
    /// reference material, and reference material belongs on Today.
    private var shown: [String] { Array(words.prefix(4)) }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 4)

            FlowLayout(spacing: 6) {
                ForEach(shown, id: \.self) { word in
                    chip(word)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Words to use: \(shown.joined(separator: ", "))")
    }

    private func chip(_ word: String) -> some View {
        let tint = tint(for: word)
        return Text(word)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(tint.opacity(0.18))
                    .overlay {
                        Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
                    }
            }
    }

    private func tint(for word: String) -> Color {
        let key = word.lowercased()
        if reviewing.contains(key) { return AppColors.primary }
        if introduced.contains(key) { return AppColors.categorySage }
        return .white
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
