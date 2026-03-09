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
        GlassCard {
            VStack(spacing: 0) {
                settingsLink(
                    icon: "slider.horizontal.3",
                    iconColor: .teal,
                    title: "Session Defaults",
                    subtitle: viewModel.defaultDuration.displayName + ", " + viewModel.countdownDuration.displayName + " countdown"
                ) {
                    SessionDefaultsView()
                }

                divider

                settingsLink(
                    icon: "waveform.badge.magnifyingglass",
                    iconColor: .blue,
                    title: "Analysis",
                    subtitle: "Target: \(viewModel.targetWPM) WPM"
                ) {
                    AnalysisSettingsView()
                }

                divider

                settingsLink(
                    icon: "character.book.closed",
                    iconColor: .green,
                    title: "Words",
                    subtitle: wordsSubtitle
                ) {
                    WordBankView()
                }

                divider

                settingsLink(
                    icon: "bubble.left.and.text.bubble.right",
                    iconColor: .purple,
                    title: "Session Feedback",
                    subtitle: "\(viewModel.activeFeedbackQuestions.count) questions"
                ) {
                    FeedbackSettingsView()
                }

                divider

                settingsLink(
                    icon: "text.quote",
                    iconColor: .orange,
                    title: "Prompts",
                    subtitle: "\(viewModel.enabledPromptCategories.count) categories"
                ) {
                    PromptSettingsView()
                }

                divider

                settingsLink(
                    icon: "bell.fill",
                    iconColor: .yellow,
                    title: "Reminders",
                    subtitle: viewModel.dailyReminderEnabled ? reminderTimeString : "Off"
                ) {
                    ReminderSettingsView()
                }

                divider

                settingsLink(
                    icon: "cpu",
                    iconColor: .purple,
                    title: "AI Features",
                    subtitle: aiModelSubtitle
                ) {
                    AIModelSettingsView()
                }

                divider

                settingsLink(
                    icon: "externaldrive.fill",
                    iconColor: .gray,
                    title: "Data Management",
                    subtitle: nil
                ) {
                    DataManagementView()
                }

                divider

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
    }

    // MARK: - Helpers

    private var divider: some View {
        Divider().padding(.vertical, 4)
    }

    private var wordsSubtitle: String {
        var parts: [String] = []
        if viewModel.vocabWords.count > 0 {
            parts.append("\(viewModel.vocabWords.count) vocab")
        }
        if viewModel.hasFillerCustomizations {
            parts.append("fillers customized")
        }
        return parts.isEmpty ? "Vocab & filler words" : parts.joined(separator: ", ")
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
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About Settings View

struct AboutSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(spacing: 0) {
                            HStack {
                                Label("Version", systemImage: "info.circle")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 40)

                            Divider().padding(.vertical, 8)

                            Link(destination: URL(string: "mailto:vansh@trygoldfinch.com")!) {
                                HStack {
                                    Label("Send Feedback", systemImage: "envelope")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(minHeight: 40)
                            }

                            Divider().padding(.vertical, 8)

                            NavigationLink {
                                JournalExportView()
                            } label: {
                                HStack {
                                    Label("Export Progress Journal", systemImage: "doc.richtext")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(minHeight: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.configure(with: modelContext) }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}
