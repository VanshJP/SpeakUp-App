import SwiftUI

struct ReminderSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 0) {
                            Toggle(isOn: $viewModel.dailyReminderEnabled) {
                                Label("Daily Reminder", systemImage: "bell.fill")
                                    .font(.subheadline)
                            }
                            .tint(.teal)
                            .frame(minHeight: 40)

                            if viewModel.dailyReminderEnabled {
                                Divider().padding(.vertical, 8)

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
                                    .tint(.teal)
                                }
                                .frame(minHeight: 40)
                            }
                        }
                    }

                    Text("Get a daily notification to practice your speaking skills.")
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
    }
}
