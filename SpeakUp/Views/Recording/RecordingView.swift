import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    @Environment(SpeechService.self) private var speechService
    @Environment(LLMService.self) private var llmService
    @State private var viewModel = RecordingViewModel()
    @State private var overlayWords: [String] = []
    @State private var overlayIntroduced: Set<String> = []
    @State private var overlayReviewing: Set<String> = []
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
            refreshVocabOverlay()
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
            }

            // Compact prompt card at top (during recording)
            if let prompt, viewModel.isRecording {
                CompactPromptCard(category: prompt.category, text: prompt.text)
            }

            if !overlayWords.isEmpty {
                VocabStrip(
                    words: overlayWords,
                    introduced: overlayIntroduced,
                    reviewing: overlayReviewing,
                    heard: viewModel.heardVocabKeys
                )
            }
        }
        .padding(.top, 50)
    }

    private func refreshVocabOverlay() {
        guard let settings = userSettings.first else {
            overlayWords = []
            overlayIntroduced = []
            overlayReviewing = []
            viewModel.targetVocab = []
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
            viewModel.targetVocab = VocabStrip.shown(overlayWords)
            return
        }

        // Bank fallback for users with the workout off. Trimmed by the strip
        // itself — a fifty-word bank is not a recording-screen cue.
        overlayWords = settings.vocabWords
        overlayIntroduced = []
        overlayReviewing = []
        viewModel.targetVocab = VocabStrip.shown(overlayWords)
    }

    // MARK: - Center Content

    private var centerContent: some View {
        VStack(spacing: 16) {
            LiveCaptionView(tokens: viewModel.liveCaptionTokens)

            TimerView(
                remainingTime: viewModel.displayTime,
                progress: viewModel.progress,
                color: viewModel.timerColor,
                isRecording: viewModel.isRecording,
                isOvertime: viewModel.isOvertime,
                timerLabel: viewModel.timerLabel,
                // Same dial the countdown just drew — the look is picked once
                // in Settings and has to survive the hand-off to recording.
                look: TimerLook(rawValue: userSettings.first?.countdownLook ?? 0) ?? .ring
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
/// is read as broken, not informative. `AudioService.isHearingInput` holds a
/// decaying peak, so this only changes when something is actually wrong, and
/// the words only appear when there is something to say.
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
/// supposed to be answering. Chips light up when live transcription hears the
/// word (same `VocabMatcher` as post-take analysis).
private struct VocabStrip: View {
    let words: [String]
    let introduced: Set<String>
    let reviewing: Set<String>
    let heard: Set<String>

    /// Mid-sentence is no time to read a list. Anything past a few chips is
    /// reference material, and reference material belongs on Today.
    ///
    /// The one owner of the cut: the live matcher listens for exactly the words
    /// this returns, so a chip can never light up for a word off the strip —
    /// or stay dark for one on it.
    static func shown(_ words: [String]) -> [String] { Array(words.prefix(4)) }

    private var shown: [String] { Self.shown(words) }

    var body: some View {
        let used = shown.filter { heard.contains($0.lowercased()) }
        let pending = shown.filter { !heard.contains($0.lowercased()) }

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
        .motion(AppMotion.settle, value: heard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vocabAccessibilityLabel(used: used, pending: pending))
    }

    private func vocabAccessibilityLabel(used: [String], pending: [String]) -> String {
        if pending.isEmpty {
            return "All spotlight words used: \(shown.joined(separator: ", "))"
        }
        if used.isEmpty {
            return "Words to use: \(pending.joined(separator: ", "))"
        }
        return "Used \(used.joined(separator: ", ")). Still to use: \(pending.joined(separator: ", "))"
    }

    private func chip(_ word: String) -> some View {
        let on = heard.contains(word.lowercased())
        let chipTint = on ? AppColors.success : sourceTint(for: word)
        return HStack(spacing: 4) {
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(word)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(chipTint.opacity(on ? 0.28 : 0.18))
                .overlay {
                    Capsule().strokeBorder(chipTint.opacity(on ? 0.55 : 0.35), lineWidth: 0.5)
                }
        }
    }

    private func sourceTint(for word: String) -> Color {
        let key = word.lowercased()
        if reviewing.contains(key) { return AppColors.primary }
        if introduced.contains(key) { return AppColors.categorySage }
        return .white
    }
}

// MARK: - Compact Prompt Card

/// Isolated so expand/collapse `@State` survives the 10 Hz recording tick.
/// A `Button` here works; a `Menu` in the parent tree did not.
private struct CompactPromptCard: View {
    let category: String
    let text: String
    @State private var expanded = false

    var body: some View {
        Button {
            Haptics.light()
            expanded.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(category)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }

                Text(text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(expanded ? 8 : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .motion(AppMotion.settle, value: expanded)
        .accessibilityLabel("Prompt, \(category)")
        .accessibilityValue(text)
        .accessibilityHint(expanded ? "Collapses the prompt" : "Shows the full prompt")
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
