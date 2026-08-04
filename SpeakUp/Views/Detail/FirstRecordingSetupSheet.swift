import SwiftUI
import SwiftData

struct FirstRecordingSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    private var settings: UserSettings? { userSettings.first }

    @State private var selectedDuration: RecordingDuration = .sixty
    @State private var selectedTimerBehavior: Int = 0
    @State private var countdownSeconds: Int = 10
    @State private var showFullSettings = false

    // Deferred onboarding steps, offered here instead of before the first score.
    @State private var reminderEnabled = false
    @State private var reminderTime = Date()
    @State private var showingCalibration = false
    @State private var showingAISettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        finishSetupSection
                        quickSettingsSection
                        fullSettingsButton
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Welcome!")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                }
            }
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
            .onAppear {
                if let settings {
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
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        FeaturedGlassCard(padding: 20) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.primary, AppColors.categoryBrandBright],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Great first recording!")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text("Now that you have seen a score, here are the optional extras — and your session defaults.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Deferred Setup

    /// The three steps onboarding no longer asks for up front. They land here,
    /// after the app has produced a score, where a reminder or a model download
    /// is a decision about something the user has actually seen work.
    private var finishSetupSection: some View {
        VStack(spacing: 14) {
            GlassSectionHeader("Finish Setting Up", icon: "sparkles")

            GlassCard {
                VStack(spacing: 16) {
                    reminderRow

                    Divider().overlay(Color.white.opacity(0.06))

                    deferredRow(
                        icon: "waveform.and.person.filled",
                        title: "Calibrate your voice",
                        detail: "20 seconds of speech makes speaker separation and pace targets yours.",
                        action: { showingCalibration = true }
                    )

                    Divider().overlay(Color.white.opacity(0.06))

                    deferredRow(
                        icon: "cpu",
                        title: "AI coherence feedback",
                        detail: "Optional. Uses Apple Intelligence, or a model you download.",
                        action: { showingAISettings = true }
                    )
                }
            }
        }
    }

    private var reminderRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.categoryAmber)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily reminder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("A nudge at the time you pick. Nothing else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: $reminderEnabled)
                    .labelsHidden()
                    .tint(AppColors.primary)
                    .onChange(of: reminderEnabled) { _, enabled in
                        Task { await applyReminderPreference(enabled) }
                    }
            }

            if reminderEnabled {
                DatePicker(
                    "Reminder time",
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .onChange(of: reminderTime) { _, _ in
                    Task { await applyReminderPreference(true) }
                }
            }
        }
    }

    private func deferredRow(
        icon: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(GlassPressStyle())
    }

    /// Requests notification permission only at the moment the user asks for a
    /// reminder, and reverts the switch if they decline.
    private func applyReminderPreference(_ enabled: Bool) async {
        let service = NotificationService()

        guard enabled else {
            await service.cancelDailyReminder()
            settings?.dailyReminderEnabled = false
            try? modelContext.save()
            return
        }

        let granted = await service.requestPermission()
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
        Haptics.success()
    }

    private var quickSettingsSection: some View {
        VStack(spacing: 14) {
            GlassSectionHeader("Quick Setup", icon: "slider.horizontal.3")

            GlassCard {
                VStack(spacing: 16) {
                    // Default Duration
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Default Duration", systemImage: "clock")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            ForEach(RecordingDuration.allCases) { duration in
                                selectionTile(
                                    text: duration.displayName,
                                    isSelected: selectedDuration == duration
                                ) {
                                    Haptics.light()
                                    selectedDuration = duration
                                }
                            }
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.06))

                    // Timer End Behavior
                    VStack(alignment: .leading, spacing: 8) {
                        Label("When Timer Ends", systemImage: "timer")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            timerBehaviorOption(
                                title: "Save & Stop",
                                icon: "stop.circle",
                                value: 0
                            )
                            timerBehaviorOption(
                                title: "Keep Going",
                                icon: "play.circle",
                                value: 1
                            )
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.06))

                    // Countdown Duration
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Countdown: \(countdownSeconds)s", systemImage: "hourglass")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            ForEach([3, 5, 10, 15], id: \.self) { seconds in
                                selectionTile(
                                    text: "\(seconds)s",
                                    isSelected: countdownSeconds == seconds
                                ) {
                                    Haptics.light()
                                    countdownSeconds = seconds
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func timerBehaviorOption(title: String, icon: String, value: Int) -> some View {
        Button {
            Haptics.light()
            selectedTimerBehavior = value
        } label: {
            let isSelected = selectedTimerBehavior == value
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.subheadline.weight(.medium))
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
            title: "All Settings",
            icon: "gearshape",
            style: .secondary,
            fullWidth: true
        ) {
            Haptics.medium()
            showFullSettings = true
        }
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
        Haptics.success()
    }

    // MARK: - Save

    private func saveSettings() {
        guard let settings else { return }
        settings.defaultDuration = selectedDuration.rawValue
        settings.timerEndBehavior = selectedTimerBehavior
        settings.countdownDuration = countdownSeconds
        try? modelContext.save()
        Haptics.success()
    }
}
