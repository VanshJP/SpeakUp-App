import SwiftUI

struct VoiceCalibrationView: View {
    @Environment(AudioService.self) private var audioService
    @Environment(\.dismiss) private var dismiss
    var onComplete: (VoiceProfile) -> Void

    @State private var phase: CalibrationPhase = .ready
    @State private var errorMessage: String?
    @State private var wordTracker = ReadAloudService()
    @State private var lastAutoScrolledIndex = 0

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

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        passageCard
                        statusSection
                        actionButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .success && phase != .analyzing {
                        Button("Cancel") {
                            if phase == .recording { cancelCalibration() }
                            dismiss()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: wordTracker.isComplete) { _, isComplete in
                if isComplete && phase == .recording {
                    finishCalibration()
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.person.crop")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.primary)

            Text("Voice Calibration")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(phase == .ready
                 ? "Read the passage below at your natural pace. SpeakUp will listen and build your voice profile."
                 : "Read each word aloud — they'll highlight as you go.")
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
                    Label("Read aloud", systemImage: "text.quote")
                        .font(.caption.bold())
                        .foregroundStyle(AppColors.primary)
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

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.primary, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * wordTracker.progressPercentage)
                    .animation(.easeInOut(duration: 0.3), value: wordTracker.progressPercentage)
            }
        }
        .frame(height: 4)
    }

    private var highlightedPassage: some View {
        ScrollViewReader { proxy in
            WrappingHStack(alignment: .leading, spacing: 5, lineSpacing: 10) {
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
            .font(.system(size: 18, weight: state == .current ? .bold : .regular))
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
                    Text("Listening...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if phase == .analyzing {
                ProgressView()
                    .tint(AppColors.primary)
                    .scaleEffect(1.2)
                Text("Analyzing your voice...")
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
            }
        }
        .frame(minHeight: phase == .ready ? 0 : 80)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch phase {
        case .ready:
            GlassButton(title: "Start Reading", icon: "mic.fill", style: .primary, size: .large) {
                startCalibration()
            }
        case .recording:
            if wordTracker.progressPercentage >= 0.6 {
                GlassButton(title: "Finish Early", icon: "checkmark", style: .primary, size: .medium) {
                    finishCalibration()
                }
            }
            GlassButton(title: "Cancel", icon: "xmark", style: .secondary, size: .medium) {
                cancelCalibration()
            }
        case .analyzing:
            EmptyView()
        case .success:
            GlassButton(title: "Done", icon: "checkmark", style: .primary, size: .large) {
                dismiss()
            }
        }
    }

    // MARK: - Actions

    private func startCalibration() {
        errorMessage = nil
        Haptics.heavy()
        wordTracker.configure(passage: calibrationPassage)
        lastAutoScrolledIndex = 0

        Task {
            let authorized = await wordTracker.requestAuthorization()
            guard authorized else {
                errorMessage = "Speech recognition permission is required. Enable it in Settings."
                return
            }

            do {
                // Start audio recording first (for voice profile extraction)
                let _ = try await audioService.startRecording()

                // Start speech recognition for live word tracking
                try wordTracker.start()
                phase = .recording
            } catch {
                errorMessage = "Could not access microphone. Check permissions in Settings."
            }
        }
    }

    private func finishCalibration() {
        guard phase == .recording else { return }
        wordTracker.stop()
        phase = .analyzing

        Task {
            guard let audioURL = await audioService.stopRecording() else {
                errorMessage = "Recording failed. Please try again."
                phase = .ready
                return
            }

            let profile = await Task.detached(priority: .userInitiated) {
                ConversationIsolationService.extractVoiceProfile(from: audioURL)
            }.value

            // Clean up calibration audio
            try? FileManager.default.removeItem(at: audioURL)

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
        Task {
            let _ = await audioService.stopRecording()
            phase = .ready
        }
    }
}
