import SwiftUI
import SwiftData
import UIKit

// MARK: - Baseline Briefing

/// The coach sits down. Four conversational beats answer why we're recording,
/// what gets measured, why there's no script, and what the rules are — before
/// the mic is anywhere near live. Bubbles cascade in; a tap fast-forwards.
struct OnboardingBaselineBriefingStep: View {
    let userName: String
    let onContinue: () -> Void
    let onNotNow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var revealedBeats = 0

    private var openerBeat: String {
        userName.isEmpty
            ? "One short recording sets your starting line."
            : "One short recording sets your starting line, \(userName)."
    }

    var body: some View {
        VStack(spacing: 0) {
            PageScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 10) {
                        OnboardingOrb(size: 96)
                        Text("Your baseline")
                            .eyebrowStyle()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                    bubble(index: 0) {
                        beatText(openerBeat)
                    }

                    bubble(index: 1) {
                        VStack(alignment: .leading, spacing: 10) {
                            beatText("We'll measure pace, clarity, fillers, and pauses, only from what you choose to record.")
                            FlowLayout(spacing: 6) {
                                ForEach(["Pace", "Clarity", "Fillers", "Pauses"], id: \.self) { metric in
                                    StatusPill(text: metric, color: AppColors.primary, glyph: .dot)
                                }
                            }
                        }
                    }

                    bubble(index: 2) {
                        beatText("No script. The muscle we're building is thinking on the spot.")
                    }

                    bubble(index: 3) {
                        beatText("30 seconds is enough. No grade, no pressure. This is your starting line.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The whole page is a fast-forward. A tap mid-cascade means "I'm
            // reading faster than you're talking", never "I missed it".
            .contentShape(Rectangle())
            .onTapGesture { revealedBeats = 4 }

            VStack(spacing: 10) {
                OnboardingCTA(title: "Set my starting line", icon: "mic.fill", action: onContinue)
                OnboardingTextButton(title: "Not now, I'll explore the app first", action: onNotNow)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .motion(AppMotion.settle, value: revealedBeats)
        .task {
            // Opacity-hidden bubbles are invisible to VoiceOver too, so the
            // cascade collapses whenever pacing is theirs, not ours.
            guard !reduceMotion, !voiceOverEnabled else {
                revealedBeats = 4
                return
            }
            for beat in 1...4 {
                try? await Task.sleep(for: .milliseconds(beat == 1 ? 250 : 900))
                if revealedBeats < beat {
                    revealedBeats = beat
                    Haptics.light()
                }
            }
        }
    }

    private func beatText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.92))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bubble(index: Int, @ViewBuilder content: () -> some View) -> some View {
        GlassCard(padding: 14) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(revealedBeats > index ? 1 : 0)
        .offset(y: revealedBeats > index ? 0 : 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Baseline Step

/// The terminal step: guided take → analysis → reveal, all inside onboarding.
/// The prompt is pinned for the entire take, the user presses record, the
/// countdown plays inside the button, and both escape hatches (restart, swap
/// prompt) sit at arm's length.
struct OnboardingBaselineStep: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpeechService.self) private var speechService
    @Environment(LLMService.self) private var llmService

    let viewModel: OnboardingViewModel
    let userName: String
    let onComplete: (_ baselineRecordingID: UUID?, _ review: Bool) -> Void

    @State private var savedRecording: Recording?
    @State private var promptIndex = 0

    /// Prompts everyone can answer, phrased to produce natural free speech —
    /// better baseline data than read speech, and content the reveal can talk
    /// back to. Starters are teleprompter crutches, not inputs.
    private static let prompts: [(text: String, starters: [String])] = [
        ("Introduce yourself. What do you do, and what kind of speaking do you want to improve?",
         ["\u{201C}My name is…\u{201D}", "\u{201C}I spend my days…\u{201D}", "\u{201C}I want to sound…\u{201D}"]),
        ("Describe your typical morning, start to finish.",
         ["\u{201C}I usually wake up…\u{201D}", "\u{201C}The first thing I do…\u{201D}", "\u{201C}By mid-morning…\u{201D}"]),
        ("What's something you know a lot about? Explain it simply.",
         ["\u{201C}Something I know well is…\u{201D}", "\u{201C}It works like this…\u{201D}", "\u{201C}Most people don't realize…\u{201D}"])
    ]

    private var phase: OnboardingViewModel.BaselinePhase { viewModel.baselinePhase }
    private var prompt: (text: String, starters: [String]) { Self.prompts[promptIndex] }

    var body: some View {
        Group {
            if let recording = savedRecording {
                OnboardingBaselineResultView(
                    recording: recording,
                    userName: userName,
                    onRetake: { retake(deleting: recording) },
                    onRetryProcessing: { reprocess(recording) },
                    onComplete: { review in onComplete(recording.id, review) }
                )
            } else {
                recorderPage
            }
        }
        .motion(AppMotion.settle, value: savedRecording != nil)
        .motion(AppMotion.settle, value: isTakeLive)
        .onChange(of: viewModel.baselinePhase) { _, newPhase in
            guard newPhase == .recording else { return }
            let count = (try? modelContext.fetchCount(FetchDescriptor<Recording>())) ?? 0
            AnalyticsService.shared.log(.practiceStarted(useCase: "baseline", sessionNumber: count + 1))
            UIAccessibility.post(notification: .announcement, argument: "Recording started")
        }
        .onChange(of: viewModel.baselineElapsed) { _, seconds in
            guard phase == .recording, seconds == 30 else { return }
            Haptics.light()
            UIAccessibility.post(notification: .announcement, argument: "30 seconds, enough for a baseline. You can stop anytime.")
        }
    }

    // MARK: - Recorder

    private var recorderPage: some View {
        OnboardingPage(
            counter: "Your baseline",
            title: recorderTitle
        ) {
            if !viewModel.hasMicPermission {
                permissionContent
            } else {
                takeContent
            }
        } footer: {
            if !viewModel.hasMicPermission {
                permissionFooter
            } else {
                takeFooter
            }
        }
    }

    private var recorderTitle: String {
        if !viewModel.hasMicPermission { return "Big Talk can't hear you yet" }
        return prompt.text
    }

    /// The take is live from the moment audio starts until the row exists.
    /// `saving` reads as live on purpose: the recorder must not reappear
    /// underneath a take the user already finished.
    private var isTakeLive: Bool { phase == .recording || phase == .saving }

    @ViewBuilder
    private var takeContent: some View {
        if isTakeLive {
            recordingReadout
        } else {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("If you're stuck, start with")
                        .eyebrowStyle()
                    FlowLayout(spacing: 8) {
                        ForEach(prompt.starters, id: \.self) { starter in
                            starterChip(starter)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            escapeHatchRow

            if let note = viewModel.baselineNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
    }

    /// Deliberately uncarded. The app's recorder puts the clock straight on the
    /// canvas above the waveform ring, and a glass box around the numbers was
    /// the loudest tell that this was an onboarding mock-up of that screen.
    private var recordingReadout: some View {
        VStack(spacing: 10) {
            ElapsedClock(viewModel: viewModel)

            TickMeter(
                fraction: min(Double(viewModel.baselineElapsed) / 90.0, 1),
                color: viewModel.baselineElapsed >= 30 ? AppColors.success : AppColors.primary,
                tickCount: 30
            )
            .frame(height: 10)
            .frame(maxWidth: 260)

            if viewModel.baselineElapsed >= 30 {
                StatusPill(
                    text: "Enough for a baseline",
                    color: AppColors.success,
                    glyph: .icon("checkmark")
                )
                .transition(.scale.combined(with: .opacity))
            } else {
                Text("30 seconds is enough")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let line = encouragement(for: viewModel.baselineElapsed) {
                Text(line)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(line)
                    .transition(.opacity)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .motion(AppMotion.settle, value: viewModel.baselineElapsed >= 30)
        .motion(AppMotion.settle, value: encouragement(for: viewModel.baselineElapsed))
    }

    /// One-liners in the coach's voice, timed to the moments nerves spike:
    /// just after starting, mid-take, once the minimum is banked, and long.
    private func encouragement(for seconds: Int) -> String? {
        switch seconds {
        case ..<8: return nil
        case ..<22: return "You're doing great."
        case ..<30: return "Say it however it comes. There's no wrong answer."
        case ..<55: return "Stop anytime, or keep rolling."
        default: return "Strong. Wrap up whenever you like."
        }
    }

    /// No script escape hatch on purpose: the baseline (and the app) trains
    /// thinking on the spot, and a read-aloud take wouldn't compare honestly
    /// against the spontaneous sessions that follow. The starter chips are
    /// the anti-freeze aid; Read-Aloud practice lives in the Library.
    private var escapeHatchRow: some View {
        quietButton("Different question", icon: "arrow.trianglehead.2.clockwise") {
            Haptics.selection()
            promptIndex = (promptIndex + 1) % Self.prompts.count
            AnalyticsService.shared.log(.onboardingStep("baseline", action: "swap_prompt"))
        }
        .frame(maxWidth: .infinity)
        .disabled(phase != .ready)
        .opacity(phase == .ready ? 1 : 0.4)
    }

    private func quietButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func starterChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().strokeBorder(AppColors.cardStroke, lineWidth: 0.5) }
            }
    }

    // MARK: - Footers

    /// One control for every phase. The button never moves, never changes size,
    /// and never swaps places with a different button between "ready" and
    /// "recording" — the screen the user is looking at when they press record is
    /// the same screen they're looking at while they talk.
    private var takeFooter: some View {
        VStack(spacing: 8) {
            BaselineRecordControl(
                viewModel: viewModel,
                canFinish: viewModel.baselineElapsed >= 30,
                onTap: {
                    switch phase {
                    case .ready: viewModel.beginBaselineCountdown()
                    case .recording: finishTake()
                    case .countdown, .saving: break
                    }
                }
            )

            Text(controlHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id(controlHint)
                .transition(.opacity)

            if phase == .recording {
                OnboardingTextButton(title: "Start over") {
                    viewModel.discardBaselineTake(note: "No problem. Nothing was saved.")
                    AnalyticsService.shared.log(.onboardingStep("baseline", action: "retry"))
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .motion(AppMotion.settle, value: phase)
        .motion(AppMotion.settle, value: viewModel.baselineElapsed >= 30)
    }

    private var controlHint: String {
        switch phase {
        case .ready: return "Tap when you're ready. Retry as many times as you like."
        case .countdown: return "Here we go."
        case .saving: return "Saving your take…"
        case .recording:
            // A baseline take is 30 seconds minimum — the stop button unlocks
            // at the same moment the "Enough for a baseline" tick flips, so
            // the floor and the goal are one number. Start over stays available.
            return viewModel.baselineElapsed >= 30
                ? "Tap to stop whenever you're done."
                : "Keep going. You can stop at 30 seconds."
        }
    }

    // MARK: - Permission-blocked

    private var permissionContent: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingBullet(
                    icon: "mic.fill",
                    text: "Your baseline needs the microphone. It's the one thing Big Talk can't work without."
                )
                OnboardingBullet(
                    icon: "lock.fill",
                    text: "Nothing records until you press the button.",
                    tint: AppColors.success
                )
            }
        }
    }

    @ViewBuilder
    private var permissionFooter: some View {
        if viewModel.micPermissionDenied {
            OnboardingCTA(title: "Open Settings", icon: "gear") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        } else {
            OnboardingCTA(
                title: viewModel.isRequestingMicPermission ? "Asking…" : "Allow microphone",
                icon: viewModel.isRequestingMicPermission ? nil : "arrow.right",
                isLoading: viewModel.isRequestingMicPermission
            ) {
                Task { await viewModel.requestMicPermissionOnly() }
            }
        }
        OnboardingTextButton(title: "Explore the app first") {
            AnalyticsService.shared.log(.onboardingStep("baseline", action: "skip"))
            onComplete(nil, false)
        }
    }

    // MARK: - Persistence

    private func finishTake() {
        Task {
            guard let take = await viewModel.finishBaselineTake() else { return }
            let recording = Recording(
                targetDuration: 60,
                actualDuration: take.duration,
                mediaType: .audio,
                audioURL: take.url,
                isProcessing: true,
                audioLevelSamples: take.levelSamples
            )
            recording.customTitle = "My baseline"
            modelContext.insert(recording)
            try? modelContext.save()
            RecordingProcessingCoordinator.shared.enqueue(
                recordingID: recording.id,
                modelContext: modelContext,
                speechService: speechService,
                llmService: llmService
            )
            AnalyticsService.shared.log(.onboardingStep("baseline", action: "take_saved"))
            savedRecording = recording
        }
    }

    /// Quality retake: the take analyzed to nothing (silence, gibberish), so
    /// the row and its audio go — the user starts clean, never re-judged.
    private func retake(deleting recording: Recording) {
        // Stop observing before deleting — a body re-evaluation against a
        // deleted SwiftData object traps.
        savedRecording = nil
        if let url = recording.resolvedAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(recording)
        try? modelContext.save()
        viewModel.discardBaselineTake(note: "Fresh take. Same prompt, whenever you're ready.")
        AnalyticsService.shared.log(.onboardingStep("baseline", action: "retry"))
    }

    private func reprocess(_ recording: Recording) {
        recording.lastProcessingError = nil
        recording.isProcessing = true
        try? modelContext.save()
        RecordingProcessingCoordinator.shared.enqueue(
            recordingID: recording.id,
            modelContext: modelContext,
            speechService: speechService,
            llmService: llmService
        )
    }
}

/// The app's recorder anatomy — radial waveform ring wrapped around a record
/// button — reused verbatim rather than restyled. The baseline take is the
/// user's first sight of the screen they'll open from Today every day after
/// this, so it is that screen, not a page that happens to record.
private struct BaselineRecordControl: View {
    let viewModel: OnboardingViewModel
    let canFinish: Bool
    let onTap: () -> Void

    private var phase: OnboardingViewModel.BaselinePhase { viewModel.baselinePhase }

    var body: some View {
        ZStack {
            BaselineWaveformRing(viewModel: viewModel)
                .opacity(phase == .recording ? 1 : 0.3)

            switch phase {
            case .ready:
                RecordButton(isRecording: false, onTap: onTap)
                    .pulsingGlow(color: AppColors.recording, isActive: true)

            case .countdown:
                // The count runs inside the button's own footprint: nothing
                // moves, nothing is covered, and the prompt stays readable
                // right up to the first word.
                buttonShell {
                    Text("\(viewModel.baselineCountdownValue)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .motion(AppMotion.snap, value: viewModel.baselineCountdownValue)
                }
                .accessibilityLabel("Starting in \(viewModel.baselineCountdownValue)")

            case .recording:
                RecordButton(isRecording: true, onTap: onTap)
                    .disabled(!canFinish)
                    .opacity(canFinish ? 1 : 0.45)

            case .saving:
                buttonShell {
                    ProgressView()
                        .tint(.white)
                }
                .accessibilityLabel("Saving your take")
            }
        }
        .frame(height: 220)
        .motion(AppMotion.settle, value: phase)
    }

    /// Same 80pt glass disc `RecordButton` draws, for the two states that show
    /// something other than a record dot inside it.
    private func buttonShell(@ViewBuilder content: () -> some View) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay { Circle().strokeBorder(.white.opacity(0.3), lineWidth: 2) }
            content()
        }
        .frame(width: 80, height: 80)
    }
}

/// The only view reading the 16 Hz meter, so its updates stop here instead of
/// invalidating the whole recorder page (perf-patterns §3).
private struct BaselineWaveformRing: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        // `CircularWaveformView` expects raw dBFS; `micLevel` is already
        // normalised 0–1, so map it back onto the −60…0 range it normalises.
        CircularWaveformView(audioLevel: viewModel.micLevel * 60 - 60)
    }
}

private struct ElapsedClock: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        let seconds = viewModel.baselineElapsed
        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .accessibilityLabel("\(seconds) seconds recorded")
    }
}

// MARK: - Result (analyzing → reveal)

/// Owns everything after the take is saved: the staged analyzing theater, the
/// couldn't-hear coaching, the failure path, and the reveal. Observes the
/// `Recording` row directly — the coordinator writes transcript + analysis to
/// it on MainActor.
private struct OnboardingBaselineResultView: View {
    let recording: Recording
    let userName: String
    let onRetake: () -> Void
    let onRetryProcessing: () -> Void
    let onComplete: (_ review: Bool) -> Void

    @State private var shownStages = 0
    @State private var retryToken = 0

    private static let stages = [
        "Transcribing your words",
        "Measuring your pace",
        "Counting pauses and fillers",
        "Setting your baseline"
    ]

    private var failed: Bool {
        recording.lastProcessingError != nil
            && recording.analysis == nil
            && !recording.isProcessing
    }

    var body: some View {
        Group {
            if failed {
                errorState
            } else if let analysis = recording.analysis, shownStages >= Self.stages.count {
                // The zero-score gate means silence or gibberish. A first-time
                // user never sees that as a number — they get coached back
                // into a retake instead.
                if analysis.speechScore.overall == 0 {
                    couldNotHearState
                } else {
                    // One forward action, and it lands on the breakdown. The
                    // reveal is a headline; the detail view is where a first
                    // score becomes information, so offering "home" instead
                    // was offering people the version with nothing in it.
                    OnboardingBaselineRevealView(
                        analysis: analysis,
                        userName: userName,
                        onSeeBreakdown: { onComplete(true) }
                    )
                }
            } else {
                analyzingState
            }
        }
        .motion(AppMotion.settle, value: shownStages)
        .motion(AppMotion.settle, value: failed)
        .task(id: retryToken) { await runStages() }
    }

    /// First three rows are paced for comprehension; the last waits on the
    /// real pipeline. Transcript and analysis persist in one save, so the
    /// stage labels are rhythm, not per-stage telemetry — the gate is real.
    private func runStages() async {
        shownStages = 0
        while shownStages < Self.stages.count {
            if shownStages == Self.stages.count - 1 {
                while recording.analysis == nil {
                    if failed { return }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            } else {
                try? await Task.sleep(for: .milliseconds(900))
            }
            shownStages += 1
            Haptics.light()
        }
    }

    private var analyzingState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                OnboardingOrb(size: 104)

                Text("Reading your voice…")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                GlassCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(Array(Self.stages.enumerated()), id: \.offset) { index, stage in
                            stageRow(stage, state: stageState(for: index))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
    }

    private enum StageState { case pending, active, done }

    private func stageState(for index: Int) -> StageState {
        if index < shownStages { return .done }
        if index == shownStages { return .active }
        return .pending
    }

    private func stageRow(_ label: String, state: StageState) -> some View {
        HStack(spacing: 10) {
            switch state {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.success)
            case .active:
                Image(systemName: "circle.dotted")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.primary)
                    .symbolEffect(.pulse)
            case .pending:
                Image(systemName: "circle.dotted")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.25))
            }

            Text(label)
                .font(.footnote.weight(state == .pending ? .regular : .medium))
                .foregroundStyle(state == .pending ? Color.secondary : Color.white.opacity(0.9))
        }
        .accessibilityElement(children: .combine)
    }

    private var couldNotHearState: some View {
        OnboardingPage(
            counter: "Your baseline",
            title: "We couldn't hear enough to read your voice",
            subtitle: "Happens all the time. Two quick checks, then let's take it again."
        ) {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingBullet(icon: "iphone", text: "Hold the phone about a forearm's length away.")
                    OnboardingBullet(icon: "speaker.slash", text: "A quiet room helps the transcriber hear you, not the background.")
                }
            }
        } footer: {
            OnboardingCTA(title: "Take it again", icon: "arrow.counterclockwise", action: onRetake)
            OnboardingTextButton(title: "Continue anyway") { onComplete(false) }
        }
    }

    private var errorState: some View {
        OnboardingPage(
            counter: "Your baseline",
            title: "That didn't go through",
            subtitle: "Your recording is safe on this iPhone. We can try scoring it again."
        ) {
            EmptyView()
        } footer: {
            OnboardingCTA(title: "Try again", icon: "arrow.counterclockwise") {
                onRetryProcessing()
                retryToken += 1
            }
            OnboardingTextButton(title: "Continue and score it later") { onComplete(false) }
        }
    }
}

// MARK: - Reveal

/// The payoff: starting line, not report card. One score, two metrics, one
/// coaching insight, and the promise that every later session compares back
/// to this. A low first score never leads with the number — first-session
/// churn is not worth numeric purity.
///
/// One exit, and it goes forward into the breakdown. The screen used to offer
/// "Take me home" alongside it, which let people leave the flow one tap before
/// the part that explains their score.
private struct OnboardingBaselineRevealView: View {
    let analysis: SpeechAnalysis
    let userName: String
    let onSeeBreakdown: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringProgress: Double = 0
    @State private var showConfetti = false

    private var score: Int { analysis.speechScore.overall }
    private var supportive: Bool { score < 40 }
    private var fillerCount: Int { analysis.fillerWords.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(spacing: 0) {
            PageScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text("Your starting line")
                            .eyebrowStyle()
                        Text(headline)
                            .font(.title.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if supportive {
                            Text("Plenty of headroom, and headroom is the fun part. Your numbers are in the breakdown.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 12)

                    if !supportive {
                        scoreRing
                            .padding(.vertical, 6)
                    }

                    HStack(spacing: 10) {
                        metricChip(label: "Pace", value: "\(Int(analysis.wordsPerMinute)) wpm")
                        metricChip(label: "Fillers", value: "\(fillerCount)")
                    }

                    if let tip = CoachingTipService.generateTips(from: analysis).first {
                        GlassCard(tint: AppColors.glassTintPrimary, padding: 14) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: tip.icon)
                                    .font(.subheadline)
                                    .foregroundStyle(AppColors.primary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tip.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(tip.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }

                    VStack(spacing: 8) {
                        Text("Every session from now on is compared to this.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        StatusPill(text: "Day 1", color: AppColors.warning, glyph: .icon("flame.fill"))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            OnboardingCTA(title: "See my full breakdown", icon: "chart.bar.fill", action: onSeeBreakdown)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .overlay {
            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .onAppear { runReveal() }
    }

    private var headline: String {
        if supportive { return "You showed up. That's the hard part." }
        return userName.isEmpty ? "There it is." : "There it is, \(userName)."
    }

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(AppColors.meterTrack, lineWidth: 12)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    AppColors.scoreColor(for: score),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(AppColors.scoreVerdict(for: score))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.scoreColor(for: score))
            }
        }
        .frame(width: 150, height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Starting line score \(score) out of 100, \(AppColors.scoreVerdict(for: score))")
    }

    private func metricChip(label: String, value: String) -> some View {
        GlassCard(padding: 12) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private func runReveal() {
        Haptics.success()
        AnalyticsService.shared.log(.onboardingStep("baseline", action: "reveal"))
        let target = Double(score) / 100.0

        guard !reduceMotion else {
            ringProgress = target
            return
        }
        withAnimation(AppMotion.reveal.delay(0.2)) {
            ringProgress = target
        }
        // Ascending ticks while the ring sweeps — the score arrives as an
        // event, not a label.
        Task {
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(180))
                Haptics.light()
            }
        }
        if !supportive {
            showConfetti = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                showConfetti = false
            }
        }
    }
}
