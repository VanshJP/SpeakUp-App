import SwiftUI

struct StoryEditorView: View {
    @Bindable var viewModel: StoriesViewModel
    var existingStory: Story?

    @Environment(\.dismiss) private var dismiss
    @Environment(LLMService.self) private var llmService
    @Environment(AudioService.self) private var audioService
    @Environment(SpeechService.self) private var speechService

    @State private var title = ""
    @State private var content = ""
    @State private var tags: [StoryTag] = []
    @State private var isExtractingTags = false
    @State private var newTagType: StoryTagType = .custom
    @State private var newTagValue = ""
    @State private var errorMessage: String?
    @State private var didUseDictation = false
    @State private var isSaving = false
    @State private var isFormattingText = false
    @State private var showFormatOption = false
    @State private var isTranscribing = false
    @State private var recordingURL: URL?

    private var isEditing: Bool { existingStory != nil }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    titleSection
                    contentSection
                    tagsManagementSection
                    autoExtractSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(isEditing ? "Edit Story" : "New Story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                        .tint(AppColors.primary)
                } else {
                    Button(isEditing ? "Save" : "Create") {
                        saveStory()
                    }
                    .disabled((title.isEmpty && content.isEmpty) || audioService.isRecording || isTranscribing)
                    .foregroundStyle(AppColors.primary)
                }
            }
        }
        .onAppear {
            if let story = existingStory {
                title = story.title
                content = story.content
                tags = story.tags
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

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader("Title", icon: "textformat")

            TextField("Story title...", text: $title)
                .font(.body)
                .foregroundStyle(.white)
                .padding(14)
                .glassBackground(cornerRadius: 12)
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader("Content", icon: "doc.text")

            TextEditor(text: $content)
                .font(.body)
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
                .padding(14)
                .glassBackground(cornerRadius: 12)
                .disabled(audioService.isRecording || isTranscribing)
                .overlay(alignment: .bottomTrailing) {
                    if !audioService.isRecording && !isTranscribing && content.isEmpty {
                        Text("Type your story or tap the mic to dictate...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(20)
                            .allowsHitTesting(false)
                    }
                }

            transcribingIndicator

            formatTextBanner

            dictationControls
        }
    }

    // MARK: - Transcribing Indicator

    @ViewBuilder
    private var transcribingIndicator: some View {
        if audioService.isRecording {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppColors.recording)
                    .frame(width: 8, height: 8)
                    .pulsingGlow(color: AppColors.recording, isActive: true)

                Text("Recording...")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.recording)

                Spacer()

                Text(formatDuration(audioService.recordingDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassBackground(cornerRadius: 10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if isTranscribing {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(AppColors.primary)
                    .scaleEffect(0.8)

                Text("Transcribing with Whisper...")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.primary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassBackground(cornerRadius: 10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Format Text Banner

    @ViewBuilder
    private var formatTextBanner: some View {
        if showFormatOption && llmService.isAvailable && !content.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppColors.primary)

                Text("Format dictated text?")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    Task { await formatText() }
                } label: {
                    Text(isFormattingText ? "Formatting..." : "Format")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                }
                .disabled(isFormattingText)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFormatOption = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassBackground(cornerRadius: 10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Dictation Controls

    private var dictationControls: some View {
        HStack {
            Spacer()

            micButton(tint: AppColors.primary)
        }
    }

    private func micButton(tint: Color) -> some View {
        Button {
            toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(audioService.isRecording ? tint.opacity(0.25) : .white.opacity(0.06))
                    .overlay {
                        Circle()
                            .strokeBorder(
                                audioService.isRecording ? tint.opacity(0.6) : .white.opacity(0.1),
                                lineWidth: 0.5
                            )
                    }
                    .frame(width: 40, height: 40)

                Image(systemName: audioService.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(audioService.isRecording ? tint : .white.opacity(0.5))
                    .symbolEffect(.pulse, isActive: audioService.isRecording)
            }
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing)
    }

    // MARK: - Tags

    private var tagsManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Tags", icon: "tag")

            if !tags.isEmpty {
                GlassCard {
                    FlowLayout(spacing: 8) {
                        ForEach(tags) { tag in
                            StoryTagPill(tag: tag) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    tags.removeAll { $0.id == tag.id }
                                }
                            }
                        }
                    }
                }
            }

            GlassCard {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(StoryTagType.allCases) { type in
                                Button {
                                    newTagType = type
                                } label: {
                                    Label(type.displayName, systemImage: type.icon)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: newTagType.icon)
                                Text(newTagType.displayName)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                Capsule().fill(AppColors.primary.opacity(0.15))
                            }
                        }

                        TextField("Tag value...", text: $newTagValue)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .onSubmit { addManualTag() }

                        Button {
                            addManualTag()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(newTagValue.isEmpty ? .secondary : AppColors.primary)
                        }
                        .disabled(newTagValue.isEmpty)
                    }
                }
            }
        }
    }

    private var autoExtractSection: some View {
        Group {
            if llmService.isAvailable && !content.isEmpty {
                GlassButton(
                    title: isExtractingTags ? "Extracting..." : "Extract Tags Now",
                    icon: "sparkles",
                    style: .secondary,
                    size: .medium
                ) {
                    Task { await extractTags() }
                }
                .disabled(isExtractingTags || content.isEmpty)
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
        didUseDictation = true
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
                let result = try await speechService.transcribe(audioURL: url)
                let transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

                if !transcribedText.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let separator = content.isEmpty ? "" : "\n\n"
                        content = content + separator + transcribedText
                    }

                    // Offer formatting if LLM is available
                    if llmService.isAvailable {
                        withAnimation(.spring(response: 0.3)) {
                            showFormatOption = true
                        }
                    }
                }
            } catch {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
            }

            // Clean up temp recording file
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil

            withAnimation(.easeInOut(duration: 0.2)) {
                isTranscribing = false
            }
        }
    }

    private func saveStory() {
        guard !isSaving else { return }
        isSaving = true

        Task {
            let method = didUseDictation ? "dictated" : "typed"
            var finalTags = tags

            // Auto-extract tags if LLM is available
            if llmService.isAvailable && !content.isEmpty {
                let extracted = await viewModel.autoExtractTags(from: content, llmService: llmService)
                for tag in extracted {
                    if !finalTags.contains(where: { $0.type == tag.type && $0.value.lowercased() == tag.value.lowercased() }) {
                        finalTags.append(tag)
                    }
                }
            }

            if let story = existingStory {
                viewModel.updateStory(story, title: title, content: content, tags: finalTags)
            } else {
                viewModel.createStory(title: title, content: content, tags: finalTags, inputMethod: method)
            }

            Haptics.success()
            isSaving = false
            dismiss()
        }
    }

    private func addManualTag() {
        let value = newTagValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        let tag = StoryTag(type: newTagType, value: value)
        withAnimation(.easeInOut(duration: 0.2)) {
            tags.append(tag)
        }
        newTagValue = ""
        Haptics.light()
    }

    private func extractTags() async {
        isExtractingTags = true
        defer { isExtractingTags = false }

        let extracted = await viewModel.autoExtractTags(from: content, llmService: llmService)
        if !extracted.isEmpty {
            withAnimation(.spring(response: 0.3)) {
                for tag in extracted {
                    if !tags.contains(where: { $0.type == tag.type && $0.value.lowercased() == tag.value.lowercased() }) {
                        tags.append(tag)
                    }
                }
            }
            Haptics.success()
        }
    }

    private func formatText() async {
        isFormattingText = true
        defer { isFormattingText = false }

        if let formatted = await viewModel.formatDictatedText(content, llmService: llmService) {
            withAnimation(.easeInOut(duration: 0.2)) {
                content = formatted
                showFormatOption = false
            }
            Haptics.success()
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
