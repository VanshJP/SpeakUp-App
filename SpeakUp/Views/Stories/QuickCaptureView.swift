import SwiftUI

struct QuickCaptureView: View {
    @Bindable var viewModel: StoriesViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioService.self) private var audioService
    @Environment(SpeechService.self) private var speechService

    @State private var title = ""
    @State private var content = ""
    @State private var selectedOccasion: StoryOccasion?
    @State private var isTranscribing = false
    @State private var recordingURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            VStack(spacing: 20) {
                TextField("Story title (optional)", text: $title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                contentArea
                    .padding(.horizontal, 20)

                occasionPicker
                    .padding(.horizontal, 20)

                Spacer()

                bottomActions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .navigationTitle("Quick Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveStory()
                }
                .foregroundStyle(AppColors.primary)
                .disabled(content.isEmpty && title.isEmpty)
            }
        }
        .onDisappear {
            if audioService.isRecording {
                audioService.cancelRecording()
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 12) {
            if isTranscribing {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(AppColors.primary)
                        .scaleEffect(0.8)
                    Text("Transcribing...")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.primary)
                    Spacer()
                }
                .padding(14)
                .glassBackground(cornerRadius: 12)
            } else if audioService.isRecording {
                HStack(spacing: 12) {
                    Circle()
                        .fill(AppColors.recording)
                        .frame(width: 10, height: 10)
                        .pulsingGlow(color: AppColors.recording, isActive: true)

                    Text("Listening...")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.recording)

                    Spacer()

                    Text(formatDuration(audioService.recordingDuration))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .glassBackground(cornerRadius: 12)
            }

            if !content.isEmpty || (!audioService.isRecording && !isTranscribing) {
                DebouncedTextEditor(
                    text: $content,
                    isDisabled: audioService.isRecording || isTranscribing,
                    placeholder: "Start typing or tap the mic below..."
                )
                .frame(minHeight: 100, maxHeight: 180)
                .padding(14)
                .glassBackground(cornerRadius: 12)
            }
        }
    }

    // MARK: - Occasion Picker

    private var occasionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StoryOccasion.allCases) { occasion in
                    Button {
                        Haptics.light()
                        selectedOccasion = selectedOccasion == occasion ? nil : occasion
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: occasion.icon)
                            Text(occasion.rawValue)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(selectedOccasion == occasion ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule().fill(selectedOccasion == occasion ? AppColors.primary : .ultraThinMaterial)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        HStack(spacing: 16) {
            Button {
                toggleRecording()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: audioService.isRecording ? "stop.fill" : "mic.fill")
                        .font(.body.weight(.semibold))
                        .symbolEffect(.pulse, isActive: audioService.isRecording)
                    Text(audioService.isRecording ? "Stop" : "Dictate")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(audioService.isRecording ? AppColors.recording : AppColors.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    Capsule().fill(
                        audioService.isRecording
                            ? AppColors.recording.opacity(0.15)
                            : AppColors.primary.opacity(0.15)
                    )
                }
            }
            .disabled(isTranscribing)

            if !content.isEmpty || !title.isEmpty {
                GlassButton(title: "Save", icon: "checkmark", style: .primary) {
                    saveStory()
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if audioService.isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Haptics.heavy()
        Task {
            do {
                let url = try await audioService.startRecording()
                recordingURL = url
            } catch {
                errorMessage = "Could not start recording: \(error.localizedDescription)"
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        Haptics.medium()
        Task {
            guard let url = await audioService.stopRecording() else {
                errorMessage = "Recording failed."
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                isTranscribing = true
            }

            do {
                let transcribedText = try await speechService.transcribeTextOnly(audioURL: url)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !transcribedText.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let separator = content.isEmpty ? "" : "\n\n"
                        content = content + separator + transcribedText
                    }
                }
            } catch {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
            }

            try? FileManager.default.removeItem(at: url)
            recordingURL = nil

            withAnimation(.easeInOut(duration: 0.2)) {
                isTranscribing = false
            }
        }
    }

    private func saveStory() {
        let finalTitle = title.isEmpty
            ? generateTitle(from: content)
            : title

        viewModel.createStory(
            title: finalTitle,
            content: content,
            tags: [],
            inputMethod: content.isEmpty ? "typed" : (recordingURL != nil ? "dictated" : "typed"),
            stage: .spark,
            occasion: selectedOccasion
        )

        Haptics.success()
        dismiss()
    }

    private func generateTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(6).joined(separator: " ")
        if words.count > 40 {
            return String(words.prefix(40)) + "…"
        }
        return words.isEmpty ? "Untitled Spark" : words
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
