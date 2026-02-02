import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()
    
    var body: some View {
        settingsList
            .navigationTitle("Settings")
            .listStyle(.insetGrouped)
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
            promptSettingsSection
            reminderSection
            weeklyGoalSection
            exportSection
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
    
    // MARK: - Export Section
    
    private var exportSection: some View {
        Section {
            Picker(selection: $viewModel.exportFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            } label: {
                Label("Video Format", systemImage: "rectangle.ratio.3.to.4")
            }
        } header: {
            Text("Export")
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
            Text("Your recordings and progress are synced to iCloud.")
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
            
            Link(destination: URL(string: "https://github.com")!) {
                Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
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
            .onChange(of: viewModel.exportFormat) { _, _ in
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

