import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
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
            settingsLink(
                icon: "slider.horizontal.3",
                iconColor: .teal,
                title: "Session Defaults",
                subtitle: viewModel.defaultDuration.displayName + ", " + viewModel.countdownDuration.displayName + " countdown"
            ) {
                SessionDefaultsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "waveform.badge.magnifyingglass",
                iconColor: .blue,
                title: "Analysis",
                subtitle: "Target: \(viewModel.targetWPM) WPM"
            ) {
                AnalysisSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "character.book.closed",
                iconColor: .green,
                title: "Words",
                subtitle: wordsSubtitle
            ) {
                WordBankView(viewModel: viewModel)
            }

            settingsLink(
                icon: "bubble.left.and.text.bubble.right",
                iconColor: .purple,
                title: "Session Feedback",
                subtitle: "\(viewModel.activeFeedbackQuestions.count) questions"
            ) {
                FeedbackSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "text.quote",
                iconColor: .orange,
                title: "Prompts",
                subtitle: "\(viewModel.enabledPromptCategories.count) categories"
            ) {
                PromptSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "bell.fill",
                iconColor: .yellow,
                title: "Reminders",
                subtitle: viewModel.dailyReminderEnabled ? reminderTimeString : "Off"
            ) {
                ReminderSettingsView(viewModel: viewModel)
            }

            settingsLink(
                icon: "cpu",
                iconColor: .purple,
                title: "AI Features",
                subtitle: aiModelSubtitle
            ) {
                AIModelSettingsView()
            }

            settingsLink(
                icon: "externaldrive.fill",
                iconColor: .gray,
                title: "Data Management",
                subtitle: "Export, reset, or manage data"
            ) {
                DataManagementView(viewModel: viewModel)
            }

            settingsLink(
                icon: "info.circle",
                iconColor: .secondary,
                title: "About",
                subtitle: "v\(viewModel.appVersion) (\(viewModel.buildNumber))"
            ) {
                AboutSettingsView()
            }
        }
    }

    // MARK: - Helpers

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
        return parts.isEmpty ? "Vocab, dictation, and filler words" : parts.joined(separator: ", ")
    }

    private var aiModelSubtitle: String {
        switch llmService.activeBackend {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .localLLM:
            return LocalLLMService.modelDisplayName
        case .none:
            return "Not available"
        }
    }

    private var reminderTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Daily at " + formatter.string(from: viewModel.reminderTime)
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
            AppBackground(style: .subtle)

            ScrollView {
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

                    Link(destination: URL(string: "mailto:vansh@trygoldfinch.com")!) {
                        GlassCard(padding: 14) {
                            HStack {
                                Label("Send Feedback", systemImage: "envelope")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 32)
                        }
                    }

                    NavigationLink {
                        JournalExportView()
                    } label: {
                        GlassCard(padding: 14) {
                            HStack {
                                Label("Export Progress Journal", systemImage: "doc.richtext")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 32)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}
