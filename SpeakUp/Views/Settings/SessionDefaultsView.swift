import SwiftUI
import SwiftData

struct SessionDefaultsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 0) {
                            settingsRow(icon: "clock", title: "Default Duration") {
                                Picker("", selection: $viewModel.defaultDuration) {
                                    ForEach(RecordingDuration.allCases) { duration in
                                        Text(duration.displayName).tag(duration)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.teal)
                            }

                            divider

                            settingsRow(icon: "timer", title: "Countdown Timer") {
                                Picker("", selection: $viewModel.countdownDuration) {
                                    ForEach(CountdownDuration.allCases) { duration in
                                        Text(duration.displayName).tag(duration)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.teal)
                            }

                            divider

                            settingsRow(icon: "arrow.up.arrow.down", title: "Countdown Style") {
                                Picker("", selection: $viewModel.countdownStyle) {
                                    ForEach(CountdownStyle.allCases) { style in
                                        Text(style.displayName).tag(style)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.teal)
                            }

                            divider

                            settingsRow(icon: "flag.checkered", title: "When Timer Ends") {
                                Picker("", selection: $viewModel.timerEndBehavior) {
                                    ForEach(TimerEndBehavior.allCases) { behavior in
                                        Text(behavior.displayName).tag(behavior)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.teal)
                            }

                            divider

                            Toggle(isOn: $viewModel.hapticCoachingEnabled) {
                                Label("Haptic Coaching", systemImage: "hand.tap")
                                    .font(.subheadline)
                            }
                            .tint(.teal)
                            .frame(minHeight: 40)

                            divider

                            Toggle(isOn: $viewModel.chirpSoundEnabled) {
                                Label("Audio Cues", systemImage: "speaker.wave.2")
                                    .font(.subheadline)
                            }
                            .tint(.teal)
                            .frame(minHeight: 40)

                            divider

                            Stepper(value: $viewModel.weeklyGoalSessions, in: 1...14) {
                                HStack {
                                    Label("Weekly Goal", systemImage: "target")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(viewModel.weeklyGoalSessions) sessions")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 40)
                        }
                    }

                    Text("Countdown timer gives you time to prepare. \"Keep Going\" lets you record past the timer. Haptic coaching gives gentle vibrations for long silences, fillers, or pace changes. Audio cues play short chirps during warm-ups and drills.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Session Defaults")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SessionDefaultsChangeModifiers(viewModel: viewModel))
    }

    // MARK: - Helpers

    private var divider: some View {
        Divider().padding(.vertical, 8)
    }

    private func settingsRow<Content: View>(icon: String, title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
            Spacer()
            trailing()
        }
        .frame(minHeight: 40)
    }
}

private struct SessionDefaultsChangeModifiers: ViewModifier {
    @Bindable var viewModel: SettingsViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.defaultDuration) { _, _ in
                guard !viewModel.isSyncing else { return }
                viewModel.scheduleSaveSettings()
            }
            .onChange(of: viewModel.countdownDuration) { _, _ in
                guard !viewModel.isSyncing else { return }
                viewModel.scheduleSaveSettings()
            }
            .onChange(of: viewModel.countdownStyle) { _, _ in
                guard !viewModel.isSyncing else { return }
                viewModel.scheduleSaveSettings()
            }
            .onChange(of: viewModel.timerEndBehavior) { _, _ in
                guard !viewModel.isSyncing else { return }
                viewModel.scheduleSaveSettings()
            }
            .onChange(of: viewModel.hapticCoachingEnabled) { _, _ in
                guard !viewModel.isSyncing else { return }
                viewModel.scheduleSaveSettings()
            }
            .onChange(of: viewModel.chirpSoundEnabled) { _, _ in
                guard !viewModel.isSyncing else { return }
                viewModel.scheduleSaveSettings()
            }
            .onChange(of: viewModel.weeklyGoalSessions) { _, _ in
                guard !viewModel.isSyncing else { return }
                viewModel.scheduleSaveSettings(debounce: .milliseconds(300))
            }
    }
}
