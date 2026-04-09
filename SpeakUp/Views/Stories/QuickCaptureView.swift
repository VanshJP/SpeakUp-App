import SwiftUI
import SwiftData

struct QuickCaptureView: View {
    @Bindable var viewModel: StoriesViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioService.self) private var audioService
    @Environment(SpeechService.self) private var speechService
    @Environment(LLMService.self) private var llmService

    @State private var title = ""
    @State private var content = ""
    @State private var selectedOccasion: StoryOccasion?
    @State private var isTranscribing = false
    @State private var isSaving = false
    @State private var recordingURL: URL?
    @State private var errorMessage: String?
    @State private var didUseDictation = false
    @State private var selectedEntryType: StoryEntryType = .story

    @FocusState private var titleFocused: Bool
    @State private var contentFocused = false

    var preselectedEntryType: StoryEntryType?

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground(style: .subtle)

            VStack(alignment: .leading, spacing: 0) {
                entryTypePicker
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                TextField("Title", text: $title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .focused($titleFocused)
                    .submitLabel(.next)
                    .onSubmit { contentFocused = true }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)

                statusBanner
                    .padding(.horizontal, 20)

                DebouncedTextEditor(
                    text: $content,
                    isDisabled: audioService.isRecording || isTranscribing,
                    placeholder: placeholder,
                    requestFocus: contentFocused
                )
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
            .padding(.bottom, 64)

            bottomBar
        }
        .navigationTitle("Quick Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                saveToolbarButton
            }
        }
        .onDisappear {
            if audioService.isRecording { audioService.cancelRecording() }
        }
        .onAppear {
            viewModel.configure(with: modelContext)
            if let preselectedEntryType { selectedEntryType = preselectedEntryType }
            contentFocused = true
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

    private var placeholder: String {
        switch selectedEntryType {
        case .reflection: return "How did your practice go?"
        case .note: return "Quick thought…"
        case .story: return "What happened?"
        }
    }

    // MARK: - Entry Type Picker

    private var entryTypePicker: some View {
        HStack(spacing: 6) {
            ForEach(StoryEntryType.allCases) { type in
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.2)) { selectedEntryType = type }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: type.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(type.displayName)
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(selectedEntryType == type ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().fill(selectedEntryType == type ? AppColors.primary.opacity(0.8) : .white.opacity(0.06))
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        if audioService.isRecording {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColors.recording)
                    .frame(width: 8, height: 8)
                    .pulsingGlow(color: AppColors.recording, isActive: true)
                Text("Listening…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.recording)
                Spacer()
                Text(formatDuration(audioService.recordingDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .glassBackground(cornerRadius: 10)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if isTranscribing {
            HStack(spacing: 8) {
                ProgressView().tint(AppColors.primary).scaleEffect(0.8)
                Text("Transcribing…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.primary)
                Spacer()
            }
            .padding(10)
            .glassBackground(cornerRadius: 10)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                toggleRecording()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: audioService.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolEffect(.pulse, isActive: audioService.isRecording)
                    Text(audioService.isRecording ? "Stop" : "Dictate")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(audioService.isRecording ? AppColors.recording : AppColors.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(
                        audioService.isRecording
                            ? AppColors.recording.opacity(0.15)
                            : AppColors.primary.opacity(0.1)
                    )
                }
            }
            .disabled(isTranscribing)

            Spacer()

            if !content.isEmpty || !title.isEmpty {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Button {
                        saveStory()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Save")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background { Capsule().fill(AppColors.primary) }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Save Toolbar Button

    @ViewBuilder
    private var saveToolbarButton: some View {
        if isSaving {
            ProgressView().tint(AppColors.primary)
        } else {
            Button("Save") { saveStory() }
                .foregroundStyle(AppColors.primary)
                .fontWeight(.semibold)
                .disabled(content.isEmpty && title.isEmpty)
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
        didUseDictation = true
        titleFocused = false
        contentFocused = false
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

            withAnimation(.easeInOut(duration: 0.2)) { isTranscribing = true }

            do {
                let transcribedText = try await speechService.transcribeTextOnly(audioURL: url)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !transcribedText.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let separator = content.isEmpty ? "" : "\n\n"
                        content += separator + transcribedText
                    }
                }
            } catch {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
            }

            try? FileManager.default.removeItem(at: url)
            recordingURL = nil

            withAnimation(.easeInOut(duration: 0.2)) { isTranscribing = false }
            contentFocused = true
        }
    }

    private func saveStory() {
        guard !isSaving else { return }
        isSaving = true
        titleFocused = false
        contentFocused = false

        Task {
            let defaultTitle: String
            switch selectedEntryType {
            case .reflection: defaultTitle = "Reflection"
            case .note: defaultTitle = "Note"
            case .story: defaultTitle = generateTitle(from: content)
            }

            let finalTitle = title.isEmpty ? defaultTitle : title

            var autoTags: [StoryTag] = []
            if llmService.isAvailable && !content.isEmpty {
                autoTags = await viewModel.autoExtractTags(from: content, llmService: llmService)
            }

            let result = viewModel.createStory(
                title: finalTitle,
                content: content,
                tags: autoTags,
                inputMethod: didUseDictation ? "dictated" : "typed",
                stage: selectedEntryType == .story ? .spark : .polished,
                occasion: selectedOccasion,
                entryType: selectedEntryType
            )

            isSaving = false
            if result != nil {
                Haptics.success()
                dismiss()
            } else {
                Haptics.error()
                errorMessage = viewModel.errorMessage ?? "Failed to save"
            }
        }
    }

    private func generateTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(6).joined(separator: " ")
        if words.count > 40 { return String(words.prefix(40)) + "…" }
        return words.isEmpty ? "Untitled" : words
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
