import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    @State private var viewModel = RecordingViewModel()
    @State private var selectedFramework: SpeechFramework?
    @State private var showFrameworkPicker = false
    @State private var showingVocabOverlay = false
    @Query private var goals: [UserGoal]

    let prompt: Prompt?
    let duration: RecordingDuration
    var timerEndBehavior: TimerEndBehavior = .saveAndStop
    var countdownStyle: CountdownStyle = .countUp
    var goalId: UUID? = nil
    var eventId: UUID? = nil
    var scriptVersionId: UUID? = nil
    let onComplete: (Recording) -> Void
    let onCancel: () -> Void

    private var selectedGoal: UserGoal? {
        guard let goalId else { return nil }
        return goals.first { $0.id == goalId }
    }

    var body: some View {
        ZStack {
            // Background
            audioBackground

            // Content Overlay
            VStack(spacing: 0) {
                // Top Bar
                topBar

                Spacer()

                // Center Content (Timer)
                centerContent

                Spacer()

                // Bottom Controls
                bottomControls
            }
            .padding()

            // Vocab words floating overlay
            if showingVocabOverlay, let vocabWords = userSettings.first?.vocabWords, !vocabWords.isEmpty {
                VocabOverlayPanel(words: vocabWords) {
                    withAnimation(.spring(response: 0.3)) {
                        showingVocabOverlay = false
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .ignoresSafeArea()
        .task {
            viewModel.configure(
                with: modelContext,
                prompt: prompt,
                duration: duration,
                timerEndBehavior: timerEndBehavior,
                countdownStyle: countdownStyle
            )
            viewModel.goalId = goalId
            viewModel.eventId = eventId
            viewModel.scriptVersionId = scriptVersionId
            if let settings = userSettings.first {
                viewModel.fillerConfig = FillerWordConfig(
                    customFillers: Set(settings.customFillerWords),
                    customContextFillers: Set(settings.customContextFillerWords),
                    removedDefaults: Set(settings.removedDefaultFillers)
                )
            }
            await viewModel.checkPermissions()
            // Auto-start recording after countdown
            if !viewModel.isRecording {
                await viewModel.startRecording()
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .onChange(of: viewModel.autoSavedRecording) { _, recording in
            if let recording {
                onComplete(recording)
            }
        }
        .alert("Permission Required", isPresented: $viewModel.showingPermissionAlert) {
            Button("Cancel") { onCancel() }
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(viewModel.permissionAlertMessage)
        }
    }

    // MARK: - Audio Background

    private var audioBackground: some View {
        AppBackground(style: .recording)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                // Close button
                Button {
                    Haptics.warning()
                    if viewModel.isRecording {
                        viewModel.cancelRecording()
                    }
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                        }
                }

                Spacer()

                // Framework picker button
                Menu {
                    Button("None") {
                        selectedFramework = nil
                    }
                    ForEach(SpeechFramework.allCases) { framework in
                        Button {
                            selectedFramework = framework
                        } label: {
                            Label(framework.displayName, systemImage: framework.icon)
                        }
                    }
                } label: {
                    Image(systemName: selectedFramework?.icon ?? "list.bullet.rectangle")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                        }
                }

                // Goal badge (if goal selected)
                if let goal = selectedGoal {
                    HStack(spacing: 4) {
                        Image(systemName: goal.type.iconName)
                            .font(.caption2.weight(.semibold))
                        Text(goal.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule()
                                    .strokeBorder(.teal.opacity(0.3), lineWidth: 0.5)
                            }
                    }
                }

                // Vocab overlay button (only if user has vocab words)
                if let vocabWords = userSettings.first?.vocabWords, !vocabWords.isEmpty {
                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.3)) {
                            showingVocabOverlay.toggle()
                        }
                    } label: {
                        Image(systemName: "character.book.closed")
                            .font(.body.weight(.medium))
                            .foregroundStyle(showingVocabOverlay ? .teal : .white)
                            .frame(width: 36, height: 36)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                            }
                    }
                }

                // Voice activity indicator (top right)
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.audioLevel > -40 ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.15), value: viewModel.audioLevel > -40)

                    Text(viewModel.audioLevel > -40 ? "Speaking" : "Silent")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(viewModel.audioLevel > -40 ? .white : .white.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }

            // Compact prompt card at top (during recording)
            if let prompt, viewModel.isRecording {
                compactPromptCard(prompt)
            }
        }
        .padding(.top, 50)
    }

    private func compactPromptCard(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prompt.category)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))

            Text(prompt.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial.opacity(0.8))
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Center Content

    private var centerContent: some View {
        VStack(spacing: 24) {
            // Framework overlay
            if let framework = selectedFramework, viewModel.isRecording {
                FrameworkOverlayView(
                    framework: framework,
                    elapsedTime: viewModel.recordingDuration,
                    totalDuration: TimeInterval(duration.seconds)
                )
            }

            // Timer
            TimerView(
                remainingTime: viewModel.displayTime,
                totalTime: TimeInterval(duration.seconds),
                progress: viewModel.progress,
                color: viewModel.timerColor,
                isRecording: viewModel.isRecording,
                isOvertime: viewModel.isOvertime,
                timerLabel: viewModel.timerLabel
            )

            // Prompt Card (if available) - show only before recording starts
            if let prompt, !viewModel.isRecording {
                promptCard(prompt)
            }
        }
    }

    private func promptCard(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(prompt.category)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text(prompt.difficulty.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(AppColors.difficultyColor(prompt.difficulty).opacity(0.3))
                    }
                    .foregroundStyle(AppColors.difficultyColor(prompt.difficulty))
            }

            Text(prompt.text)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
        .padding(.horizontal)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 24) {
            // Live filler counter
            if viewModel.isRecording {
                FillerCounterOverlay(count: viewModel.liveFillerCount)
            }

            // Record Button with circular waveform
            ZStack {
                // Circular waveform around button
                if viewModel.isRecording {
                    CircularWaveformView(audioLevel: viewModel.audioLevel)
                }

                RecordButton(
                    isRecording: viewModel.isRecording,
                    onTap: {
                        Task {
                            if viewModel.isRecording {
                                if let recording = await viewModel.stopRecording() {
                                    onComplete(recording)
                                }
                            } else {
                                await viewModel.startRecording()
                            }
                        }
                    }
                )
            }

            // Hint text
            if !viewModel.isRecording {
                Text("Tap to start recording")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text("Tap to stop")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.bottom, 40)
    }
}

// MARK: - Circular Waveform View (surrounds record button)

struct CircularWaveformView: View {
    let audioLevel: Float
    private let barCount = 48
    private let baseRadius: CGFloat = 70  // Just outside the record button

    @State private var barHeights: [CGFloat] = Array(repeating: 0.15, count: 48)

    var body: some View {
        ZStack {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    height: barHeights[index],
                    index: index,
                    totalBars: barCount,
                    baseRadius: baseRadius
                )
            }
        }
        .frame(width: 200, height: 200)
        .onChange(of: audioLevel) { _, newLevel in
            updateBars(level: newLevel)
        }
    }

    private func updateBars(level: Float) {
        // Convert dB level (-60 to 0 range for speech) to normalized value (0 to 1)
        let normalizedLevel = max(0, min(1, (level + 60) / 60))

        withAnimation(.easeOut(duration: 0.08)) {
            for i in 0..<barCount {
                // Create variation across bars for organic look
                let variation = CGFloat.random(in: 0.7...1.3)
                let waveOffset = sin(Double(i) * 0.3 + Date().timeIntervalSince1970 * 3) * 0.2
                let height = CGFloat(normalizedLevel) * variation * 0.8 + 0.15 + waveOffset
                barHeights[i] = min(1.0, max(0.1, height))
            }
        }
    }
}

private struct WaveformBar: View {
    let height: CGFloat
    let index: Int
    let totalBars: Int
    let baseRadius: CGFloat

    private let maxBarHeight: CGFloat = 35
    private let barWidth: CGFloat = 3

    var body: some View {
        let angle = (Double(index) / Double(totalBars)) * 360

        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color.teal, Color.cyan],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: barWidth, height: maxBarHeight * height)
            .offset(y: -(baseRadius + (maxBarHeight * height) / 2))
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Vocab Overlay Panel

struct VocabOverlayPanel: View {
    let words: [String]
    let onDismiss: () -> Void

    @State private var autoHideTask: Task<Void, Never>?

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Your Words", systemImage: "character.book.closed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                FlowLayout(spacing: 6) {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                Capsule()
                                    .fill(.teal.opacity(0.2))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(.teal.opacity(0.3), lineWidth: 0.5)
                                    }
                            }
                    }
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 110)

            Spacer()
        }
        .onTapGesture { onDismiss() }
        .onAppear {
            autoHideTask = Task {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await MainActor.run { onDismiss() }
            }
        }
        .onDisappear {
            autoHideTask?.cancel()
        }
    }
}

#Preview {
    RecordingView(
        prompt: nil,
        duration: .sixty,
        onComplete: { _ in },
        onCancel: {}
    )
    .modelContainer(for: [Recording.self, Prompt.self, UserSettings.self], inMemory: true)
}
