import SwiftUI
import SwiftData

/// The deferred tail of onboarding: the three asks the first run deliberately
/// skips (reminder, voice calibration, AI feedback) plus the session defaults,
/// shown once on Today after the first score exists. See `ONBOARDING_VISION.md`
/// invariant 8 for why none of this happens before a score.
///
/// Three things this screen is careful about, each fixing a way the earlier
/// version misled people:
/// - **Every change persists the moment it is made.** Session defaults used to
///   be written only by the "Done" toolbar button, so closing the sheet the way
///   sheets are usually closed — dragging it down — silently discarded them.
/// - **Each row reports its own state.** Calibration and AI feedback are either
///   set up or not. Showing an identical "go do this" row either way leaves the
///   user no way to tell what they already handled.
/// - **Defaults are collapsed behind their summary.** They are preferences, not
///   tasks; three expanded pill grids turned a one-line celebration into a
///   settings export.
struct FirstRecordingSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @Query private var userSettings: [UserSettings]

    private var settings: UserSettings? { userSettings.first }

    @State private var selectedDuration: RecordingDuration = .sixty
    @State private var selectedTimerBehavior: Int = 0
    @State private var countdownSeconds: Int = 10
    @State private var showFullSettings = false
    @State private var showingDefaults = false

    // Deferred onboarding steps, offered here instead of before the first score.
    @State private var reminderEnabled = false
    @State private var reminderTime = Date()
    @State private var isRequestingReminder = false
    @State private var showingCalibration = false
    @State private var showingAISettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                ScrollView {
                    VStack(spacing: 18) {
                        headerSection
                        finishSetupSection
                        sessionDefaultsSection
                        fullSettingsButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) { footer }
            }
            // No title and no toolbar Done: the header card names the screen,
            // and the one way forward is the pinned button, which is also the
            // only control on screen that isn't already saved.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showFullSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $showingAISettings) {
                AIModelSettingsView()
            }
            .sheet(isPresented: $showingCalibration) {
                NavigationStack {
                    VoiceCalibrationView { profile in
                        applyCalibration(profile)
                    }
                }
            }
            .onAppear(perform: loadCurrentSettings)
        }
    }

    // MARK: - Footer

    /// Pinned, so the exit stays in reach however far the sheet is scrolled.
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
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerSection: some View {
        FeaturedGlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColors.primary, AppColors.categoryBrandBright],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your first score is in")
                            .eyebrowStyle()
                        Text("Nice work")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }

                    Spacer(minLength: 0)
                }

                Text("Three optional extras sharpen the coaching. Set up what you want, skip the rest.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                setupProgress
            }
        }
    }

    /// Turns three unrelated asks into one visible count. Without it the rows
    /// read as an open-ended to-do list, which is how a screen nobody has to
    /// finish starts feeling like a chore.
    private var setupProgress: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(completedSetupSteps == Self.setupStepCount
                     ? "All three set up"
                     : "\(completedSetupSteps) of \(Self.setupStepCount) set up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer(minLength: 0)

                if completedSetupSteps == Self.setupStepCount {
                    StatusPill(text: "Done", color: AppColors.success, glyph: .icon("checkmark"))
                }
            }

            TickMeter(
                fraction: Double(completedSetupSteps) / Double(Self.setupStepCount),
                color: AppColors.primary,
                tickCount: Self.setupStepCount
            )
            .frame(height: 9)
        }
        .motion(AppMotion.settle, value: completedSetupSteps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completedSetupSteps) of \(Self.setupStepCount) extras set up")
    }

    // MARK: - Setup State

    private static let setupStepCount = 3

    /// A stored profile is the only durable signal that calibration happened;
    /// `voiceProfileSampleCount` also climbs on its own as recordings are
    /// analyzed, so it would report "done" for someone who never calibrated.
    private var hasCalibratedVoice: Bool {
        settings?.voiceProfileLastUpdated != nil
    }

    /// Nil when no backend can generate — the row's "not set up" state.
    private var aiBackendLabel: String? {
        switch llmService.activeBackend {
        case .appleIntelligence: return "Apple Intelligence"
        case .localLLM: return "On-device model"
        case .none: return nil
        }
    }

    private var completedSetupSteps: Int {
        [reminderEnabled, hasCalibratedVoice, aiBackendLabel != nil]
            .filter { $0 }
            .count
    }

    // MARK: - Deferred Setup

    /// The three steps onboarding no longer asks for up front. They land here,
    /// after the app has produced a score, where a reminder or a model download
    /// is a decision about something the user has actually seen work.
    private var finishSetupSection: some View {
        VStack(spacing: 10) {
            GlassSectionHeader("Make it yours", icon: "sparkles")

            // Card padding drops to 4 so each row owns its own hit area and can
            // reach the card's edges — a 44pt row inset by card padding reads as
            // a cramped label rather than a control.
            GlassCard(padding: 4) {
                VStack(spacing: 0) {
                    reminderRow

                    rowDivider

                    setupRow(
                        icon: "waveform.and.person.filled",
                        tint: AppColors.primary,
                        title: "Calibrate your voice",
                        detail: hasCalibratedVoice
                            ? "Read again any time. Your profile also sharpens itself as you record."
                            : "20 seconds of speech makes speaker separation and pace targets yours.",
                        status: hasCalibratedVoice ? .done("Saved") : .todo,
                        action: {
                            AnalyticsService.shared.log(.onboardingStep("calibrate", action: "open"))
                            showingCalibration = true
                        }
                    )

                    rowDivider

                    setupRow(
                        icon: "sparkle",
                        tint: AppColors.categoryBrandBright,
                        title: "AI coherence feedback",
                        detail: aiBackendLabel == nil
                            ? "Optional. Uses Apple Intelligence, or a model you download."
                            : "Scores how well your points hang together, on top of the usual metrics.",
                        status: aiBackendLabel.map { RowStatus.done($0) } ?? .todo,
                        action: {
                            AnalyticsService.shared.log(.onboardingStep("intelligence", action: "open"))
                            showingAISettings = true
                        }
                    )
                }
            }
        }
    }

    /// The toggle owns the ask; the time row only exists once there is something
    /// to schedule. `onChange` lives on the row rather than the controls so a
    /// programmatic revert (permission denied) doesn't re-enter the handler.
    private var reminderRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                OnboardingGlyph(icon: "bell.badge", tint: AppColors.categoryAmber, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily reminder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(reminderEnabled
                         ? "One nudge a day. Nothing else."
                         : "A nudge at the time you pick. Nothing else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isRequestingReminder {
                    ProgressView()
                        .tint(.white)
                } else {
                    Toggle("Daily reminder", isOn: $reminderEnabled)
                        .labelsHidden()
                        .tint(AppColors.primary)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if reminderEnabled {
                HStack(spacing: 8) {
                    Text("Remind me at")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    DatePicker(
                        "Reminder time",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .motion(AppMotion.settle, value: reminderEnabled)
        .onChange(of: reminderEnabled) { _, enabled in
            Task { await applyReminderPreference(enabled) }
        }
        .onChange(of: reminderTime) { _, _ in
            guard reminderEnabled else { return }
            Task { await applyReminderPreference(true) }
        }
    }

    /// Whether a row still asks for something, or already reports a result.
    private enum RowStatus {
        case todo
        case done(String)
    }

    private func setupRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        status: RowStatus,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 12) {
                OnboardingGlyph(icon: icon, tint: tint, size: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if case .done(let label) = status {
                            StatusPill(text: label, color: AppColors.success, glyph: .icon("checkmark"))
                        }
                    }

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Inset past the glyph column so the rows read as one list.
    private var rowDivider: some View {
        Divider()
            .overlay(AppColors.cardStroke)
            .padding(.leading, 54)
    }

    /// Requests notification permission only at the moment the user asks for a
    /// reminder, and reverts the switch if they decline. The switch is swapped
    /// for a spinner while the system prompt is up, so the row doesn't sit in a
    /// state the user didn't get to choose yet.
    private func applyReminderPreference(_ enabled: Bool) async {
        let service = NotificationService()

        guard enabled else {
            await service.cancelDailyReminder()
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

        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let hour = comps.hour ?? 9
        let minute = comps.minute ?? 0
        await service.scheduleDailyReminder(hour: hour, minute: minute)

        settings?.dailyReminderEnabled = true
        settings?.dailyReminderHour = hour
        settings?.dailyReminderMinute = minute
        try? modelContext.save()
        AnalyticsService.shared.log(.onboardingStep("reminder", action: "complete"))
        Haptics.success()
    }

    // MARK: - Session Defaults

    /// Preferences, not tasks — so they arrive as one line the user can read and
    /// ignore. Expanded by default they were the tallest thing on a screen whose
    /// job is to celebrate a first score.
    private var sessionDefaultsSection: some View {
        VStack(spacing: 10) {
            GlassSectionHeader("Session defaults", icon: "slider.horizontal.3")

            GlassCard(padding: 4) {
                VStack(spacing: 0) {
                    Button {
                        Haptics.light()
                        showingDefaults.toggle()
                    } label: {
                        HStack(spacing: 12) {
                            OnboardingGlyph(icon: "record.circle", tint: AppColors.primary, size: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("What the record button does")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(defaultsSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showingDefaults ? 180 : 0))
                        }
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Session defaults. \(defaultsSummary)")
                    .accessibilityHint(showingDefaults ? "Hides the options" : "Shows the options")
                    .accessibilityAddTraits(.isButton)

                    if showingDefaults {
                        VStack(spacing: 14) {
                            rowDivider
                            durationPicker
                            timerBehaviorPicker
                            countdownPicker
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                    }
                }
            }
        }
        .motion(AppMotion.settle, value: showingDefaults)
    }

    /// The collapsed state has to say everything the expanded state would, or
    /// collapsing it is just hiding settings.
    private var defaultsSummary: String {
        let behavior = TimerEndBehavior(rawValue: selectedTimerBehavior)?.displayName ?? "Save & Stop"
        return "\(selectedDuration.displayName) · \(behavior) · \(countdownSeconds)s countdown"
    }

    private var durationPicker: some View {
        pickerGroup(title: "Session length", icon: "clock") {
            // Seven options do not fit one row on any iPhone width — a flexible
            // grid wraps them instead of forcing the whole sheet wider than the
            // screen, which is what made this page scroll sideways.
            LazyVGrid(columns: durationColumns, spacing: 8) {
                ForEach(RecordingDuration.allCases) { duration in
                    selectionTile(
                        text: duration.displayName,
                        isSelected: selectedDuration == duration
                    ) {
                        Haptics.light()
                        selectedDuration = duration
                        persistDefaults()
                    }
                }
            }
        }
    }

    private var timerBehaviorPicker: some View {
        pickerGroup(title: "When the timer ends", icon: "timer") {
            HStack(spacing: 8) {
                timerBehaviorOption(title: "Save & Stop", icon: "stop.circle", value: 0)
                timerBehaviorOption(title: "Keep Going", icon: "play.circle", value: 1)
            }
        }
    }

    private var countdownPicker: some View {
        pickerGroup(title: "Countdown before recording", icon: "hourglass") {
            HStack(spacing: 8) {
                ForEach([3, 5, 10, 15], id: \.self) { seconds in
                    selectionTile(
                        text: "\(seconds)s",
                        isSelected: countdownSeconds == seconds
                    ) {
                        Haptics.light()
                        countdownSeconds = seconds
                        persistDefaults()
                    }
                }
            }
        }
    }

    private func pickerGroup<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    }

    private func timerBehaviorOption(title: String, icon: String, value: Int) -> some View {
        Button {
            Haptics.light()
            selectedTimerBehavior = value
            persistDefaults()
        } label: {
            let isSelected = selectedTimerBehavior == value
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppColors.primary.opacity(0.5) : .clear)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppColors.primary.opacity(0.6) : .white.opacity(0.08), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func selectionTile(text: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? AppColors.primary.opacity(0.5) : .clear)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? AppColors.primary.opacity(0.6) : .white.opacity(0.08), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
    }

    private var fullSettingsButton: some View {
        GlassButton(
            title: "All settings",
            icon: "gearshape",
            style: .secondary,
            size: .small,
            fullWidth: true
        ) {
            Haptics.light()
            showFullSettings = true
        }
        .padding(.top, 2)
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

    // MARK: - Load / Save

    private func loadCurrentSettings() {
        guard let settings else { return }
        selectedDuration = RecordingDuration(rawValue: settings.defaultDuration) ?? .sixty
        selectedTimerBehavior = settings.timerEndBehavior
        countdownSeconds = settings.countdownDuration
        reminderEnabled = settings.dailyReminderEnabled
        reminderTime = Calendar.current.date(
            bySettingHour: settings.dailyReminderHour,
            minute: settings.dailyReminderMinute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    /// Written on every tap rather than on dismissal. A sheet with a drag
    /// indicator gets closed by dragging it, and the old save-on-Done path threw
    /// the user's picks away every time they did that.
    private func persistDefaults() {
        guard let settings else { return }
        settings.defaultDuration = selectedDuration.rawValue
        settings.timerEndBehavior = selectedTimerBehavior
        settings.countdownDuration = countdownSeconds
        try? modelContext.save()
    }
}

// MARK: - Previews

#Preview("First Recording Setup") {
    FirstRecordingSetupSheet()
        .environment(LLMService())
        .modelContainer(for: UserSettings.self, inMemory: true)
}
