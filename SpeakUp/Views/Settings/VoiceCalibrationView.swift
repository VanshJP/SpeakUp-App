import SwiftUI

struct VoiceCalibrationView: View {
    @Environment(AudioService.self) private var audioService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var onComplete: (VoiceProfile) -> Void

    @State private var phase: CalibrationPhase = .ready
    @State private var errorMessage: String?
    /// The error is a permission iOS holds, so the fix lives in Settings.
    @State private var errorNeedsSettings = false
    @State private var wordTracker = ReadAloudService()
    @State private var lastAutoScrolledIndex = 0
    /// Cleared on disappear, so a start still awaiting permission or the mic
    /// when the sheet goes away backs out instead of recording unseen.
    @State private var isOnScreen = true

    private let passage = "The quick brown fox jumps over the lazy dog. She sells seashells by the seashore. A journey of a thousand miles begins with a single step. Practice makes progress, not perfection."

    private var calibrationPassage: ReadAloudPassage {
        ReadAloudPassage(
            id: "calibration",
            title: "Calibration",
            text: passage,
            difficulty: .easy,
            category: .literature
        )
    }

    private var passageWords: [String] {
        calibrationPassage.words
    }

    enum CalibrationPhase {
        case ready
        case recording
        case analyzing
        case success
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                PageScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        passageCard
                        statusSection
                        actionButtons
                    }
                    .padding(.horizontal, AppLayout.pageHorizontal)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Voice Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The one way out. The in-page button while reading is
                // "Start over", so two different "Cancel"s no longer compete.
                ToolbarItem(placement: .topBarLeading) {
                    if phase != .analyzing {
                        Button(role: .close) {
                            if phase == .recording { cancelCalibration() }
                            dismiss()
                        }
                    }
                }
            }
            .onChange(of: wordTracker.isComplete) { _, isComplete in
                if isComplete && phase == .recording {
                    finishCalibration()
                }
            }
        }
        // The recorder here is the app-wide `AudioService`. A swipe away mid-take
        // used to leave it recording with no end, and the story editor's
        // dictation then found it already running.
        .interactiveDismissDisabled(phase == .recording || phase == .analyzing)
        .onAppear { isOnScreen = true }
        .onDisappear {
            isOnScreen = false
            if phase == .recording { cancelCalibration() }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 12) {
            IconChip(icon: "waveform.and.person.filled", tint: AppColors.primary, size: 56)

            Text(phase == .ready
                 ? "Read the passage below at your natural pace. Big Talk will listen and build your voice profile."
                 : "Read each word aloud. They light up as you go.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var passageCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Read aloud")
                        .eyebrowStyle()
                    Spacer()
                    if phase == .recording {
                        Text("\(wordTracker.currentWordIndex)/\(passageWords.count)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if phase == .recording {
                    progressBar
                    highlightedPassage
                } else {
                    Text(passage)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineSpacing(4)
                }
            }
        }
    }

    /// Determinate progress is a `TickMeter`, the app's one measured bar.
    private var progressBar: some View {
        TickMeter(fraction: wordTracker.progressPercentage, color: AppColors.primary)
            .frame(height: 10)
    }

    private var highlightedPassage: some View {
        ScrollViewReader { proxy in
            WrappingHStack(spacing: 5, lineSpacing: 10) {
                ForEach(Array(passageWords.enumerated()), id: \.offset) { index, word in
                    wordView(word, at: index)
                        .id("cal_word_\(index)")
                }
            }
            .onChange(of: wordTracker.currentWordIndex) { _, newIndex in
                guard abs(newIndex - lastAutoScrolledIndex) >= 2 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo("cal_word_\(max(0, newIndex - 3))", anchor: .center)
                }
                lastAutoScrolledIndex = newIndex
            }
        }
    }

    private func wordView(_ word: String, at index: Int) -> some View {
        let states = wordTracker.wordStates
        let state: WordMatchState = index < states.count ? states[index] : .upcoming

        return Text(word)
            .font(.body.weight(state == .current ? .bold : .regular))
            .foregroundStyle(wordColor(for: state))
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
            .background {
                if state == .current {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.primary.opacity(0.2))
                }
            }
    }

    private func wordColor(for state: WordMatchState) -> Color {
        switch state {
        case .upcoming: return .white.opacity(0.35)
        case .current: return .white
        case .matched: return AppColors.success
        case .skipped, .mismatched: return AppColors.warning
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(spacing: 12) {
            if phase == .recording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppColors.recording)
                        .frame(width: 8, height: 8)
                        .pulsingGlow(color: AppColors.recording, isActive: true)
                    Text("Listening…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if phase == .analyzing {
                VoiceLoader(size: .large)
                    .foregroundStyle(AppColors.primary)
                Text("Analyzing your voice…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if phase == .success {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.success)
                Text("Voice profile created!")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Your profile will improve automatically with every recording you make.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppColors.error)
                    .multilineTextAlignment(.center)

                if errorNeedsSettings {
                    GlassButton(title: "Open Settings", icon: "gear", style: .secondary, size: .small) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
        }
        .frame(minHeight: phase == .ready ? 0 : 80)
        .animation(.easeInOut(duration: 0.3), value: phase == .success)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch phase {
        case .ready:
            GlassButton(title: "Start reading", icon: "mic.fill", style: .primary, size: .large, fullWidth: true) {
                startCalibration()
            }
        case .recording:
            VStack(spacing: 10) {
                if wordTracker.progressPercentage >= 0.6 {
                    GlassButton(title: "Finish early", icon: "checkmark", style: .primary, size: .medium, fullWidth: true) {
                        finishCalibration()
                    }
                }
                GlassButton(title: "Start over", icon: "arrow.counterclockwise", style: .secondary, size: .medium, fullWidth: true) {
                    Haptics.light()
                    cancelCalibration()
                }
            }
        case .analyzing:
            EmptyView()
        case .success:
            GlassButton(title: "Done", icon: "checkmark", style: .primary, size: .large, fullWidth: true) {
                dismiss()
            }
        }
    }

    // MARK: - Actions

    private func startCalibration() {
        errorMessage = nil
        errorNeedsSettings = false
        Haptics.heavy()
        wordTracker.configure(passage: calibrationPassage)
        lastAutoScrolledIndex = 0

        Task {
            let authorized = await wordTracker.requestAuthorization()
            guard authorized else {
                errorMessage = "Big Talk needs speech recognition to follow your reading. Turn it on in Settings."
                errorNeedsSettings = true
                return
            }

            do {
                guard isOnScreen else { return }
                let _ = try await audioService.startRecording()
                guard isOnScreen else {
                    audioService.cancelRecording()
                    return
                }

                try wordTracker.start()
                phase = .recording
            } catch {
                errorMessage = "Couldn't start the microphone. If Big Talk isn't allowed to use it, turn it on in Settings."
                errorNeedsSettings = true
            }
        }
    }

    private func finishCalibration() {
        guard phase == .recording else { return }
        wordTracker.stop()
        phase = .analyzing

        Task {
            // Read once and deleted, so it never goes to iCloud.
            guard let audioURL = await audioService.stopRecording() else {
                errorMessage = "Recording failed. Please try again."
                phase = .ready
                return
            }

            let profile = await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: audioURL) }
                return ConversationIsolationService.extractVoiceProfile(from: audioURL)
            }.value

            if let profile {
                Haptics.success()
                onComplete(profile)
                phase = .success
            } else {
                Haptics.error()
                errorMessage = "Couldn't detect enough voice data. Try speaking louder and closer to the mic."
                phase = .ready
            }
        }
    }

    private func cancelCalibration() {
        wordTracker.stop()
        // Cancel, not stop: a stop kept the file, promoted it to iCloud and
        // never deleted it, so every cancelled calibration left a take behind.
        audioService.cancelRecording()
        phase = .ready
    }
}
