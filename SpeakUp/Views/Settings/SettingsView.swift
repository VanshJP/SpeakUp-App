import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()
    
    var body: some View {
        settingsList
            .navigationTitle("Settings")
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .appBackground(.subtle)
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

    private var settingsList: some View {
        List {
            recordingDefaultsSection
            analysisFeaturesSection
            vocabWordBankSection
            promptSettingsSection
            reminderSection
            weeklyGoalSection
            dataManagementSection
            aboutSection
        }
    }
    
    // MARK: - Recording Defaults Section

    private var recordingDefaultsSection: some View {
        Section {
            // Duration Picker
            HStack {
                Label("Default Duration", systemImage: "clock")
                Spacer()
                Picker("", selection: $viewModel.defaultDuration) {
                    ForEach(RecordingDuration.allCases) { duration in
                        Text(duration.displayName).tag(duration)
                    }
                }
                .pickerStyle(.menu)
            }

            // Countdown Duration Picker
            HStack {
                Label("Countdown Timer", systemImage: "timer")
                Spacer()
                Picker("", selection: $viewModel.countdownDuration) {
                    ForEach(CountdownDuration.allCases) { duration in
                        Text(duration.displayName).tag(duration)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("Default Session Settings")
        } footer: {
            Text("Countdown timer gives you time to prepare before recording starts.")
        }
    }
    
    // MARK: - Analysis Features Section
    
    private var analysisFeaturesSection: some View {
        Section {
            Toggle(isOn: $viewModel.trackPauses) {
                Label("Track Pauses", systemImage: "pause.circle")
            }
            .tint(.teal)
            
            Toggle(isOn: $viewModel.trackFillerWords) {
                Label("Track Filler Words", systemImage: "text.bubble")
            }
            .tint(.teal)
        } header: {
            Text("Analysis Features")
        } footer: {
            Text("These features analyze your speech patterns to provide feedback on pauses and filler words like \"um\", \"uh\", and \"like\".")
        }
    }
    
    // MARK: - Word Bank Section

    private var vocabWordBankSection: some View {
        Section {
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
                    .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.vocabWords, id: \.self) { word in
                        HStack(spacing: 4) {
                            Text(word)
                                .font(.caption.weight(.medium))
                            Button {
                                viewModel.removeVocabWord(word)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(.teal)
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
        } header: {
            Text("Word Bank")
        } footer: {
            Text("Add vocabulary words you want to use more often. They'll be detected in your recordings and tracked as positive progress.")
        }
    }

    // MARK: - Prompt Settings Section
    
    private var promptSettingsSection: some View {
        Section {
            Toggle(isOn: $viewModel.showDailyPrompt) {
                Label("Show Daily Prompt", systemImage: "text.quote")
            }
            .tint(.teal)
            
            // Prompt Categories
            DisclosureGroup {
                ForEach(PromptCategory.allCases, id: \.self) { category in
                    Button {
                        viewModel.toggleCategory(category)
                    } label: {
                        HStack {
                            Image(systemName: category.iconName)
                                .foregroundStyle(category.color)
                                .frame(width: 24)
                            
                            Text(category.displayName)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            if viewModel.isCategoryEnabled(category) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.teal)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Label("Prompt Categories", systemImage: "folder")
                    Spacer()
                    Text("\(viewModel.enabledPromptCategories.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Prompt Settings")
        } footer: {
            Text("Choose which categories of prompts you'd like to practice with.")
        }
    }
    
    // MARK: - Reminder Section
    
    private var reminderSection: some View {
        Section {
            Toggle(isOn: $viewModel.dailyReminderEnabled) {
                Label("Daily Reminder", systemImage: "bell.fill")
            }
            .tint(.teal)
            
            if viewModel.dailyReminderEnabled {
                DatePicker(
                    "Reminder Time",
                    selection: $viewModel.reminderTime,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Get a daily notification to practice your speaking skills.")
        }
    }
    
    // MARK: - Weekly Goal Section
    
    private var weeklyGoalSection: some View {
        Section {
            Stepper(value: $viewModel.weeklyGoalSessions, in: 1...14) {
                HStack {
                    Label("Weekly Goal", systemImage: "target")
                    Spacer()
                    Text("\(viewModel.weeklyGoalSessions) sessions")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Goals")
        } footer: {
            Text("Set your target number of practice sessions per week.")
        }
    }
    
    // MARK: - Data Management Section
    
    private var dataManagementSection: some View {
        Section {
            Button {
                viewModel.showingResetConfirmation = true
            } label: {
                Label("Reset Settings", systemImage: "arrow.counterclockwise")
            }
            
            Button(role: .destructive) {
                viewModel.showingClearDataConfirmation = true
            } label: {
                Label("Clear All Data", systemImage: "trash")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Your recordings and progress are stored locally on this device.")
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                    .foregroundStyle(.secondary)
            }
            
            Link(destination: URL(string: "mailto:support@speakup.app")!) {
                Label("Send Feedback", systemImage: "envelope")
            }
        } header: {
            Text("About")
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
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}

