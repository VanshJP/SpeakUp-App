import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()
    @State private var showingCategories = false
    @State private var isWordBankExpanded = false
    @FocusState private var isWordInputFocused: Bool

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)
                .ignoresSafeArea(.keyboard)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        recordingDefaultsSection
                        analysisFeaturesSection
                        vocabWordBankSection
                            .id("wordBank")
                        promptSettingsSection
                        reminderSection
                        weeklyGoalSection
                        dataManagementSection
                        aboutSection
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: isWordInputFocused) { _, focused in
                    if focused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo("wordBank", anchor: .top)
                            }
                        }
                    }
                }
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

                    Divider()
                        .padding(.vertical, 8)

                    Toggle(isOn: $viewModel.hapticCoachingEnabled) {
                        Label("Haptic Coaching", systemImage: "hand.tap")
                            .font(.subheadline)
                    }
                    .tint(.teal)

                    Divider()
                        .padding(.vertical, 8)

                    Toggle(isOn: $viewModel.chirpSoundEnabled) {
                        Label("Audio Cues", systemImage: "speaker.wave.2")
                            .font(.subheadline)
                    }
                    .tint(.teal)
                }
            }

            Text("Countdown timer gives you time to prepare. \"Keep Going\" lets you record past the timer. Haptic coaching gives gentle vibrations for long silences, fillers, or pace changes. Audio cues play short chirps during warm-ups and drills.")
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
                        wordBankEmptyState
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(viewModel.vocabWords, id: \.self) { word in
                                wordBankChip(word)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    wordBankInputField
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = viewModel.vocabWordError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Text("Words you want to use more often. They'll be detected and tracked in your recordings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.vocabWordError)
        .animation(.spring(duration: 0.25), value: viewModel.vocabWords)
    }

    private var wordBankEmptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.15))

            Text("No words yet")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func wordBankChip(_ word: String) -> some View {
        HStack(spacing: 5) {
            Text(word)
                .font(.caption.weight(.medium))

            Button {
                Haptics.light()
                withAnimation(.spring(duration: 0.25)) {
                    viewModel.removeVocabWord(word)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.teal.opacity(0.15))
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var wordBankInputField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.teal)

            TextField("Add a word...", text: $viewModel.newVocabWord)
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(.teal)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isWordInputFocused)
                .submitLabel(.done)
                .onSubmit {
                    viewModel.addVocabWord()
                    if !viewModel.vocabWords.isEmpty && viewModel.vocabWordError == nil {
                        isWordInputFocused = true
                    }
                }

            if !viewModel.newVocabWord.isEmpty {
                Button {
                    viewModel.newVocabWord = ""
                    viewModel.vocabWordError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.white.opacity(0.06))
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                }
        }
    }

    // MARK: - Prompt Settings Section

    private var promptSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Prompts", systemImage: "text.quote")
                .font(.headline)

            GlassCard {
                VStack(spacing: 0) {
                    Toggle(isOn: $viewModel.hideAnsweredPrompts) {
                        Label("Hide Answered Prompts", systemImage: "checkmark.circle")
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

            Text("Hide answered prompts to always get fresh topics. Choose which categories you'd like to practice with.")
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

                    Divider()
                        .padding(.vertical, 8)

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
                    }
                    .buttonStyle(.plain)
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
            .modifier(SettingsChangeModifiersA(viewModel: viewModel))
            .modifier(SettingsChangeModifiersB(viewModel: viewModel))
    }
}

private struct SettingsChangeModifiersA: ViewModifier {
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
    }
}

private struct SettingsChangeModifiersB: ViewModifier {
    @Bindable var viewModel: SettingsViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.countdownDuration) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.countdownStyle) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.timerEndBehavior) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.hapticCoachingEnabled) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.chirpSoundEnabled) { _, _ in
                Task { await viewModel.saveSettings() }
            }
            .onChange(of: viewModel.hideAnsweredPrompts) { _, _ in
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

