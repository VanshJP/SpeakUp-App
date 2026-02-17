import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()
    @State private var showingCategories = false

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    recordingDefaultsSection
                    analysisFeaturesSection
                    vocabWordBankSection
                    promptSettingsSection
                    reminderSection
                    weeklyGoalSection
                    dataManagementSection
                    aboutSection
                }
                .padding()
            }
        }
        .navigationTitle("Settings")
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.configure(with: modelContext)
        }
        .modifier(SettingsChangeModifiers(viewModel: viewModel))
        .alert("Reset Settings?", isPresented: $viewModel.showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await viewModel.resetSettings() }
            }
        } message: {
            Text("This will reset all settings to their default values.")
        }
        .alert("Add Word", isPresented: $viewModel.showingAddVocabWord) {
            TextField("Enter a word", text: $viewModel.newVocabWord)
                .textInputAutocapitalization(.never)
            Button("Add") { viewModel.addVocabWord() }
            Button("Cancel", role: .cancel) { viewModel.newVocabWord = "" }
        } message: {
            if let error = viewModel.vocabWordError {
                Text(error)
            } else {
                Text("Add a vocabulary word you want to use more.")
            }
        }
        .alert("Clear All Data?", isPresented: $viewModel.showingClearDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Data", role: .destructive) {
                Task { await viewModel.clearAllData() }
            }
        } message: {
            Text("This will permanently delete all your recordings and goals. This action cannot be undone.")
        }
    }

    // MARK: - Recording Defaults Section

    private var recordingDefaultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Session Defaults", systemImage: "slider.horizontal.3")
                .font(.headline)

            GlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Label("Default Duration", systemImage: "clock")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $viewModel.defaultDuration) {
                            ForEach(RecordingDuration.allCases) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.teal)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    HStack {
                        Label("Countdown Timer", systemImage: "timer")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $viewModel.countdownDuration) {
                            ForEach(CountdownDuration.allCases) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.teal)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    HStack {
                        Label("Countdown Style", systemImage: "arrow.up.arrow.down")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $viewModel.countdownStyle) {
                            ForEach(CountdownStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.teal)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    HStack {
                        Label("When Timer Ends", systemImage: "flag.checkered")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $viewModel.timerEndBehavior) {
                            ForEach(TimerEndBehavior.allCases) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.teal)
                    }
                }
            }

            Text("Countdown timer gives you time to prepare. \"Keep Going\" lets you record past the timer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Analysis Features Section

    private var analysisFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Analysis", systemImage: "waveform.badge.magnifyingglass")
                .font(.headline)

            GlassCard {
                VStack(spacing: 0) {
                    Toggle(isOn: $viewModel.trackPauses) {
                        Label("Track Pauses", systemImage: "pause.circle")
                            .font(.subheadline)
                    }
                    .tint(.teal)

                    Divider()
                        .padding(.vertical, 8)

                    Toggle(isOn: $viewModel.trackFillerWords) {
                        Label("Track Filler Words", systemImage: "text.bubble")
                            .font(.subheadline)
                    }
                    .tint(.teal)
                }
            }

            Text("Analyze your speech patterns for pauses and filler words like \"um\", \"uh\", and \"like\".")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Word Bank Section

    private var vocabWordBankSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Word Bank", systemImage: "character.book.closed")
                .font(.headline)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.vocabWords.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "character.book.closed")
                                    .font(.title3)
                                    .foregroundStyle(.tertiary)
                                Text("No words added yet")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            Spacer()
                        }
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(viewModel.vocabWords, id: \.self) { word in
                                HStack(spacing: 4) {
                                    Text(word)
                                        .font(.caption.weight(.medium))
                                    Button {
                                        Haptics.light()
                                        viewModel.removeVocabWord(word)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.teal.opacity(0.15)))
                            }
                        }
                    }

                    Button {
                        viewModel.vocabWordError = nil
                        viewModel.newVocabWord = ""
                        viewModel.showingAddVocabWord = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Add Word")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().strokeBorder(.teal.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Words you want to use more often. They'll be detected and tracked in your recordings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Prompt Settings Section

    private var promptSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Prompts", systemImage: "text.quote")
                .font(.headline)

            GlassCard {
                VStack(spacing: 0) {
                    Toggle(isOn: $viewModel.showDailyPrompt) {
                        Label("Show Daily Prompt", systemImage: "text.quote")
                            .font(.subheadline)
                    }
                    .tint(.teal)

                    Divider()
                        .padding(.vertical, 8)

                    // Categories expandable
                    Button {
                        Haptics.light()
                        withAnimation(.spring(duration: 0.3)) {
                            showingCategories.toggle()
                        }
                    } label: {
                        HStack {
                            Label("Prompt Categories", systemImage: "folder")
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("\(viewModel.enabledPromptCategories.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showingCategories ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)

                    if showingCategories {
                        VStack(spacing: 0) {
                            ForEach(Array(PromptCategory.allCases.enumerated()), id: \.element) { index, category in
                                Divider()
                                    .padding(.vertical, 6)

                                Button {
                                    Haptics.selection()
                                    viewModel.toggleCategory(category)
                                } label: {
                                    HStack {
                                        Image(systemName: category.iconName)
                                            .foregroundStyle(category.color)
                                            .frame(width: 24)

                                        Text(category.displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        if viewModel.isCategoryEnabled(category) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.teal)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .scaleEffect(showingCategories ? 1.05 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showingCategories)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity)
                    }
                }
            }

            Text("Choose which categories of prompts you'd like to practice with.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Reminder Section

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Reminders", systemImage: "bell.fill")
                .font(.headline)

            GlassCard {
                VStack(spacing: 0) {
                    Toggle(isOn: $viewModel.dailyReminderEnabled) {
                        Label("Daily Reminder", systemImage: "bell.fill")
                            .font(.subheadline)
                    }
                    .tint(.teal)

                    if viewModel.dailyReminderEnabled {
                        Divider()
                            .padding(.vertical, 8)

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
                    }
                }
            }

            Text("Get a daily notification to practice your speaking skills.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Weekly Goal Section

    private var weeklyGoalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Goals", systemImage: "target")
                .font(.headline)

            GlassCard {
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
            }

            Text("Set your target number of practice sessions per week.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Data Management Section

    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Data", systemImage: "externaldrive.fill")
                .font(.headline)

            GlassCard {
                VStack(spacing: 0) {
                    Button {
                        Haptics.warning()
                        viewModel.showingResetConfirmation = true
                    } label: {
                        HStack {
                            Label("Reset Settings", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.vertical, 8)

                    Button {
                        Haptics.warning()
                        viewModel.showingClearDataConfirmation = true
                    } label: {
                        HStack {
                            Label("Clear All Data", systemImage: "trash")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Your recordings and progress are stored locally on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("About", systemImage: "info.circle")
                .font(.headline)

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

                    Divider()
                        .padding(.vertical, 8)

                    Link(destination: URL(string: "mailto:support@speakup.app")!) {
                        HStack {
                            Label("Send Feedback", systemImage: "envelope")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Settings Change Modifiers

struct SettingsChangeModifiers: ViewModifier {
    @Bindable var viewModel: SettingsViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.defaultDuration) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.dailyReminderEnabled) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.reminderTime) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.weeklyGoalSessions) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.trackPauses) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.trackFillerWords) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.showDailyPrompt) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.countdownDuration) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.countdownStyle) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.timerEndBehavior) { _, _ in
                Task { await viewModel.saveSettings() }
            }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}

