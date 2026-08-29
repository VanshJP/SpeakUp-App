import SwiftUI

// MARK: - Microphone

struct OnboardingMicStep: View {
    let counter: String?
    let viewModel: OnboardingViewModel
    let onContinue: () -> Void

    private var hasPermission: Bool { viewModel.hasMicPermission }
    private var isRequesting: Bool { viewModel.isRequestingMicPermission }
    private var heardVoice: Bool { viewModel.hasHeardVoice }

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: hasPermission ? "Sound check" : "Let's make sure we can hear you",
            subtitle: subtitle
        ) {
            GlassCard(tint: hasPermission ? AppColors.glassTintPrimary : nil, padding: 16) {
                VStack(spacing: 14) {
                    // Isolated so the 16 Hz meter only redraws the bars, not
                    // this card, its copy, or the page's footer button.
                    LiveMicWaveform(viewModel: viewModel, isLive: hasPermission)
                        .frame(height: 104)
                        .opacity(hasPermission ? 1 : 0.3)

                    if heardVoice {
                        StatusPill(
                            text: "Loud and clear",
                            color: AppColors.success,
                            glyph: .icon("checkmark")
                        )
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Text(hasPermission ? "Listening…" : "Microphone off")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .motion(AppMotion.settle, value: heardVoice)
            }
        } footer: {
            if hasPermission {
                OnboardingCTA(title: "I'm ready", action: onContinue)
            } else {
                OnboardingCTA(
                    title: isRequesting ? "Asking…" : "Allow microphone",
                    icon: isRequesting ? nil : "arrow.right",
                    isLoading: isRequesting,
                    action: { Task { await viewModel.requestMicAndStartTest() } }
                )
            }
        }
        // Granting permission rewrites the title, subtitle, card tint and CTA
        // at once. Without this the whole page snaps between two layouts.
        .motion(AppMotion.settle, value: hasPermission)
    }

    /// "Sound check" is the load-bearing reframe: roadies do sound checks;
    /// nobody judges a sound check. Nothing here is kept or scored, and the
    /// copy never asks the user to perform.
    private var subtitle: String {
        if !hasPermission {
            return "Big Talk listens only while you're recording. Audio stays on this iPhone."
        }
        if heardVoice {
            return "Mic looks good. Nothing is saved until you press record."
        }
        return "Say anything. Try \"testing, one two three.\""
    }
}

/// The only view that reads `micLevel`, so the ~16 Hz meter updates stop here
/// instead of invalidating the whole mic page.
private struct LiveMicWaveform: View {
    let viewModel: OnboardingViewModel
    let isLive: Bool

    var body: some View {
        OnboardingWaveform(level: isLive ? viewModel.micLevel : 0)
    }
}

/// Live input meter. Centre bars react hardest so the shape reads as a voice
/// rather than a level bar.
///
/// Drawn as one `Canvas` on a `TimelineView` clock. It used to be 28 sibling
/// views, each holding its own `@State` phase on a `repeatForever` animation:
/// 28 view bodies re-evaluating every frame for what is a single picture.
struct OnboardingWaveform: View {
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 28
    private let spacing: CGFloat = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
                // Matches the old 0→2π-per-0.6s linear loop.
                let phase = context.date.timeIntervalSinceReferenceDate * (2 * Double.pi / 0.6)
                let barWidth = max(1, (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))

                for index in 0..<barCount {
                    let position = Double(index) / Double(barCount - 1)
                    // Distance from middle (0 at center, 1 at edges).
                    let distance = abs(position - 0.5) * 2
                    let centerWeight = 1 - distance * 0.7
                    let noise = (sin(phase + Double(index) * 0.4) + 1) / 2
                    let amplitude = max(0.05, Double(level)) * centerWeight * (0.6 + noise * 0.6)
                    let height = max(5, CGFloat(amplitude) * size.height)
                    let rect = CGRect(
                        x: CGFloat(index) * (barWidth + spacing),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(AppColors.primary))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Voice Calibration

/// Captures a baseline pitch/energy signature. Optional, since the profile is
/// also learned automatically from quality-gated recordings, but doing it once
/// up front means speaker separation works on the very first conversation.
struct OnboardingCalibrationStep: View {
    let counter: String?
    let hasMicPermission: Bool
    let isRequestingMic: Bool
    let hasCalibrated: Bool
    let onRequestMic: () -> Void
    let onCalibrate: () -> Void
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: hasCalibrated ? "Voice profile saved" : "Teach Big Talk your voice",
            subtitle: hasCalibrated
                ? "You can recalibrate any time from Settings → Data Management."
                : "Read a short passage out loud. It takes about 30 seconds and only has to happen once."
        ) {
            if hasCalibrated {
                GlassCard(tint: AppColors.glassTintSuccess, padding: 14) {
                    HStack(spacing: 12) {
                        OnboardingGlyph(icon: "person.wave.2.fill", tint: AppColors.success, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Baseline captured")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Your pitch and vocal energy are on file.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        StatusPill(text: "Ready", color: AppColors.success, glyph: .dot)
                    }
                }
            }

            // One line each. These were full sentences that each wrapped to
            // two lines, so three bullets read as a six-line paragraph with
            // icons in it rather than three separate facts.
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingBullet(
                        icon: "waveform",
                        text: "Learns the pitch and energy of your voice."
                    )
                    OnboardingBullet(
                        icon: "person.2.fill",
                        text: "Scores you, not whoever else is in the room."
                    )
                    OnboardingBullet(
                        icon: "arrow.trianglehead.2.clockwise",
                        text: "Sharpens itself with every recording after this."
                    )
                }
            }

            if !hasMicPermission {
                GlassCard(padding: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                        Text("Calibration needs microphone access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            if hasCalibrated {
                OnboardingCTA(title: "Continue", action: onContinue)
            } else if hasMicPermission {
                OnboardingCTA(title: "Start calibration", icon: "mic.fill", action: onCalibrate)
                OnboardingTextButton(title: "Skip and learn it as I record", action: onSkip)
            } else {
                OnboardingCTA(
                    title: isRequestingMic ? "Asking…" : "Allow microphone",
                    icon: isRequestingMic ? nil : "arrow.right",
                    isLoading: isRequestingMic,
                    action: onRequestMic
                )
                OnboardingTextButton(title: "Skip for now", action: onSkip)
            }
        }
        // The sheet dismisses and this page flips to its saved state behind it.
        .motion(AppMotion.settle, value: hasCalibrated)
        .motion(AppMotion.settle, value: hasMicPermission)
    }
}

// MARK: - AI Features

/// Surfaces which AI backend the device can use and, on devices without Apple
/// Intelligence, offers the on-device model download up front instead of
/// leaving the feature silently switched off.
struct OnboardingIntelligenceStep: View {
    @Environment(LLMService.self) private var llmService

    let counter: String?
    let onContinue: () -> Void

    private var localState: LocalModelState { llmService.localLLM.modelState }

    private var appleIntelligenceAvailable: Bool { llmService.appleIntelligenceAvailable }

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: appleIntelligenceAvailable ? "AI coaching is ready" : "Add AI coaching",
            subtitle: appleIntelligenceAvailable
                ? "This iPhone has Apple Intelligence, so the smarter half of your feedback is already switched on."
                : "This iPhone doesn't have Apple Intelligence. You can download a small language model instead. It runs entirely offline."
        ) {
            backendCard

            if !appleIntelligenceAvailable {
                localModelCard
            }

            GlassCard(tint: AppColors.glassTintPrimary, padding: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("What it adds")
                        .eyebrowStyle()
                    OnboardingBullet(
                        icon: "brain",
                        text: "Coherence scoring that reads meaning, not just keyword overlap."
                    )
                    OnboardingBullet(
                        icon: "text.bubble",
                        text: "Coaching tips written against your own transcript and metrics."
                    )
                    OnboardingBullet(
                        icon: "wand.and.stars",
                        text: "Clean-up and tagging when you dictate a story or script."
                    )
                    OnboardingBullet(
                        icon: "checkmark.circle",
                        text: "Everything else (transcription, scoring, drills) works without any of this.",
                        tint: AppColors.success
                    )
                }
            }

            if appleIntelligenceAvailable {
                Text("Prefer a downloadable model instead? Settings → AI Features has the full list.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        } footer: {
            if appleIntelligenceAvailable {
                OnboardingCTA(title: "Continue", action: onContinue)
            } else {
                switch localState {
                case .notDownloaded, .error:
                    OnboardingCTA(
                        title: "Download \(llmService.localLLM.approximateModelSize)",
                        icon: "arrow.down.circle",
                        action: startDownload
                    )
                    OnboardingTextButton(title: "Not now", action: onContinue)
                case .downloading:
                    OnboardingCTA(title: "Continue while it downloads", action: onContinue)
                case .downloaded, .loading, .ready:
                    OnboardingCTA(title: "Continue", action: onContinue)
                }
            }
        }
    }

    // MARK: - Subviews

    private var backendCard: some View {
        GlassCard(
            tint: appleIntelligenceAvailable ? AppColors.glassTintSuccess : nil,
            padding: 14
        ) {
            HStack(spacing: 12) {
                OnboardingGlyph(
                    icon: "cpu",
                    tint: appleIntelligenceAvailable ? AppColors.success : AppColors.accent,
                    size: 38
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(appleIntelligenceAvailable
                         ? "Built into this device. Nothing to download."
                         : "Needs iPhone 15 Pro or newer with Apple Intelligence enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                StatusPill(
                    text: appleIntelligenceAvailable ? "Active" : "Unavailable",
                    color: appleIntelligenceAvailable ? AppColors.success : AppColors.accent,
                    glyph: .dot
                )
            }
        }
    }

    private var localModelCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    OnboardingGlyph(icon: "arrow.down.circle", tint: AppColors.primary, size: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(llmService.localLLM.modelDisplayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("\(llmService.localLLM.approximateModelSize) • Wi-Fi only • runs offline after install")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    localStatusPill
                }

                localStateDetail
            }
        }
    }

    @ViewBuilder
    private var localStateDetail: some View {
        switch localState {
        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(AppColors.primary)

                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        llmService.localLLM.cancelDownload()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.error)
                }

                Text("Keep going. The download continues in the background.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .loading:
            HStack(spacing: 10) {
                ProgressView().tint(AppColors.primary)
                Text("Loading model into memory…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .downloaded:
            GlassButton(title: "Load model", icon: "play.fill", style: .secondary, size: .small, fullWidth: true) {
                Haptics.medium()
                Task { await llmService.localLLM.loadModel() }
            }

        case .ready:
            Text("Loaded and ready. AI coaching is on.")
                .font(.caption)
                .foregroundStyle(AppColors.success)

        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppColors.error)
                    .fixedSize(horizontal: false, vertical: true)

                GlassButton(title: "Retry", icon: "arrow.clockwise", style: .secondary, size: .small, fullWidth: true) {
                    startDownload()
                }
            }

        case .notDownloaded:
            Text("Optional. Big Talk still transcribes, scores, and coaches you without it. This is the size we picked for your device's memory; Settings → AI Features has smaller and larger options.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var localStatusPill: some View {
        switch localState {
        case .ready:
            StatusPill(text: "Ready", color: AppColors.success, glyph: .dot)
        case .loading:
            StatusPill(text: "Loading", color: AppColors.info, glyph: .dot)
        case .downloading:
            StatusPill(text: "Downloading", color: AppColors.info, glyph: .dot)
        case .downloaded:
            StatusPill(text: "Installed", color: AppColors.primary, glyph: .dot)
        case .error:
            StatusPill(text: "Failed", color: AppColors.error, glyph: .dot)
        case .notDownloaded:
            StatusPill(text: "Optional", color: AppColors.accent, glyph: .dot)
        }
    }

    private func startDownload() {
        Haptics.medium()
        Task { await llmService.setupLocalModel() }
    }
}

// MARK: - Reminder

struct OnboardingReminderStep: View {
    let counter: String?
    let hasPermission: Bool
    let isRequesting: Bool
    @Binding var reminderEnabled: Bool
    @Binding var reminderTime: Date
    let onEnable: () -> Void
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: "Build the habit",
            subtitle: "Speaking improves with reps, not marathons. One nudge a day is usually enough."
        ) {
            if hasPermission {
                GlassCard(padding: 14) {
                    Toggle(isOn: $reminderEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily practice nudge")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("One reminder at the time you choose. Nothing else.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(AppColors.primary)
                }

                GlassCard(padding: 4) {
                    // The wheel needs ~200pt to render its three rolling rows
                    // without clipping; a shorter frame also shadows the centre
                    // row's hit region so taps land off-target.
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                }
                .opacity(reminderEnabled ? 1 : 0.4)
                .disabled(!reminderEnabled)
            } else {
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 9) {
                        OnboardingBullet(icon: "clock", text: "One reminder a day, at a time you choose.")
                        OnboardingBullet(icon: "bell.slash", text: "No streak warnings or surprise nudges.")
                        OnboardingBullet(icon: "gearshape", text: "Change it or turn it off any time in Settings.")
                    }
                }
            }
        } footer: {
            if hasPermission {
                OnboardingCTA(title: "Looks good", action: onContinue)
                OnboardingTextButton(title: "No thanks", action: onSkip)
            } else {
                OnboardingCTA(
                    title: isRequesting ? "Asking…" : "Turn on reminders",
                    icon: isRequesting ? nil : "arrow.right",
                    isLoading: isRequesting,
                    action: onEnable
                )
                OnboardingTextButton(title: "Continue without reminders", action: onContinue)
            }
        }
        .motion(AppMotion.settle, value: reminderEnabled)
        .motion(AppMotion.settle, value: hasPermission)
    }
}

// The ready-step recap that used to live here is gone with the baseline
// moving inside onboarding: the flow no longer needs a receipt or a
// start-recording decision — the reveal in `OnboardingBaselineSteps` is the
// terminal screen.
