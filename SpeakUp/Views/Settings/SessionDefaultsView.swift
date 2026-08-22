import SwiftUI

struct SessionDefaultsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 0) {
                            settingsRow(icon: "person.fill", title: "Speaker Level") {
                                Picker("", selection: $viewModel.speakerLevel) {
                                    ForEach(SpeakerLevel.allCases) { level in
                                        Text(level.displayName).tag(level)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppColors.primary)
                            }

                            divider

                            settingsRow(icon: "clock", title: "Default Duration") {
                                Picker("", selection: $viewModel.defaultDuration) {
                                    ForEach(RecordingDuration.allCases) { duration in
                                        Text(duration.displayName).tag(duration)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppColors.primary)
                            }

                            divider

                            settingsRow(icon: "timer", title: "Countdown Timer") {
                                Picker("", selection: $viewModel.countdownDuration) {
                                    ForEach(CountdownDuration.allCases) { duration in
                                        Text(duration.displayName).tag(duration)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppColors.primary)
                            }


                            divider

                            settingsRow(icon: "flag.checkered", title: "When Timer Ends") {
                                Picker("", selection: $viewModel.timerEndBehavior) {
                                    ForEach(TimerEndBehavior.allCases) { behavior in
                                        Text(behavior.displayName).tag(behavior)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppColors.primary)
                            }

                            divider

                            Toggle(isOn: $viewModel.hapticCoachingEnabled) {
                                Label("Haptic Coaching", systemImage: "hand.tap")
                                    .font(.subheadline)
                            }
                            .tint(AppColors.primary)
                            .frame(minHeight: 40)

                            divider

                            Toggle(isOn: $viewModel.chirpSoundEnabled) {
                                Label("Audio Cues", systemImage: "speaker.wave.2")
                                    .font(.subheadline)
                            }
                            .tint(AppColors.primary)
                            .frame(minHeight: 40)

                            divider

                            settingsRow(icon: "music.quarternote.3", title: "Cue Sound") {
                                Picker("", selection: $viewModel.soundPack) {
                                    ForEach(SoundPack.allCases) { pack in
                                        Text(pack.displayName).tag(pack)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppColors.primary)
                                .disabled(!viewModel.chirpSoundEnabled)
                            }

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

                    Text("Speaker level controls your daily prompt difficulty mix. Countdown timer gives you time to prepare. \"Keep Going\" lets you record past the timer. Haptic coaching gives gentle vibrations for long silences, fillers, or pace changes. Audio cues play short chirps during warm-ups and drills, and Cue Sound picks their timbre.")
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
            .onChange(of: viewModel.speakerLevel) { _, _ in
                guard !viewModel.isSyncing else { return }
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.defaultDuration) { _, _ in
                guard !viewModel.isSyncing else { return }
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.countdownDuration) { _, _ in
                guard !viewModel.isSyncing else { return }
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.timerEndBehavior) { _, _ in
                guard !viewModel.isSyncing else { return }
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.hapticCoachingEnabled) { _, _ in
                guard !viewModel.isSyncing else { return }
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.chirpSoundEnabled) { _, _ in
                guard !viewModel.isSyncing else { return }
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.soundPack) { _, pack in
                guard !viewModel.isSyncing else { return }
                Task {
                    await viewModel.saveSettings()
                    // Hear the pack you just picked — the whole point of the row.
                    ChirpPlayer.shared.pack = pack
                    ChirpPlayer.shared.play(.tick)
                }
            }
            .onChange(of: viewModel.weeklyGoalSessions) { _, _ in
                guard !viewModel.isSyncing else { return }
                Task { await viewModel.saveSettings() }
            }
    }
}
