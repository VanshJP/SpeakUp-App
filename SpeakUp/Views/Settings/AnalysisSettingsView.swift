import SwiftUI

struct AnalysisSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var pendingTargetWPMSave: Task<Void, Never>?

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: AppLayout.chapterSpacing) {
                    // Each row explains itself; the paragraph that used to sit
                    // under the card covered five rows at once.
                    GlassRowGroup(dividerInset: Self.dividerInset) {
                        toggleRow(
                            "Track pauses",
                            icon: "pause.circle",
                            isOn: $viewModel.trackPauses,
                            caption: "Scores how long you pause and where."
                        )

                        toggleRow(
                            "Track filler words",
                            icon: "text.bubble",
                            isOn: $viewModel.trackFillerWords,
                            caption: "Counts um, uh, like, and the rest of your filler list."
                        )

                        if viewModel.trackFillerWords {
                            linkRow(
                                "Filler words",
                                icon: "text.badge.minus",
                                caption: "Choose which words count as fillers."
                            ) {
                                EmptyView()
                            } destination: {
                                WordBankView(viewModel: viewModel, showDismissButton: false, initialTab: .fillers)
                            }
                        }

                        toggleRow(
                            "Auto pace target",
                            icon: "wand.and.stars",
                            isOn: $viewModel.autoPaceTarget,
                            caption: "Learns your natural pace from every take. Turn it off to set your own."
                        )

                        targetPaceRow

                        linkRow(
                            "Voice Profile",
                            icon: "waveform.and.person.filled",
                            caption: "Helps Big Talk pick out your voice."
                        ) {
                            Text(viewModel.voiceProfileStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } destination: {
                            VoiceProfileView(viewModel: viewModel)
                        }

                        linkRow(
                            "Score Weights",
                            icon: "slider.horizontal.3",
                            caption: "Choose what counts most in your overall score."
                        ) {
                            if viewModel.hasCustomWeights {
                                StatusPill(text: "Custom", color: AppColors.primary)
                            }
                        } destination: {
                            ScoreWeightsView(viewModel: viewModel)
                        }
                    }
                }
                .padding()
                .labelStyle(.row)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.trackPauses) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onChange(of: viewModel.trackFillerWords) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
        .onChange(of: viewModel.targetWPM) { _, _ in
            guard !viewModel.isSyncing else { return }
            // Debounced. A drag moves this on every step, and each save is a
            // store write, a CloudKit export and a full reminder reschedule.
            // Not cancelled on disappear, so leaving mid-settle still saves.
            pendingTargetWPMSave?.cancel()
            pendingTargetWPMSave = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await viewModel.saveSettings()
            }
        }
        .onChange(of: viewModel.autoPaceTarget) { _, _ in
            guard !viewModel.isSyncing else { return }
            Task { await viewModel.saveSettings() }
        }
    }

    // MARK: - Rows

    /// Rules start under the row titles: 14pt row inset + the 24pt glyph
    /// column + the 12pt gap of `RowLabelStyle`.
    private static let dividerInset: CGFloat = 50
    private static let captionIndent: CGFloat = 36

    @ViewBuilder
    private var targetPaceRow: some View {
        if viewModel.autoPaceTarget {
            row {
                HStack {
                    Label("Target pace", systemImage: "speedometer")
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Text(viewModel.hasCalibratedWPM
                         ? "Learned: \(viewModel.displayTargetWPM) WPM"
                         : "Learning from your takes…")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } else {
            row {
                HStack {
                    Label("Target pace", systemImage: "speedometer")
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Text("\(viewModel.targetWPM) WPM")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)

                Slider(
                    value: Binding(
                        get: { Double(viewModel.targetWPM) },
                        set: { viewModel.targetWPM = Int($0) }
                    ),
                    in: 100...200,
                    step: 5
                )
                .tint(AppColors.primary)
                .accessibilityLabel("Target pace")
                .accessibilityValue("\(viewModel.targetWPM) words per minute")
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
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

    private func linkRow<Accessory: View, Destination: View>(
        _ title: String,
        icon: String,
        caption: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
                .restoresNavigationBar()
        } label: {
            row {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    accessory()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                captionText(caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint(caption)
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
