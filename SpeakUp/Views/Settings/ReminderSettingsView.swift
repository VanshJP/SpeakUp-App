import SwiftUI
import UserNotifications

struct ReminderSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: AppLayout.chapterSpacing) {
                    GlassRowGroup(dividerInset: Self.dividerInset) {
                        row {
                            Toggle(isOn: $viewModel.dailyReminderEnabled) {
                                Label("Daily reminder", systemImage: "bell.fill")
                                    .font(.subheadline)
                            }
                            .tint(AppColors.primary)
                        }

                        // The toggle can be on while iOS delivers nothing. Say
                        // so, next to the one control that fixes it.
                        if viewModel.notificationsBlocked {
                            permissionRow
                        }

                        if viewModel.dailyReminderEnabled {
                            toggleRow(
                                isOn: $viewModel.adaptiveReminderEnabled,
                                title: "Pick the time for me",
                                icon: "wand.and.stars",
                                detail: "Big Talk watches when you actually practise and moves the reminder to half an hour before."
                            )

                            timeRows
                        }
                    }

                    if viewModel.dailyReminderEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            GlassSectionHeader("What else we send")

                            GlassRowGroup(dividerInset: Self.dividerInset) {
                                toggleRow(
                                    isOn: $viewModel.streakRemindersEnabled,
                                    title: "Streak saves",
                                    icon: "flame.fill",
                                    detail: "An evening nudge on days you have a streak going and have not practised yet."
                                )

                                toggleRow(
                                    isOn: $viewModel.comebackRemindersEnabled,
                                    title: "Comeback nudges",
                                    icon: "arrow.uturn.backward",
                                    detail: "On days 2, 4 and 7 after your last take. Then we stop."
                                )

                                toggleRow(
                                    isOn: $viewModel.milestoneNotificationsEnabled,
                                    title: "Milestones",
                                    icon: "rosette",
                                    detail: "When you hit 3, 7, 14, 30 days and up."
                                )
                            }
                        }
                    }

                    Text(footerText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding()
                .labelStyle(.row)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings, where the answer may have changed.
            guard phase == .active else { return }
            Task { await viewModel.refreshNotificationStatus() }
        }
        .onChange(of: viewModel.dailyReminderEnabled) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onChange(of: viewModel.reminderTime) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onChange(of: viewModel.adaptiveReminderEnabled) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onChange(of: viewModel.streakRemindersEnabled) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onChange(of: viewModel.comebackRemindersEnabled) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onChange(of: viewModel.milestoneNotificationsEnabled) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
    }

    // MARK: - Rows

    /// Rules start under the row titles: 14pt row inset + the 24pt glyph
    /// column + the 12pt gap of `RowLabelStyle`.
    private static let dividerInset: CGFloat = 50
    private static let captionIndent: CGFloat = 36

    /// "Denied" can only be undone in iOS Settings; "never asked" can still
    /// show the system prompt, so it gets an Allow button instead.
    private var permissionRow: some View {
        let isDenied = viewModel.notificationStatus == .denied
        return row {
            HStack(spacing: 8) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications are off")
                            .font(.subheadline.weight(.semibold))
                        Text(isDenied
                             ? "iOS is blocking Big Talk, so nothing will arrive."
                             : "Big Talk hasn't been allowed to notify you yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "bell.slash.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.warning)
                }

                Spacer(minLength: 8)

                GlassButton(title: isDenied ? "Open Settings" : "Allow", style: .secondary, size: .small) {
                    Haptics.light()
                    if isDenied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } else {
                        Task { await viewModel.requestNotificationPermission() }
                    }
                }
            }
        }
    }

    /// Adaptive mode makes the time a readout, not an input: the scheduler owns
    /// the slot, and a picker the app overwrites every morning is a lie. Picking
    /// a time by hand is how you take it back, so the switch happens here rather
    /// than behind a second confirmation.
    @ViewBuilder
    private var timeRows: some View {
        if viewModel.adaptiveReminderEnabled {
            row {
                HStack {
                    Label("Reminder time", systemImage: "clock")
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Text(learnedTimeText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            Button {
                Haptics.light()
                viewModel.adaptiveReminderEnabled = false
            } label: {
                row {
                    Text("Set the time myself")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.primary)
                        .padding(.leading, Self.captionIndent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
        } else {
            row {
                HStack {
                    Label("Reminder time", systemImage: "clock")
                        .font(.subheadline)
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    DatePicker(
                        "Reminder time",
                        selection: $viewModel.reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .tint(AppColors.primary)
                }
            }
        }
    }

    private var learnedTimeText: String {
        viewModel.reminderTime.formatted(date: .omitted, time: .shortened)
    }

    /// The ceiling is stated whenever the channel is on (settings.md rule 18).
    /// Off, it only promises what the page can show: the toggles below appear
    /// once the daily reminder is on.
    private var footerText: String {
        guard viewModel.dailyReminderEnabled else {
            return "One reminder a day. Turn it on to also choose streak, comeback, and milestone nudges. Off means we never notify you."
        }
        return "At most three notifications in a day, and only with a week-long streak on the line. Turning off the daily reminder silences all of them."
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
    }

    private func toggleRow(
        isOn: Binding<Bool>,
        title: String,
        icon: String,
        detail: String
    ) -> some View {
        row {
            Toggle(isOn: isOn) {
                Label(title, systemImage: icon)
                    .font(.subheadline)
            }
            .tint(AppColors.primary)
            .accessibilityHint(detail)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Self.captionIndent)
                .accessibilityHidden(true)
        }
    }
}
