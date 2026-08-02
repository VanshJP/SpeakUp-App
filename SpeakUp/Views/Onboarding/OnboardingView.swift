import SwiftUI
import UIKit

/// Interactive first-launch flow. Two hero screens bookend nine working pages
/// that explain the app, capture practice intent, and switch on the four
/// things Big Talk needs to do its job: microphone, voice profile, an AI
/// backend, and a daily reminder.
///
/// Every page routes through `OnboardingPage`, so the header rhythm, glass
/// surfaces, and call-to-action placement match the rest of the app instead of
/// each step inventing its own layout.
struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()

    var onComplete: (OnboardingResult) -> Void

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                ZStack {
                    stepContent
                        .id(viewModel.currentStep)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .motion(.easeInOut(duration: 0.3), value: viewModel.currentStep)
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
            // Dismiss the keyboard on every transition. Steps that need it
            // (.name, .vocab) re-acquire focus after the crossfade settles.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
            // Centralised mic-test lifecycle so leaving via Back/Skip/Continue
            // always tears down the recording — the calibration step that
            // follows drives its own session and cannot share the device.
            if oldStep == .mic, newStep != .mic {
                viewModel.stopMicTest()
            }
            if newStep == .mic, oldStep != .mic, viewModel.hasMicPermission {
                Task { await viewModel.resumeMicTestIfPermitted() }
            }
        }
        .onDisappear {
            viewModel.stopMicTest()
        }
    }

    // MARK: - Top Bar

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
                .accessibilityLabel("Back")
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 34, height: 34)
            }

            // Ticks read as discrete steps rather than a loading bar — one
            // tick per page, using the app's shared meter primitive. Hidden on
            // the cover so the first screen reads as a cover, not a form.
            //
            // Decorative to VoiceOver on purpose: every non-hero page already
            // announces "Step N of 11" as the first line of its header, so
            // labelling the meter too would read the position twice.
            TickMeter(
                fraction: viewModel.stepProgress,
                color: AppColors.primary,
                tickCount: viewModel.stepCount
            )
            .frame(height: 12)
            .opacity(viewModel.currentStep == .welcome ? 0 : 1)
            .motion(AppMotion.settle, value: viewModel.stepProgress)

            // Skip makes no sense on the cover or the terminal step, and would
            // duplicate the footer action on steps that decline explicitly.
            if !viewModel.currentStep.isHero, !viewModel.currentStep.providesOwnSkip {
                Button("Skip") {
                    viewModel.advance()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, minHeight: 34)
            } else {
                Color.clear.frame(width: 34, height: 34)
            }
        }
        .motion(.easeInOut(duration: 0.25), value: viewModel.currentStep)
    }

    // MARK: - Step Routing

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            OnboardingWelcomeStep(onContinue: viewModel.advance)

        case .howItWorks:
            OnboardingHowItWorksStep(
                counter: viewModel.stepCounterLabel,
                onContinue: viewModel.advance
            )

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
                selectedGoal: viewModel.selectedGoal,
                onSelect: { viewModel.selectGoal($0) },
                onContinue: viewModel.advance
            )

        case .level:
            OnboardingLevelStep(
                counter: viewModel.stepCounterLabel,
                selected: viewModel.speakerLevel,
                onSelect: { viewModel.selectLevel($0, haptic: false) },
                onContinue: viewModel.advance
            )

        case .vocab:
            OnboardingVocabStep(
                counter: viewModel.stepCounterLabel,
                vocabWords: viewModel.vocabWords,
                onAdd: { viewModel.addVocabWord($0) },
                onRemove: { viewModel.removeVocabWord($0) },
                onContinue: viewModel.advance
            )

        case .mic:
            OnboardingMicStep(
                counter: viewModel.stepCounterLabel,
                hasPermission: viewModel.hasMicPermission,
                isRequesting: viewModel.isRequestingMicPermission,
                level: viewModel.micLevel,
                heardVoice: viewModel.hasHeardVoice,
                onEnable: {
                    Task { await viewModel.requestMicAndStartTest() }
                },
                onContinue: viewModel.advance
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
                onSkip: viewModel.advance
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
                    viewModel.advance()
                }
            )

        case .ready:
            OnboardingReadyStep(
                userName: viewModel.trimmedName,
                goal: viewModel.selectedGoal ?? .everydayConfidence,
                level: viewModel.speakerLevel,
                hasCalibratedVoice: viewModel.hasCalibratedVoice,
                launchFirstRecording: $viewModel.launchFirstRecording,
                onFinish: {
                    Haptics.success()
                    onComplete(viewModel.makeResult())
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
}
