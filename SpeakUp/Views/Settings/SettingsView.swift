import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                VStack(spacing: 16) {
                    settingsMenuCard
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Settings")
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }

    // MARK: - Menu Card

    private var settingsMenuCard: some View {
        VStack(spacing: 12) {
            LifetimeStatusRow()

            GlassSectionHeader("You", icon: "person.crop.circle")

            settingsLink(
                icon: "person.crop.circle",
                iconColor: AppColors.primary,
                title: "Profile",
                subtitle: profileSubtitle
            ) {
                ProfileSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "slider.horizontal.3",
                iconColor: AppColors.primary,
                title: "Session Defaults",
                subtitle: viewModel.defaultDuration.displayName + ", " + viewModel.countdownDuration.displayName + " countdown"
            ) {
                SessionDefaultsView(viewModel: viewModel)
            }
            .tourAnchor(.settingsPresets)

            settingsLink(
                icon: "bell.fill",
                iconColor: AppColors.categoryAmber,
                title: "Reminders",
                subtitle: viewModel.dailyReminderEnabled ? reminderTimeString : "Off"
            ) {
                ReminderSettingsView(viewModel: viewModel)
            }

            GlassSectionHeader("Practice & Scoring", icon: "waveform")
                .padding(.top, 8)

            settingsLink(
                icon: "waveform.badge.magnifyingglass",
                iconColor: AppColors.categoryNeutralCool,
                title: "Analysis",
                subtitle: "Target: \(viewModel.displayTargetWPM) WPM"
            ) {
                AnalysisSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "waveform.circle",
                iconColor: AppColors.categoryBrandBright,
                title: "Recording Look",
                // Two of the four, because the row is `.lineLimit(1)` and four
                // names truncate at default type on a small phone. These are
                // the two you see the whole session.
                subtitle: "\(viewModel.recordingBackdrop.displayName) · \(viewModel.waveformStyle.displayName)"
            ) {
                RecordingLookView(viewModel: viewModel)
            }

            settingsLink(
                icon: "character.book.closed",
                iconColor: AppColors.categorySage,
                title: "Words",
                subtitle: wordsSubtitle
            ) {
                WordBankView(viewModel: viewModel, showDismissButton: false)
            }

            settingsLink(
                icon: "text.quote",
                iconColor: AppColors.categoryCopper,
                title: "Prompts",
                subtitle: "\(viewModel.enabledPromptCategories.count) categories"
            ) {
                PromptSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "bubble.left.and.text.bubble.right",
                iconColor: AppColors.categoryPlum,
                title: "Session Feedback",
                subtitle: "\(viewModel.activeFeedbackQuestions.count) questions"
            ) {
                FeedbackSettingsView(viewModel: viewModel)
            }

            GlassSectionHeader("Intelligence & Data", icon: "cpu")
                .padding(.top, 8)

            settingsLink(
                icon: "cpu",
                iconColor: AppColors.categoryIndigo,
                title: "AI Features",
                subtitle: aiModelSubtitle
            ) {
                AIModelSettingsView()
            }

            iCloudSyncRow

            settingsLink(
                icon: "externaldrive.fill",
                iconColor: AppColors.accent,
                title: "Data Management",
                subtitle: "Export, reset, or manage data"
            ) {
                DataManagementView(viewModel: viewModel)
            }

            settingsLink(
                icon: "info.circle",
                iconColor: AppColors.accent,
                title: "About",
                subtitle: "v\(viewModel.appVersion) (\(viewModel.buildNumber))"
            ) {
                AboutSettingsView()
            }
        }
    }

    // MARK: - iCloud Sync

    @State private var iCloudSyncEnabled = ICloudStorageService.shared.isSyncEnabled
    @State private var showingSyncRestartAlert = false

    private var iCloudSyncRow: some View {
        GlassCard(tint: AppColors.info.opacity(0.06), padding: 14) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppColors.info.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.info)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Sync")
                            .font(.subheadline.weight(.semibold))
                        Text(iCloudSyncSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !ICloudStorageService.shared.hasResolvedContainer {
                        ProgressView()
                            .tint(.secondary)
                    } else if ICloudStorageService.shared.isICloudReachable {
                        Toggle("", isOn: $iCloudSyncEnabled)
                            .labelsHidden()
                            .tint(AppColors.primary)
                            .onChange(of: iCloudSyncEnabled) { _, newValue in
                                // Turning sync *on* is part of Lifetime. Turning
                                // it off never is — a user must always be able to
                                // stop their data leaving the device.
                                if newValue,
                                   !PaywallCoordinator.allow(.iCloudSync, trigger: "icloud_sync") {
                                    iCloudSyncEnabled = false
                                    return
                                }
                                ICloudStorageService.shared.isSyncEnabled = newValue
                                // Also persist to SwiftData settings
                                if let settings = viewModel.settings {
                                    settings.iCloudSyncEnabled = newValue
                                }
                                showingSyncRestartAlert = true
                            }
                    } else {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(AppColors.warning)
                    }
                }

                if iCloudSyncEnabled && ICloudStorageService.shared.isICloudAvailable {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(AppColors.success)
                        Text("Recordings and data sync across all your devices")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .alert("Restart Required", isPresented: $showingSyncRestartAlert) {
            Button("OK") {}
        } message: {
            Text("Please restart Big Talk for the sync change to take effect.")
        }
    }

    private var iCloudSyncSubtitle: String {
        if !ICloudStorageService.shared.hasResolvedContainer {
            return "Checking iCloud availability…"
        }
        if !ICloudStorageService.shared.isICloudReachable {
            return "Sign in to iCloud in Settings to enable"
        }
        if iCloudSyncEnabled {
            return "Syncing across your devices"
        }
        return "Disabled — recordings stay on this device"
    }

    // MARK: - Helpers

    private var profileSubtitle: String {
        let name = viewModel.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Set your name" : name
    }

    private var wordsSubtitle: String {
        var parts: [String] = []
        if viewModel.vocabWords.count > 0 {
            parts.append("\(viewModel.vocabWords.count) vocab")
        }
        if viewModel.dictationBiasWords.count > 0 {
            parts.append("\(viewModel.dictationBiasWords.count) dictation")
        }
        if viewModel.hasFillerCustomizations {
            parts.append("fillers customized")
        }
        if viewModel.vocabChallengeEnabled {
            parts.append("daily workout")
        }
        return parts.isEmpty ? "Vocab, dictation, and filler words" : parts.joined(separator: ", ")
    }

    private var aiModelSubtitle: String {
        switch llmService.activeBackend {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .localLLM:
            return llmService.localLLM.modelDisplayName
        case .none:
            return "Not available"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private var reminderTimeString: String {
        "Daily at " + Self.timeFormatter.string(from: viewModel.reminderTime)
    }

    private func settingsLink<Destination: View>(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String?,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            GlassCard(padding: 14) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(iconColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(" ")
                                .font(.caption)
                                .opacity(0)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About Settings View

struct AboutSettingsView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"

    var body: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                VStack(spacing: 12) {
                    GlassCard(padding: 14) {
                        HStack {
                            Label("Version", systemImage: "info.circle")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(appVersion) (\(buildNumber))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 32)
                    }

                    NavigationLink {
                        LifetimeFAQView()
                    } label: {
                        aboutRow(
                            "Lifetime, Privacy & Data",
                            icon: "hand.raised",
                            trailingIcon: "chevron.right"
                        )
                    }
                    .buttonStyle(GlassPressStyle())

                    if let mail = SupportLinks.feedbackMailto {
                        Link(destination: mail) {
                            aboutRow("Send Feedback", icon: "envelope", trailingIcon: "arrow.up.right")
                        }
                    }

                    if let support = SupportLinks.support {
                        Link(destination: support) {
                            aboutRow("Support", icon: "lifepreserver", trailingIcon: "arrow.up.right")
                        }
                    }

                    if let privacy = SupportLinks.privacyPolicy {
                        Link(destination: privacy) {
                            aboutRow("Privacy Policy", icon: "lock.shield", trailingIcon: "arrow.up.right")
                        }
                    }

                    if let terms = SupportLinks.terms {
                        Link(destination: terms) {
                            aboutRow("Terms of Use", icon: "doc.text", trailingIcon: "arrow.up.right")
                        }
                    }

                    NavigationLink {
                        AnalyticsDiagnosticsView()
                    } label: {
                        aboutRow(
                            "Usage Diagnostics",
                            icon: "chart.bar.doc.horizontal",
                            trailingIcon: "chevron.right"
                        )
                    }
                    .buttonStyle(GlassPressStyle())

                    Text("Big Talk keeps your recordings, transcripts, and scores on this device. There is no account, and nothing is uploaded to us.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                    // Journal export lives in History → Progress → More,
                    // next to the data it exports.
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutRow(_ title: String, icon: String, trailingIcon: String) -> some View {
        GlassCard(padding: 14) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: trailingIcon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 32)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}
