import SwiftUI
import SwiftData
import UIKit

/// Interactive first-launch flow. Four quick questions build toward the one
/// thing that matters: the guided baseline recording, which happens *inside*
/// onboarding — briefing, take, analysis, and score reveal — instead of
/// dropping the user into an unguided recorder afterwards.
///
/// Voice calibration, the on-device model, and reminders are not here. They ask
/// for effort, storage, or a system permission before the app has produced a
/// single score, so `FirstRecordingSetupSheet` offers them afterwards instead.
/// Their steps still exist and still work — they are simply not in
/// `OnboardingStep.firstRunSteps`.
///
/// Question pages route through `OnboardingPage`, so the header rhythm, glass
/// surfaces, and call-to-action placement match the rest of the app instead of
/// each step inventing its own layout.
struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var onComplete: (OnboardingResult) -> Void

    var body: some View {
        ZStack {
            // The canvas darkens for the live take, exactly like the app's own
            // recorder — the baseline should feel like the recording screen the
            // user will meet again tomorrow, not a page that happens to record.
            AppBackground(style: isTakeLive ? .recording : .subtle)
                .ignoresSafeArea()
                .motion(AppMotion.settle, value: isTakeLive)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                ZStack {
                    stepContent
                        .id(viewModel.currentStep)
                        // The arriving page rises as it fades in; the outgoing
                        // one only fades. Deliberately direction-agnostic: a
                        // horizontal push would need the removal transition to
                        // know which way it is leaving, and SwiftUI resolves a
                        // removed view's transition from the state it was
                        // created with, so Back would exit the wrong way.
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 14)),
                            removal: .opacity
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .motion(AppMotion.settle, value: viewModel.currentStep)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $viewModel.showingCalibration) {
            VoiceCalibrationView { profile in
                viewModel.applyCalibration(profile)
            }
        }
        .onAppear {
            viewModel.checkMicPermission()
            viewModel.restoreFromDefaults()
            Task { await viewModel.checkNotificationPermission() }
        }
        .onChange(of: viewModel.currentStep) { oldStep, newStep in
            // Dismiss the keyboard on every transition. The name step
            // re-acquires focus after the crossfade settles.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
            // Centralised mic-test lifecycle so leaving via Back/Skip/Continue
            // always tears down the recording. The calibration step that
            // follows drives its own session and cannot share the device.
            if oldStep == .mic, newStep != .mic {
                viewModel.stopMicTest()
            }
            if newStep == .mic, oldStep != .mic, viewModel.hasMicPermission {
                Task { await viewModel.resumeMicTestIfPermitted() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The mic test holds a live recording. Leaving it running while the
            // app is backgrounded keeps the system recording indicator lit and
            // burns battery for a meter nobody can see.
            if viewModel.currentStep == .mic {
                if phase == .active {
                    Task { await viewModel.resumeMicTestIfPermitted() }
                } else {
                    viewModel.stopMicTest()
                }
            }
            // A baseline take interrupted by backgrounding (call, app switch)
            // is discarded rather than resumed — a take with a hole in it
            // would poison the one recording everything gets compared to.
            // `.saving` is deliberately excluded: the audio is already stopped
            // and the row is moments from existing, so discarding there would
            // throw away a finished take.
            if viewModel.currentStep == .baseline,
               phase != .active,
               viewModel.baselinePhase == .countdown || viewModel.baselinePhase == .recording {
                viewModel.discardBaselineTake(note: "We saved nothing. Clean slate whenever you're ready.")
            }
        }
        .onDisappear {
            viewModel.stopMicTest()
        }
    }

    private var isTakeLive: Bool {
        viewModel.currentStep == .baseline
            && (viewModel.baselinePhase == .countdown || viewModel.baselinePhase == .recording)
    }

    // MARK: - Top Bar

    /// Both gutters are fixed and equal so the tick meter keeps one width and
    /// one centre across every step. "Skip" is wider than the back chevron,
    /// and letting the row self-size made the meter twitch on each transition.
    private static let topBarGutter: CGFloat = 44

    private var topBar: some View {
        HStack(alignment: .center, spacing: 14) {
            if viewModel.currentStep.allowsBack {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay { Circle().stroke(AppColors.cardStroke, lineWidth: 0.5) }
                        }
                }
                .buttonStyle(GlassPressStyle())
                .frame(width: Self.topBarGutter, alignment: .leading)
                .accessibilityLabel("Back")
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: Self.topBarGutter, height: 34)
            }

            // Ticks read as discrete steps rather than a loading bar: one
            // tick per page, using the app's shared meter primitive. Hidden on
            // hero steps: the cover should read as a cover, and the baseline
            // is the event the ticks build toward, not another tick.
            //
            // Decorative to VoiceOver on purpose: every non-hero page already
            // announces "Step N of 4" as the first line of its header, so
            // labelling the meter too would read the position twice.
            TickMeter(
                fraction: viewModel.stepProgress,
                color: AppColors.primary,
                tickCount: viewModel.stepCount
            )
            .frame(height: 12)
            .opacity(viewModel.currentStep.isHero ? 0 : 1)
            .motion(AppMotion.settle, value: viewModel.stepProgress)

            // Skip makes no sense on the cover or the terminal step, and would
            // duplicate the footer action on steps that decline explicitly.
            if !viewModel.currentStep.isHero, !viewModel.currentStep.providesOwnSkip {
                Button("Skip") {
                    viewModel.skip()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: Self.topBarGutter, height: 34, alignment: .trailing)
            } else {
                Color.clear.frame(width: Self.topBarGutter, height: 34)
            }
        }
        .motion(AppMotion.settle, value: viewModel.currentStep)
    }

    // MARK: - Step Routing

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            OnboardingWelcomeStep(onContinue: viewModel.advance)

        case .name:
            OnboardingNameStep(
                counter: viewModel.stepCounterLabel,
                name: $viewModel.nameInput,
                canAdvance: viewModel.canAdvanceFromName,
                onContinue: viewModel.advance
            )

        case .goal:
            OnboardingGoalStep(
                counter: viewModel.stepCounterLabel,
                userName: viewModel.trimmedName,
                selectedGoals: viewModel.selectedGoals,
                maxGoals: OnboardingViewModel.maxGoals,
                onToggle: viewModel.toggleGoal,
                onContinue: viewModel.advance
            )

        case .level:
            OnboardingLevelStep(
                counter: viewModel.stepCounterLabel,
                selected: viewModel.hasPickedLevel ? viewModel.speakerLevel : nil,
                onSelect: viewModel.selectLevel,
                onContinue: viewModel.advance
            )

        case .mic:
            // Takes the view model rather than a `level:` snapshot on purpose.
            // Reading `micLevel` here would re-evaluate this whole body (top
            // bar, tick meter, every page) 16 times a second while the meter
            // runs. The step keeps that read inside its own waveform subview.
            OnboardingMicStep(
                counter: viewModel.stepCounterLabel,
                viewModel: viewModel,
                onContinue: viewModel.advance
            )

        case .baselineBriefing:
            OnboardingBaselineBriefingStep(
                userName: viewModel.trimmedName,
                onContinue: viewModel.advance,
                onNotNow: {
                    AnalyticsService.shared.log(.onboardingStep("baseline_briefing", action: "skip"))
                    onComplete(viewModel.makeResult())
                }
            )

        case .baseline:
            OnboardingBaselineStep(
                viewModel: viewModel,
                userName: viewModel.trimmedName,
                onComplete: { recordingID, review in
                    Haptics.success()
                    onComplete(viewModel.makeResult(
                        baselineRecordingID: recordingID,
                        reviewBaseline: review
                    ))
                }
            )

        case .calibrate:
            OnboardingCalibrationStep(
                counter: viewModel.stepCounterLabel,
                hasMicPermission: viewModel.hasMicPermission,
                isRequestingMic: viewModel.isRequestingMicPermission,
                hasCalibrated: viewModel.hasCalibratedVoice,
                onRequestMic: {
                    Task { await viewModel.requestMicPermissionOnly() }
                },
                onCalibrate: viewModel.startCalibration,
                onContinue: viewModel.advance,
                onSkip: viewModel.skip
            )

        case .intelligence:
            OnboardingIntelligenceStep(
                counter: viewModel.stepCounterLabel,
                onContinue: viewModel.advance
            )

        case .reminder:
            OnboardingReminderStep(
                counter: viewModel.stepCounterLabel,
                hasPermission: viewModel.hasNotificationPermission,
                isRequesting: viewModel.isRequestingNotificationPermission,
                reminderEnabled: $viewModel.reminderEnabled,
                reminderTime: $viewModel.reminderTime,
                onEnable: {
                    Task { await viewModel.requestNotificationPermission() }
                },
                onContinue: viewModel.advance,
                onSkip: {
                    viewModel.reminderEnabled = false
                    viewModel.skip()
                }
            )

        }
    }
}

// MARK: - Previews

#Preview("Onboarding") {
    OnboardingView { _ in }
        .environment(LLMService())
        .environment(AudioService())
        .environment(SpeechService())
        .modelContainer(for: [Recording.self, Prompt.self, UserSettings.self], inMemory: true)
}
