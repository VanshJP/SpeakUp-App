import SwiftUI

struct SessionDefaultsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: AppLayout.chapterSpacing) {
                    // Each row explains itself. The paragraph under the card
                    // that used to cover five rows at once is gone.
                    GlassRowGroup(dividerInset: Self.dividerInset) {
                        pickerRow(
                            "Speaker level",
                            icon: "person.fill",
                            selection: $viewModel.speakerLevel,
                            caption: viewModel.speakerLevel.subtitle
                        ) {
                            ForEach(SpeakerLevel.allCases) { level in
                                Text(level.displayName).tag(level)
                            }
                        }

                        pickerRow("Default duration", icon: "clock", selection: $viewModel.defaultDuration) {
                            ForEach(RecordingDuration.allCases) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }

                        pickerRow(
                            "Countdown timer",
                            icon: "timer",
                            selection: $viewModel.countdownDuration,
                            caption: "Time to get ready before recording starts."
                        ) {
                            ForEach(CountdownDuration.allCases) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }

                        pickerRow(
                            "When timer ends",
                            icon: "flag.checkered",
                            selection: $viewModel.timerEndBehavior,
                            caption: viewModel.timerEndBehavior.description
                        ) {
                            ForEach(TimerEndBehavior.allCases) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }

                        toggleRow(
                            "Haptic coaching",
                            icon: "hand.tap",
                            isOn: $viewModel.hapticCoachingEnabled,
                            caption: "Gentle taps for long silences, fillers, or pace changes."
                        )

                        toggleRow(
                            "Audio cues",
                            icon: "speaker.wave.2",
                            isOn: $viewModel.chirpSoundEnabled,
                            caption: "Short chirps during warm-ups and drills."
                        )

                        // Hidden rather than greyed out while cues are off: a
                        // disabled picker only invites the tap that cannot land.
                        if viewModel.chirpSoundEnabled {
                            pickerRow("Cue sound", icon: "music.quarternote.3", selection: $viewModel.soundPack) {
                                ForEach(SoundPack.allCases) { pack in
                                    Text(pack.displayName).tag(pack)
                                }
                            }
                        }

                        row {
                            Stepper(value: $viewModel.weeklyGoalSessions, in: 1...14) {
                                HStack {
                                    Label("Weekly goal", systemImage: "target")
                                        .font(.subheadline)
                                    Spacer(minLength: 8)
                                    Text(weeklyGoalText)
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
                .labelStyle(.row)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Session Defaults")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SessionDefaultsChangeModifiers(viewModel: viewModel))
    }

    // MARK: - Rows

    /// Rules start under the row titles: 14pt row inset + the 24pt glyph
    /// column + the 12pt gap of `RowLabelStyle`.
    private static let dividerInset: CGFloat = 50
    private static let captionIndent: CGFloat = 36

    private var weeklyGoalText: String {
        let sessions = viewModel.weeklyGoalSessions
        return sessions == 1 ? "1 session" : "\(sessions) sessions"
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
    }

    /// The picker carries the row's name and caption for VoiceOver, so the
    /// visible label is not read twice.
    private func pickerRow<Value: Hashable, Options: View>(
        _ title: String,
        icon: String,
        selection: Binding<Value>,
        caption: String? = nil,
        @ViewBuilder options: () -> Options
    ) -> some View {
        row {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Picker(title, selection: selection) {
                    options()
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(AppColors.primary)
                .accessibilityHint(caption ?? "")
            }

            if let caption {
                captionText(caption)
            }
        }
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>, caption: String) -> some View {
        row {
            Toggle(isOn: isOn) {
                Label(title, systemImage: icon)
                    .font(.subheadline)
            }
            .tint(AppColors.primary)
            .accessibilityHint(caption)

            captionText(caption)
        }
    }

    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, Self.captionIndent)
            .accessibilityHidden(true)
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
                    // Hear the pack you just picked - the whole point of the row.
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
