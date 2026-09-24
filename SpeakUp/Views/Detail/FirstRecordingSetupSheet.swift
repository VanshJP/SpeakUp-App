import SwiftUI
import SwiftData

/// The handoff that fires on Today once the first score has landed.
///
/// Its job is to set up how sessions run (take length, countdown, weekly goal)
/// and offer the three extras onboarding deliberately withheld until the user
/// had seen a number - then get out of the way. Every row writes through on
/// change and lives on in Settings → Session Defaults, so nothing is pending
/// when the sheet closes.
struct FirstRecordingSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @Query private var userSettings: [UserSettings]

    private var settings: UserSettings? { userSettings.first }

    @State private var reminderEnabled = false
    @State private var isRequestingReminder = false
    @State private var showingCalibration = false
    @State private var showingAISettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                PageScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        section("Your sessions") { sessionCard }
                        section("Optional extras") { optionsCard }
                    }
                    .padding(.top, 28)
                    .pageContentInsets()
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) { footer }
            }
            // No bar on the root: an empty inline bar sat the header under the
            // grabber. `AIModelSettingsView` still gets its own bar when pushed.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingAISettings) {
                AIModelSettingsView()
            }
            .sheet(isPresented: $showingCalibration) {
                NavigationStack {
                    VoiceCalibrationView(onComplete: applyCalibration)
                }
            }
            .onAppear {
                reminderEnabled = settings?.dailyReminderEnabled ?? false
            }
        }
    }

    // MARK: - Header

    /// Type on the canvas rather than a card. A hero card here stacked a plate
    /// on a plate and turned three optional extras into a checklist with a
    /// progress meter, which read as homework standing between the user and
    /// the practice they just proved they could do.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your first score is in")
                .eyebrowStyle()

            Text(greeting)
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Set how your sessions run. Everything here changes later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let name = settings?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Nice work" : "Nice work, \(name)"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .eyebrowStyle()
                .padding(.leading, 4)
            content()
        }
    }

    // MARK: - Session Defaults

    /// The three defaults a new user feels on their very next take. The rest of
    /// Session Defaults (cue sounds, haptics, timer-end behavior) are refinements
    /// nobody has an opinion on after one recording.
    private var sessionCard: some View {
        GlassCard(padding: 4) {
            VStack(spacing: 0) {
                rowShell(
                    icon: "clock",
                    tint: AppColors.primary,
                    title: "Take length",
                    detail: "How long each prompt runs."
                ) {
                    valueMenu(
                        selection: settingBinding(\.defaultDuration, default: 60),
                        options: RecordingDuration.allCases.map { ($0.rawValue, $0.displayName) }
                    )
                }

                rowDivider

                rowShell(
                    icon: "timer",
                    tint: AppColors.categoryAmber,
                    title: "Countdown",
                    detail: "Thinking time before recording starts."
                ) {
                    valueMenu(
                        selection: settingBinding(\.countdownDuration, default: 10),
                        options: CountdownDuration.allCases.map { ($0.rawValue, $0.displayName) }
                    )
                }

                rowDivider

                rowShell(
                    icon: "target",
                    tint: AppColors.success,
                    title: "Weekly goal",
                    detail: "How many sessions a week you are aiming for."
                ) {
                    valueMenu(
                        selection: settingBinding(\.weeklyGoalSessions, default: 5),
                        options: (1...14).map { ($0, "\($0)") }
                    )
                }
            }
        }
    }

    /// Writes straight through to `UserSettings`, the same way the reminder and
    /// calibration rows below do. Today reloads on dismiss to pick up the new
    /// take length and goal.
    private func settingBinding(_ keyPath: ReferenceWritableKeyPath<UserSettings, Int>, default fallback: Int) -> Binding<Int> {
        Binding(
            get: { settings?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard let settings else { return }
                settings[keyPath: keyPath] = value
                try? modelContext.save()
                Haptics.light()
            }
        )
    }

    private func valueMenu(selection: Binding<Int>, options: [(value: Int, label: String)]) -> some View {
        Menu {
            Picker("", selection: selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(options.first { $0.value == selection.wrappedValue }?.label ?? "\(selection.wrappedValue)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassEffect(.regular.interactive(), in: .capsule)
            .frame(minHeight: AppLayout.minHitTarget)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Options

    private var optionsCard: some View {
        GlassCard(padding: 4) {
            VStack(spacing: 0) {
                reminderRow

                rowDivider

                linkRow(
                    icon: "waveform.and.person.filled",
                    tint: AppColors.primary,
                    title: "Calibrate your voice",
                    detail: hasCalibratedVoice
                        ? "Read again any time. Your profile also sharpens itself as you record."
                        : "Twenty seconds of speech makes speaker separation and pace targets yours.",
                    pill: hasCalibratedVoice ? "Saved" : nil
                ) {
                    AnalyticsService.shared.log(.onboardingStep("calibrate", action: "open"))
                    showingCalibration = true
                }

                rowDivider

                linkRow(
                    icon: "sparkle",
                    tint: AppColors.categoryBrandBright,
                    title: "AI coherence feedback",
                    detail: aiBackendLabel == nil
                        ? "Optional. Uses Apple Intelligence, or a model you download."
                        : "Scores how well your points hang together, on top of the usual metrics.",
                    pill: aiBackendLabel
                ) {
                    AnalyticsService.shared.log(.onboardingStep("intelligence", action: "open"))
                    showingAISettings = true
                }
            }
        }
    }

    /// The reminder no longer asks for a time. `PracticeRhythm` learns when this
    /// user practises and `RetentionScheduler` moves the slot to sit half an
    /// hour ahead of it, so a picker here would only be a guess the app
    /// overwrites within the week. See docs/features/retention.md.
    private var reminderDetail: String {
        reminderEnabled
            ? "We watch when you practise and nudge you half an hour before. Change it in Settings."
            : "One nudge a day, timed to when you actually practise. Nothing else."
    }

    /// A stored profile is the only durable signal that calibration happened;
    /// `voiceProfileSampleCount` also climbs on its own as recordings are
    /// analyzed, so it would report "done" for someone who never calibrated.
    private var hasCalibratedVoice: Bool {
        settings?.voiceProfileLastUpdated != nil
    }

    private var aiBackendLabel: String? {
        switch llmService.activeBackend {
        case .appleIntelligence: return "Apple Intelligence"
        case .localLLM: return "On-device model"
        case .none: return nil
        }
    }

    // MARK: - Rows

    /// Shared row shell: glyph, title, one line of detail (plus an optional
    /// "already done" pill), and whatever control belongs on the trailing end.
    private func rowShell<Accessory: View>(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        pill: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            IconChip(icon: icon, tint: tint, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Its own line: beside the title it squeezed "AI coherence
                // feedback" onto two lines and wrapped the pill text too.
                if let pill {
                    StatusPill(text: pill, color: AppColors.success, glyph: .icon("checkmark"))
                        .fixedSize()
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 8)

            accessory()
        }
        .frame(minHeight: AppLayout.minHitTarget)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The switch is the ask, so the row itself is not tappable. `onChange`
    /// lives on the row rather than the control so a programmatic revert after
    /// a denied permission prompt does not re-enter the handler.
    private var reminderRow: some View {
        rowShell(
            icon: "bell.badge",
            tint: AppColors.categoryAmber,
            title: "Daily reminder",
            detail: reminderDetail
        ) {
            if isRequestingReminder {
                VoiceLoader(size: .small).foregroundStyle(.white)
            } else {
                Toggle("Daily reminder", isOn: $reminderEnabled)
                    .labelsHidden()
                    .tint(AppColors.primary)
            }
        }
        .motion(AppMotion.settle, value: reminderEnabled)
        .onChange(of: reminderEnabled) { _, enabled in
            Task { await applyReminderPreference(enabled) }
        }
    }

    private func linkRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        pill: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            rowShell(icon: icon, tint: tint, title: title, detail: detail, pill: pill) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(AppColors.cardStroke)
            .padding(.leading, 54)
    }

    // MARK: - Footer

    /// Pinned, so the exit stays in reach however far the sheet is scrolled.
    /// No material plate behind it - on a short page that was a grey slab
    /// floating over empty canvas.
    /// Labelled with what happens next rather than "Done", because nothing here
    /// is pending a commit.
    private var footer: some View {
        GlassButton(
            title: "Start practicing",
            icon: "arrow.right",
            iconPosition: .right,
            style: .primary,
            size: .large,
            fullWidth: true
        ) {
            Haptics.medium()
            dismiss()
        }
        .padding(.horizontal, AppLayout.pageHorizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func applyReminderPreference(_ enabled: Bool) async {
        let service = NotificationService()

        guard enabled else {
            RetentionScheduler.disable(service: service)
            settings?.dailyReminderEnabled = false
            try? modelContext.save()
            AnalyticsService.shared.log(.onboardingStep("reminder", action: "skip"))
            return
        }

        isRequestingReminder = true
        let granted = await service.requestPermission()
        isRequestingReminder = false
        AnalyticsService.shared.log(.permissionResult(kind: "notifications", granted: granted))
        guard granted else {
            reminderEnabled = false
            return
        }

        settings?.dailyReminderEnabled = true
        settings?.adaptiveReminderEnabled = true
        try? modelContext.save()

        // After the save: the scheduler reads the persisted row, and it is also
        // what picks the hour - the first recording is already on disk, so the
        // very first reminder lands near the time this user just practised.
        await RetentionScheduler.refresh(context: modelContext, service: service)
        AnalyticsService.shared.log(.onboardingStep("reminder", action: "complete"))
        Haptics.success()
    }

    /// Matches `SettingsViewModel.saveCalibrationProfile`: a deliberate "this is
    /// my voice" reading earns full blend trust rather than starting at one
    /// sample, so speaker separation works on the very next conversation.
    private func applyCalibration(_ profile: VoiceProfile) {
        guard let settings else { return }
        settings.voiceProfileF0Hz = profile.f0Hz
        settings.voiceProfileEnergyDb = profile.energyDb
        settings.voiceProfileSampleCount = max(settings.voiceProfileSampleCount, 3)
        settings.voiceProfileLastUpdated = Date()
        try? modelContext.save()
        showingCalibration = false
        AnalyticsService.shared.log(.onboardingStep("calibrate", action: "complete"))
        Haptics.success()
    }
}

// MARK: - Previews

#Preview("First Recording Setup") {
    FirstRecordingSetupSheet()
        .environment(LLMService())
        .modelContainer(for: UserSettings.self, inMemory: true)
}
