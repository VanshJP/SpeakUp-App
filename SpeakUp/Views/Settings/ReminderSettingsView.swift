import SwiftUI

struct ReminderSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 0) {
                            Toggle(isOn: $viewModel.dailyReminderEnabled) {
                                Label("Daily Reminder", systemImage: "bell.fill")
                                    .font(.subheadline)
                            }
                            .tint(AppColors.primary)
                            .frame(minHeight: 40)

                            if viewModel.dailyReminderEnabled {
                                Divider().padding(.vertical, 8)

                                toggleRow(
                                    isOn: $viewModel.adaptiveReminderEnabled,
                                    title: "Pick the Time For Me",
                                    icon: "wand.and.stars",
                                    detail: "Big Talk watches when you actually practise and moves the reminder to half an hour before."
                                )

                                Divider().padding(.vertical, 8)

                                timeRow
                            }
                        }
                    }

                    if viewModel.dailyReminderEnabled {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("What else we send")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 12)

                                toggleRow(
                                    isOn: $viewModel.streakRemindersEnabled,
                                    title: "Streak Saves",
                                    icon: "flame.fill",
                                    detail: "An evening nudge on days you have a streak going and have not practised yet."
                                )

                                Divider().padding(.vertical, 8)

                                toggleRow(
                                    isOn: $viewModel.comebackRemindersEnabled,
                                    title: "Comeback Nudges",
                                    icon: "arrow.uturn.backward",
                                    detail: "On days 2, 4 and 7 after your last take. Then we stop."
                                )

                                Divider().padding(.vertical, 8)

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
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
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

    /// Adaptive mode makes the time a readout, not an input: the scheduler owns
    /// the slot, and a picker the app overwrites every morning is a lie. Picking
    /// a time by hand is how you take it back, so the switch happens here rather
    /// than behind a second confirmation.
    @ViewBuilder
    private var timeRow: some View {
        if viewModel.adaptiveReminderEnabled {
            HStack {
                Label("Reminder Time", systemImage: "clock")
                    .font(.subheadline)
                Spacer()
                Text(learnedTimeText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 40)
            .accessibilityElement(children: .combine)

            Button("Set the time myself") {
                Haptics.light()
                viewModel.adaptiveReminderEnabled = false
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(AppColors.primary)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
        } else {
            HStack {
                Label("Reminder Time", systemImage: "clock")
                    .font(.subheadline)
                Spacer()
                DatePicker(
                    "",
                    selection: $viewModel.reminderTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .tint(AppColors.primary)
            }
            .frame(minHeight: 40)
        }
    }

    private var learnedTimeText: String {
        viewModel.reminderTime.formatted(date: .omitted, time: .shortened)
    }

    private var footerText: String {
        guard viewModel.dailyReminderEnabled else {
            return "One reminder a day, plus optional streak and comeback nudges you control below. Off means we never notify you."
        }
        return viewModel.adaptiveReminderEnabled
            ? "The daily reminder follows your own practice times and lands half an hour ahead of them, so it arrives while you still have the evening. At most three notifications in a day, and only with a week-long streak on the line."
            : "At most three notifications in a day, and only if you have a week-long streak on the line. Turning Daily Reminder off silences all of them."
    }

    private func toggleRow(
        isOn: Binding<Bool>,
        title: String,
        icon: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn) {
                Label(title, systemImage: icon)
                    .font(.subheadline)
            }
            .tint(AppColors.primary)
            .frame(minHeight: 40)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
