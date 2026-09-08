import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        PageScrollView {
            VStack(spacing: AppLayout.listSpacing) {
                practiceSection
                appearanceSection
                accountSection

                aboutFooter
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
        VStack(spacing: 12) {
            GlassSectionHeader("Practice", icon: "waveform")

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
                icon: "waveform.badge.magnifyingglass",
                iconColor: AppColors.categoryNeutralCool,
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
                subtitle: "Add vocab, dictation, and filler words"
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
        VStack(spacing: 12) {
            GlassSectionHeader("Appearance", icon: "paintpalette.fill")
                .padding(.top, 4)

            settingsLink(
                icon: "paintpalette.fill",
                iconColor: AppColors.categoryIndigo,
                title: "App Look",
                subtitle: appLookSubtitle,
                accessory: {
                    lookSwatch {
                        AppCanvasView(canvas: viewModel.appCanvas, style: .primary, animated: false)
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
                            animated: false,
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
        VStack(spacing: 12) {
            GlassSectionHeader("Account & Data", icon: "person.crop.circle")
                .padding(.top, 4)

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
                subtitle: viewModel.dailyReminderEnabled ? "Change your reminder time" : "Turn on a daily practice reminder"
            ) {
                ReminderSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "cpu",
                iconColor: AppColors.info,
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

    private var aboutFooter: some View {
        NavigationLink {
            AboutSettingsView()
                .restoresNavigationBar()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("About Big Talk")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("v\(viewModel.appVersion) (\(viewModel.buildNumber))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    // MARK: - iCloud Sync

    @State private var iCloudSyncEnabled = ICloudStorageService.shared.isSyncEnabled
    @State private var showingSyncRestartAlert = false

    private var iCloudSyncRow: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.categoryBrandBright)
                        .frame(width: 32, height: 32)
                        .background { Circle().fill(AppColors.categoryBrandBright.opacity(0.15)) }

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
        return "Sync recordings across your devices"
    }

    // MARK: - Helpers

    /// Hub subtitles name the action the row performs, never the value.
    private var profileSubtitle: String {
        viewModel.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Set your name"
            : "Edit your name"
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
            GlassCard(padding: 14) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 32, height: 32)
                        .background { Circle().fill(iconColor.opacity(0.15)) }

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

                    Spacer(minLength: 8)

                    accessory()

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
                        PrivacyDataView()
                    } label: {
                        aboutRow(
                            "Privacy & Data",
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
