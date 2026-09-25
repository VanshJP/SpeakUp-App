import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        PageScrollView {
            VStack(spacing: AppLayout.chapterSpacing) {
                PageTitle(kicker: "Big Talk", title: "Settings")

                practiceSection
                appearanceSection
                accountSection
                aboutSection
            }
            .padding(.top, 8)
            .pageContentInsets()
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.configure(with: modelContext)
        }
    }

    // MARK: - Practice

    private var practiceSection: some View {
        settingsGroup("Practice") {
            settingsLink(
                icon: "slider.horizontal.3",
                iconColor: AppColors.primary,
                title: "Session Defaults",
                subtitle: "Choose take length, countdown, and goal"
            ) {
                SessionDefaultsView(viewModel: viewModel)
            }
            .tourAnchor(.settingsPresets)

            settingsLink(
                icon: "list.bullet.indent",
                iconColor: AppColors.categoryBrandBright,
                title: "Routine",
                subtitle: "Choose what a session walks you through"
            ) {
                RoutineSettingsView()
            }

            settingsLink(
                icon: "waveform.badge.magnifyingglass",
                iconColor: AppColors.info,
                title: "Analysis",
                subtitle: "Tune pace, fillers, and score weights"
            ) {
                AnalysisSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "character.book.closed",
                iconColor: AppColors.categorySage,
                title: "Word Workout",
                subtitle: viewModel.vocabChallengeEnabled ? "Adjust words per day and level" : "Turn on the daily word workout"
            ) {
                WordWorkoutSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "list.bullet.rectangle",
                iconColor: AppColors.categoryTeal,
                title: "Word Lists",
                subtitle: "Add words, names, and fillers"
            ) {
                WordBankView(viewModel: viewModel, showDismissButton: false)
            }

            settingsLink(
                icon: "text.quote",
                iconColor: AppColors.categoryCopper,
                title: "Prompts",
                subtitle: "Choose which prompt categories appear"
            ) {
                PromptSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "bubble.left.and.text.bubble.right",
                iconColor: AppColors.categoryPlum,
                title: "Session Feedback",
                subtitle: "Choose your post-session questions"
            ) {
                FeedbackSettingsView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        settingsGroup("Appearance") {
            settingsLink(
                icon: "paintpalette.fill",
                iconColor: AppColors.categoryIndigo,
                title: "App Look",
                subtitle: appLookSubtitle,
                accessory: {
                    lookSwatch {
                        AppCanvasView(canvas: viewModel.appCanvas, style: .primary)
                    }
                }
            ) {
                AppearanceSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "waveform.circle.fill",
                iconColor: AppColors.categoryBrandBright,
                title: "Recording Look",
                subtitle: recordingLookSubtitle,
                accessory: {
                    lookSwatch {
                        RecordingBackdropView(
                            backdrop: viewModel.recordingBackdrop,
                            fillsSafeArea: false
                        )
                    }
                }
            ) {
                RecordingLookView(viewModel: viewModel)
            }
        }
    }

    private func lookSwatch<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 320, height: 210)
            .scaleEffect(0.2)
            .frame(width: 52, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AppColors.cardStroke, lineWidth: 1)
            }
            .allowsHitTesting(false)
    }

    private var appLookSubtitle: String {
        "\(viewModel.appCanvas.displayName) · \(viewModel.glassAppearance.displayName) glass"
    }

    private var recordingLookSubtitle: String {
        "\(viewModel.recordingBackdrop.displayName) · \(viewModel.waveformStyle.displayName)"
    }

    // MARK: - Account

    private var accountSection: some View {
        settingsGroup("Account & data") {
            settingsLink(
                icon: "person.crop.circle",
                iconColor: AppColors.primary,
                title: "Profile",
                subtitle: profileSubtitle
            ) {
                ProfileSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "bell.fill",
                iconColor: AppColors.categoryAmber,
                title: "Reminders",
                subtitle: reminderSubtitle
            ) {
                ReminderSettingsView(viewModel: viewModel)
            }

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
                subtitle: "Reset settings or clear all data"
            ) {
                DataManagementView(viewModel: viewModel)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsGroup(nil) {
            settingsLink(
                icon: "info.circle",
                iconColor: AppColors.accent,
                title: "About Big Talk",
                subtitle: "Privacy, support, and diagnostics",
                accessory: {
                    Text("v\(viewModel.appVersion) (\(viewModel.buildNumber))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            ) {
                AboutSettingsView()
            }
        }
    }

    // MARK: - iCloud Sync

    @State private var iCloudSyncEnabled = ICloudStorageService.shared.isSyncEnabled
    @State private var showingSyncRestartAlert = false

    private var iCloudSyncRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                IconChip(icon: "icloud.fill", tint: AppColors.categoryBrandBright, size: Self.rowIconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Sync")
                        .font(.subheadline.weight(.semibold))
                    Text(iCloudSyncSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !ICloudStorageService.shared.hasResolvedContainer {
                    VoiceLoader(size: .small)
                        .foregroundStyle(.secondary)
                } else if ICloudStorageService.shared.isICloudReachable {
                    Toggle("", isOn: $iCloudSyncEnabled)
                        .labelsHidden()
                        .tint(AppColors.primary)
                        .onChange(of: iCloudSyncEnabled) { _, newValue in
                            ICloudStorageService.shared.isSyncEnabled = newValue
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
        .padding(.horizontal, Self.rowPadding)
        .padding(.vertical, 12)
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
        return "Sync recordings across your devices"
    }

    // MARK: - Helpers

    /// Hub subtitles name the action the row performs, never the value.
    private var profileSubtitle: String {
        viewModel.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Set your name"
            : "Edit your name"
    }

    private var reminderSubtitle: String {
        guard viewModel.dailyReminderEnabled else { return "Turn on a daily practice reminder" }
        return viewModel.adaptiveReminderEnabled
            ? "Timed to your own practice rhythm"
            : "Change your reminder time"
    }

    private var aiModelSubtitle: String {
        switch llmService.activeBackend {
        case .appleIntelligence:
            return "Manage Apple Intelligence"
        case .localLLM:
            return "Manage \(llmService.localLLM.modelDisplayName)"
        case .none:
            return "Set up on-device AI"
        }
    }

    // MARK: - Rows

    private static let rowIconSize: CGFloat = 30
    private static let rowPadding: CGFloat = 14

    /// A section of the hub: its name, then its rows on one plate.
    private func settingsGroup<Rows: View>(
        _ title: String?,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                GlassSectionHeader(title)
            }

            // Rules start under the row text, past the icon and its gap.
            GlassRowGroup(dividerInset: Self.rowPadding + Self.rowIconSize + 14) {
                rows()
            }
        }
    }

    private func settingsLink<Destination: View, Accessory: View>(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String?,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
                .restoresNavigationBar()
        } label: {
            HStack(spacing: 14) {
                IconChip(icon: icon, tint: iconColor, size: Self.rowIconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                accessory()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Self.rowPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

// MARK: - About Settings View

struct AboutSettingsView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"

    var body: some View {
        ZStack {
            AppBackground()

            PageScrollView {
                VStack(spacing: AppLayout.listSpacing) {
                    GlassRowGroup(dividerInset: 14) {
                        HStack {
                            Label("Version", systemImage: "info.circle")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(appVersion) (\(buildNumber))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(minHeight: 52)

                        NavigationLink {
                            PrivacyDataView()
                        } label: {
                            aboutRow("Privacy & Data", icon: "hand.raised", trailingIcon: "chevron.right")
                        }
                        .buttonStyle(RowPressStyle())

                        NavigationLink {
                            AnalyticsDiagnosticsView()
                        } label: {
                            aboutRow("Usage Diagnostics", icon: "chart.bar.doc.horizontal", trailingIcon: "chevron.right")
                        }
                        .buttonStyle(RowPressStyle())
                    }

                    GlassRowGroup(dividerInset: 14) {
                        if let mail = SupportLinks.feedbackMailto {
                            Link(destination: mail) {
                                aboutRow("Send Feedback", icon: "envelope", trailingIcon: "arrow.up.right")
                            }
                            .buttonStyle(RowPressStyle())
                        }

                        if let support = SupportLinks.support {
                            Link(destination: support) {
                                aboutRow("Support", icon: "lifepreserver", trailingIcon: "arrow.up.right")
                            }
                            .buttonStyle(RowPressStyle())
                        }

                        if let privacy = SupportLinks.privacyPolicy {
                            Link(destination: privacy) {
                                aboutRow("Privacy Policy", icon: "lock.shield", trailingIcon: "arrow.up.right")
                            }
                            .buttonStyle(RowPressStyle())
                        }

                        if let terms = SupportLinks.terms {
                            Link(destination: terms) {
                                aboutRow("Terms of Use", icon: "doc.text", trailingIcon: "arrow.up.right")
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }

                    Text("Big Talk keeps your recordings, transcripts, and scores on this device. There is no account, and nothing is uploaded to us.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                .padding()
                .labelStyle(.row)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutRow(_ title: String, icon: String, trailingIcon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: trailingIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}
