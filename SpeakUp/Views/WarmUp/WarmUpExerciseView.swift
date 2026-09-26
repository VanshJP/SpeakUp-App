import SwiftUI
import UIKit

/// The warm-up runner: ready → (breathing: count-in) → steps → done.
///
/// It used to open mid-exercise - step 1's label, a bare countdown, and the
/// transport trio - so the first thing on screen was a clock that was not
/// running. The label was a single truncating line ("Breathe In Through the
/// No…"), progress was "Step 1 of 9" for what is three breaths, and pausing
/// meant finding a 72pt button under your thumb with your eyes closed.
///
/// Now the runner opens on what the exercise is, how long it takes and how
/// many rounds, with one Begin. The orb is the timer (a ring around it shows
/// the step's elapsed share, the count sits inside), the cue gets a short
/// phase word plus the full instruction on as many lines as it needs, the
/// next step is previewed, and the whole orb is the pause control.
struct WarmUpExerciseView: View {
    var viewModel: WarmUpViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingExitConfirm = false

    /// Announces each step change to VoiceOver - the countdown numeral and
    /// the chirps are otherwise silent context for a non-visual reader.
    @State private var announcedStepIndex = -1

    private var exercise: WarmUpExercise? { viewModel.currentExercise }
    private var tint: Color { exercise?.category.color ?? AppColors.primary }
    private var isBreathing: Bool { exercise?.category == .breathing }

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 0) {
                topBar

                if viewModel.isComplete {
                    completeView
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else if !viewModel.hasStarted {
                    readyView
                        .transition(.opacity)
                } else {
                    runningView
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .motion(AppMotion.settle, value: viewModel.hasStarted)
            .motion(AppMotion.settle, value: viewModel.isComplete)
        }
        // Breathing rounds and hums are hands-off by design; Auto-Lock used to
        // dim the screen partway through a round.
        .keepsScreenAwake(viewModel.isRunning)
        .onChange(of: viewModel.isComplete) { _, complete in
            guard complete else { return }
            PracticeRoutineService.shared.complete(.warmUp)
        }
        .onChange(of: viewModel.currentStepIndex) { _, newIndex in
            announceStep(newIndex)
        }
        .onChange(of: viewModel.isLeadingIn) { _, leadingIn in
            if !leadingIn { announceStep(viewModel.currentStepIndex) }
        }
    }

    private func announceStep(_ index: Int) {
        guard viewModel.hasStarted, !viewModel.isComplete, !viewModel.isLeadingIn,
              index != announcedStepIndex,
              let step = viewModel.currentStep else { return }
        announcedStepIndex = index
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(step.label), \(viewModel.timeRemaining) seconds"
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 14) {
            ZStack {
                if viewModel.hasStarted, !viewModel.isComplete {
                    Text(exercise?.title ?? "")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, 56)
                        .transition(.opacity)
                }

                HStack {
                    closeButton
                    Spacer()
                }
            }

            if viewModel.hasStarted, !viewModel.isComplete {
                runProgress
                    .transition(.opacity)
            }
        }
        .padding(.top, 8)
        .confirmationDialog(
            "End this warm-up?",
            isPresented: $showingExitConfirm,
            titleVisibility: .visible
        ) {
            Button("End Warm-Up", role: .destructive) {
                viewModel.cleanup()
                dismiss()
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Progress in this warm-up won't be saved.")
        }
    }

    private var closeButton: some View {
        Button {
            if viewModel.hasStarted, !viewModel.isComplete {
                Haptics.warning()
                showingExitConfirm = true
            } else {
                viewModel.cleanup()
                dismiss()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close warm-up")
    }

    /// Rounds for breathing, where "step 4 of 9" meant nothing; step segments
    /// for everything else, where each step is a different thing to say.
    private var runProgress: some View {
        let isRounds = viewModel.totalRounds > 1
        let count = isRounds ? viewModel.totalRounds : (exercise?.steps.count ?? 1)
        let current = isRounds ? viewModel.currentRound - 1 : viewModel.currentStepIndex
        let caption = isRounds
            ? "Round \(viewModel.currentRound) of \(viewModel.totalRounds)"
            : "Step \(viewModel.currentStepIndex + 1) of \(count)"

        return VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(index < current
                              ? tint
                              : index == current ? tint.opacity(0.75) : Color.white.opacity(0.14))
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: 240)
            .motion(AppMotion.slide, value: current)

            Text(caption)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
    }

    // MARK: - Ready

    private var readyView: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)

            if let exercise {
                VStack(spacing: 14) {
                    IconChip(icon: exercise.category.icon, tint: tint, size: 64)

                    VStack(spacing: 8) {
                        Text(exercise.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text(exercise.instructions)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        summaryChip(icon: "clock", text: "\(viewModel.totalSeconds)s")
                        summaryChip(
                            icon: isBreathing ? "arrow.triangle.2.circlepath" : "list.number",
                            text: isBreathing
                                ? "\(viewModel.totalRounds) round\(viewModel.totalRounds == 1 ? "" : "s")"
                                : "\(exercise.steps.count) steps"
                        )
                    }
                    .contentTransition(.numericText())
                    .motion(AppMotion.snap, value: viewModel.totalSeconds)
                }
            }

            Spacer(minLength: 12)

            VStack(spacing: 14) {
                if viewModel.canCustomizeRounds {
                    roundsPicker
                }

                GlassButton(
                    title: "Begin",
                    icon: "play.fill",
                    style: .primary,
                    size: .large,
                    fullWidth: true
                ) {
                    Haptics.medium()
                    viewModel.start()
                }
            }
        }
    }

    private func summaryChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassBackground(cornerRadius: 15)
    }

    private var roundsPicker: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rounds")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("One round is one full breath cycle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            stepperButton(icon: "minus", label: "Fewer rounds") {
                viewModel.rebuildWithRounds(viewModel.selectedRounds - 1)
            }
            .disabled(viewModel.selectedRounds <= WarmUpViewModel.roundsRange.lowerBound)

            Text("\(viewModel.selectedRounds)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 32)
                .contentTransition(.numericText())
                .motion(AppMotion.snap, value: viewModel.selectedRounds)

            stepperButton(icon: "plus", label: "More rounds") {
                viewModel.rebuildWithRounds(viewModel.selectedRounds + 1)
            }
            .disabled(viewModel.selectedRounds >= WarmUpViewModel.roundsRange.upperBound)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassBackground(cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rounds")
        .accessibilityValue("\(viewModel.selectedRounds)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: viewModel.rebuildWithRounds(viewModel.selectedRounds + 1)
            case .decrement: viewModel.rebuildWithRounds(viewModel.selectedRounds - 1)
            @unknown default: break
            }
        }
    }

    private func stepperButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.14)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // A painted circle has no glass to react to the touch, so the press
        // style is the only sign the tap landed.
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Running

    private var breathTargets: [CGFloat] {
        BreathingAnimationView.targets(for: exercise?.steps ?? [])
    }

    /// Short word for the breath phase, shown large; the step's own label is
    /// the instruction under it. Only breathing steps get one.
    private func phaseWord(for step: ExerciseStep) -> String? {
        guard isBreathing else { return nil }
        switch step.animation {
        case .expand: return "Breathe in"
        case .hold: return "Hold"
        case .contract: return "Breathe out"
        }
    }

    private var runningView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            orb
                .padding(.bottom, 24)

            cue
                .frame(minHeight: 132, alignment: .top)

            Spacer(minLength: 8)

            transport
        }
    }

    private var orb: some View {
        let index = viewModel.currentStepIndex
        let targets = breathTargets
        let target = isBreathing && targets.indices.contains(index) ? targets[index] : 0.82
        let isPausedMidRun = !viewModel.isRunning

        return ZStack {
            BreathingAnimationView(
                toScale: viewModel.isLeadingIn ? BreathingAnimationView.emptyScale : target,
                isRunning: viewModel.isRunning && !viewModel.isLeadingIn,
                duration: TimeInterval(viewModel.currentStep?.durationSeconds ?? 1),
                stepID: index,
                tint: tint,
                diameter: 264,
                showsRing: !viewModel.isLeadingIn
            )
            .opacity(isPausedMidRun ? 0.45 : 1)

            Group {
                if isPausedMidRun {
                    Image(systemName: "play.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(viewModel.leadInRemaining ?? viewModel.timeRemaining)")
                        .font(.displayNumeral)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .motion(AppMotion.snap, value: isPausedMidRun)
            .animation(.default, value: viewModel.timeRemaining)
            .animation(.default, value: viewModel.leadInRemaining)
        }
        .frame(width: 264, height: 264)
        .contentShape(Circle())
        .onTapGesture {
            Haptics.light()
            viewModel.togglePlayback()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPausedMidRun ? "Paused" : "\(viewModel.leadInRemaining ?? viewModel.timeRemaining) seconds")
        .accessibilityHint(isPausedMidRun ? "Double-tap to resume" : "Double-tap to pause")
        .accessibilityAddTraits([.isButton, .updatesFrequently])
    }

    @ViewBuilder
    private var cue: some View {
        if viewModel.isLeadingIn {
            cueText(
                headline: "Get ready",
                detail: "Sit tall, drop your shoulders, and let your breath settle.",
                next: viewModel.currentStep.map { "First: \($0.label)" }
            )
        } else if let step = viewModel.currentStep {
            let word = phaseWord(for: step)
            // Box breathing's labels already are the phase word; don't say it twice.
            let detail: String? = word.flatMap {
                $0.caseInsensitiveCompare(step.label) == .orderedSame ? nil : step.label
            }
            cueText(
                headline: word ?? step.label,
                detail: detail,
                next: viewModel.nextStep.map { "Next: \($0.label)" }
            )
            .id(viewModel.currentStepIndex)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }

    private func cueText(headline: String, detail: String?, next: String?) -> some View {
        VStack(spacing: 8) {
            if !viewModel.isRunning, !viewModel.isLeadingIn {
                StatusPill(text: "Paused - tap the circle to resume", color: tint)
            }

            Text(headline)
                .font(isBreathing || viewModel.isLeadingIn ? .largeTitle.weight(.bold) : .title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                Text(detail)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let next {
                Text(next)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .motion(AppMotion.settle, value: viewModel.currentStepIndex)
    }

    private var transport: some View {
        HStack(spacing: 36) {
            transportButton(icon: "arrow.counterclockwise", size: 56, label: "Restart exercise") {
                viewModel.reset()
                viewModel.start()
            }

            Button {
                Haptics.light()
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Color.white.opacity(0.94)))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    .symbolSwap(viewModel.isRunning)
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel(viewModel.isRunning ? "Pause" : "Resume")

            transportButton(
                icon: "forward.end.fill",
                size: 56,
                label: viewModel.isLeadingIn ? "Start now" : "Next step"
            ) {
                viewModel.skip()
            }
        }
        .padding(.bottom, 8)
    }

    private func transportButton(icon: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: size, height: size)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 76))
                .foregroundStyle(AppColors.success)
                .symbolEffect(.bounce, value: viewModel.isComplete)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Warm-up done")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text(isBreathing
                     ? "Breath's steady. You're ready to speak."
                     : "Voice is warm. You're ready to speak.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                summaryChip(icon: "clock", text: "\(viewModel.totalSeconds)s")
                if viewModel.totalRounds > 1 {
                    summaryChip(icon: "arrow.triangle.2.circlepath", text: "\(viewModel.totalRounds) rounds")
                } else if let count = exercise?.steps.count {
                    summaryChip(icon: "list.number", text: "\(count) steps")
                }
            }

            Spacer()

            VStack(spacing: 12) {
                GlassButton(title: "Done", style: .primary, size: .large, fullWidth: true) {
                    viewModel.cleanup()
                    dismiss()
                }

                GlassButton(title: "Go again", icon: "arrow.clockwise", style: .secondary, fullWidth: true) {
                    viewModel.goAgain()
                }
            }
        }
    }
}
