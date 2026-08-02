import SwiftUI

// MARK: - Microphone

struct OnboardingMicStep: View {
    let counter: String?
    let hasPermission: Bool
    let isRequesting: Bool
    let level: Float
    let heardVoice: Bool
    let onEnable: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: hasPermission ? "Say something" : "Let's hear your voice",
            subtitle: subtitle,
            icon: "mic.fill"
        ) {
            GlassCard(tint: hasPermission ? AppColors.glassTintPrimary : nil, padding: 16) {
                VStack(spacing: 14) {
                    OnboardingWaveform(level: hasPermission ? level : 0)
                        .frame(height: 104)
                        .opacity(hasPermission ? 1 : 0.3)

                    if heardVoice {
                        StatusPill(
                            text: "Mic is working",
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
            }

            GlassCard(padding: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    OnboardingBullet(
                        icon: "mic",
                        text: "Microphone access records your practice sessions."
                    )
                    OnboardingBullet(
                        icon: "text.quote",
                        text: "Speech recognition is the backup transcriber when the on-device model is still loading."
                    )
                    OnboardingBullet(
                        icon: "lock.fill",
                        text: "Audio never leaves your iPhone, and recording only runs while you are on a session screen.",
                        tint: AppColors.success
                    )
                }
            }
        } footer: {
            if hasPermission {
                OnboardingCTA(title: "Continue", action: onContinue)
            } else {
                OnboardingCTA(
                    title: isRequesting ? "Asking…" : "Allow microphone",
                    icon: isRequesting ? nil : "arrow.right",
                    isLoading: isRequesting,
                    action: onEnable
                )
            }
        }
    }

    private var subtitle: String {
        if !hasPermission {
            return "Big Talk needs the microphone to record, and speech recognition as a transcription fallback. Both are used only while you practice."
        }
        if heardVoice {
            return "That's the level we'll be scoring. Keep talking or continue."
        }
        return "Try saying: \"Hi, I'm getting started with Big Talk.\""
    }
}

/// Live input meter. Centre bars react hardest so the shape reads as a voice
/// rather than a level bar.
struct OnboardingWaveform: View {
    let level: Float
    private let barCount = 28

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    BarView(index: index, total: barCount, level: level, geoHeight: geo.size.height)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private struct BarView: View {
        let index: Int
        let total: Int
        let level: Float
        let geoHeight: CGFloat
        @State private var phase: Double = 0

        var body: some View {
            let position = Double(index) / Double(total - 1)
            // Distance from middle (0 at center, 1 at edges).
            let distance = abs(position - 0.5) * 2
            let centerWeight = 1 - distance * 0.7
            let noise = (sin(phase + Double(index) * 0.4) + 1) / 2
            let amplitude = max(0.05, Double(level)) * centerWeight * (0.6 + noise * 0.6)
            let height = max(5, CGFloat(amplitude) * geoHeight)
            return Capsule()
                .fill(AppColors.primary)
                .frame(height: height)
                .frame(maxHeight: .infinity, alignment: .center)
                .ambientLoop(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                    phase = .pi * 2
                }
        }
    }
}

// MARK: - Voice Calibration

/// Captures a baseline pitch/energy signature. Optional — the profile is also
/// learned automatically from quality-gated recordings — but doing it once up
/// front means speaker separation works on the very first conversation.
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
                : "Read a short passage out loud. It takes about 30 seconds and only has to happen once.",
            icon: hasCalibrated ? "checkmark.seal.fill" : "waveform.badge.person.crop",
            iconTint: hasCalibrated ? AppColors.success : AppColors.primary
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

            GlassCard(padding: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    OnboardingBullet(
                        icon: "waveform",
                        text: "Measures the pitch and energy that make your voice yours."
                    )
                    OnboardingBullet(
                        icon: "person.2.fill",
                        text: "Lets Big Talk score you — not the other people in the room — when a session picks up a conversation."
                    )
                    OnboardingBullet(
                        icon: "arrow.trianglehead.2.clockwise",
                        text: "Keeps sharpening itself from every recording you make afterwards."
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
                OnboardingTextButton(title: "Skip — learn it as I record", action: onSkip)
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
                : "This iPhone doesn't have Apple Intelligence. You can download a small language model instead — it runs entirely offline.",
            icon: "sparkles",
            iconTint: appleIntelligenceAvailable ? AppColors.success : AppColors.primary
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
                        text: "Everything else — transcription, scoring, drills — works without any of this.",
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

                Text("Keep going — the download continues in the background.")
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
            Text("Optional. Skip it and Big Talk still transcribes, scores, and coaches you with its built-in analysis.")
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
            subtitle: "Speaking improves with reps, not marathons. One nudge a day is usually enough.",
            icon: "bell.badge.fill"
        ) {
            if hasPermission {
                GlassCard(padding: 14) {
                    Toggle(isOn: $reminderEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily practice nudge")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("We'll also warn you when a streak is about to lapse.")
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
                        OnboardingBullet(icon: "flame.fill", text: "A heads-up when your streak is about to break.", tint: AppColors.warning)
                        OnboardingBullet(icon: "bell.slash", text: "Nothing else. Turn it off any time in Settings.")
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
    }
}

// MARK: - Ready

struct OnboardingReadyStep: View {
    @Environment(LLMService.self) private var llmService

    let userName: String
    let goal: OnboardingGoal
    let level: SpeakerLevel
    let hasCalibratedVoice: Bool
    @Binding var launchFirstRecording: Bool
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    OnboardingOrb(size: 150)
                        .padding(.top, 10)

                    VStack(spacing: 8) {
                        Text(headline)
                            .font(.title.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Here's your setup. Your first recording is the baseline every later session gets compared against.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 8)

                    GlassCard(padding: 14) {
                        VStack(spacing: 10) {
                            OnboardingSummaryRow(
                                icon: goal.icon,
                                label: "Focus",
                                value: goal.displayName,
                                tint: goal.color
                            )
                            Divider().overlay(AppColors.cardStroke)
                            OnboardingSummaryRow(
                                icon: level.icon,
                                label: "Level",
                                value: level.displayName,
                                tint: level.color
                            )
                            Divider().overlay(AppColors.cardStroke)
                            OnboardingSummaryRow(
                                icon: "waveform.badge.person.crop",
                                label: "Voice profile",
                                value: hasCalibratedVoice ? "Calibrated" : "Learns as you record",
                                tint: hasCalibratedVoice ? AppColors.success : AppColors.accent
                            )
                            Divider().overlay(AppColors.cardStroke)
                            OnboardingSummaryRow(
                                icon: "sparkles",
                                label: "AI coaching",
                                value: aiSummary,
                                tint: llmService.isAvailable ? AppColors.success : AppColors.accent
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            VStack(spacing: 12) {
                Toggle(isOn: $launchFirstRecording) {
                    Text("Start a 60-second session right now")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .tint(AppColors.primary)

                OnboardingCTA(
                    title: launchFirstRecording ? "Start first recording" : "Take me in",
                    icon: launchFirstRecording ? "mic.fill" : "checkmark",
                    action: onFinish
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var headline: String {
        userName.isEmpty ? "You're all set" : "Let's go, \(userName)"
    }

    private var aiSummary: String {
        switch llmService.activeBackend {
        case .appleIntelligence: return "Apple Intelligence"
        case .localLLM: return llmService.localLLM.modelDisplayName
        case .none:
            if case .downloading = llmService.localLLM.modelState { return "Downloading" }
            return "Built-in analysis"
        }
    }
}
