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
    @State private var selectedStage: StoryStage = .spark
    @State private var selectedOccasion: StoryOccasion?
    @State private var isExtractingTags = false
    @State private var newTagValue = ""
    @State private var newTagType: StoryTagType = .topic
    @State private var errorMessage: String?
    @State private var didUseDictation = false
    @State private var isSaving = false
    @State private var isTranscribing = false
    @State private var recordingURL: URL?
    @State private var showTagInput = false

    @FocusState private var focusedField: Field?
    @State private var contentFocused = false

    private enum Field: Hashable {
        case title, tagValue
    }

    private var isEditing: Bool { existingStory != nil }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground(style: .subtle)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        stagePills
                            .padding(.bottom, 12)

                        titleField
                            .padding(.bottom, 4)

                        contentField
                            .padding(.bottom, 16)

                        transcribingBanner
                            .padding(.bottom, 8)

                        tagsArea
                            .id("tags")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: showTagInput) { _, show in
                    if show {
                        withAnimation { proxy.scrollTo("tags", anchor: .bottom) }
                    }
                }
            }

            bottomBar
        }
        .navigationTitle(isEditing ? "Edit" : "New Story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                saveButton
            }
        }
        .onAppear {
            if let story = existingStory {
                title = story.title
                content = story.content
                tags = story.tags
                selectedStage = story.resolvedStage
                selectedOccasion = story.resolvedOccasion
                contentFocused = true
            } else {
                focusedField = .title
            }
        }
        .onDisappear {
            if audioService.isRecording { audioService.cancelRecording() }
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

    // MARK: - Stage Pills

    private var stagePills: some View {
        HStack(spacing: 6) {
            ForEach(StoryStage.allCases) { stage in
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.2)) { selectedStage = stage }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: stage.icon)
                            .font(.system(size: 10, weight: .bold))
                        Text(stage.displayName)
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(selectedStage == stage ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().fill(selectedStage == stage ? stageColor(stage) : .white.opacity(0.06))
                    }
                }
            }

            Spacer()

            occasionMenu
        }
    }

    private var occasionMenu: some View {
        Menu {
            Button {
                selectedOccasion = nil
                Haptics.light()
            } label: {
                HStack {
                    Text("None")
                    if selectedOccasion == nil { Image(systemName: "checkmark") }
                }
            }
            ForEach(StoryOccasion.allCases) { occasion in
                Button {
                    selectedOccasion = occasion
                    Haptics.light()
                } label: {
                    HStack {
                        Label(occasion.rawValue, systemImage: occasion.icon)
                        if selectedOccasion == occasion { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: selectedOccasion?.icon ?? "tag")
                    .font(.system(size: 10, weight: .semibold))
                Text(selectedOccasion?.rawValue ?? "Occasion")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(selectedOccasion != nil ? AppColors.primary : .tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background { Capsule().fill(.white.opacity(0.06)) }
        }
    }

    private func stageColor(_ stage: StoryStage) -> Color {
        switch stage {
        case .spark: return .yellow.opacity(0.8)
        case .draft: return AppColors.primary
        case .polished: return AppColors.success
        }
    }

    // MARK: - Title

    private var titleField: some View {
        TextField("Title", text: $title)
            .font(.title2.weight(.bold))
            .foregroundStyle(.white)
            .focused($focusedField, equals: .title)
            .submitLabel(.next)
            .onSubmit { contentFocused = true }
    }

    // MARK: - Content

    private var contentField: some View {
        DebouncedTextEditor(
            text: $content,
            isDisabled: audioService.isRecording || isTranscribing,
            placeholder: "Start writing…",
            requestFocus: contentFocused
        )
        .frame(minHeight: 220)
    }

    // MARK: - Transcribing Banner

    @ViewBuilder
    private var transcribingBanner: some View {
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
            .padding(12)
            .glassBackground(cornerRadius: 10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if isTranscribing {
            HStack(spacing: 8) {
                ProgressView().tint(AppColors.primary).scaleEffect(0.8)
                Text("Transcribing…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.primary)
                Spacer()
            }
            .padding(12)
            .glassBackground(cornerRadius: 10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Tags

    private var tagsArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty || isExtractingTags {
                tagCloud
            }

            if showTagInput {
                tagInputRow
            }

            tagActionRow
        }
    }

    private var tagCloud: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags) { tag in
                tagChip(tag)
            }
            if isExtractingTags {
                HStack(spacing: 4) {
                    ProgressView().tint(AppColors.primary).scaleEffect(0.6)
                    Text("Tagging…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppColors.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagChip(_ tag: StoryTag) -> some View {
        HStack(spacing: 3) {
            Image(systemName: tag.type.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(tag.value)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    tags.removeAll { $0.id == tag.id }
                }
                Haptics.light()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .foregroundStyle(tagColor(tag.type))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background { Capsule().fill(tagColor(tag.type).opacity(0.15)) }
        .transition(.scale.combined(with: .opacity))
    }

    private var tagInputRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(StoryTagType.allCases) { type in
                    Button {
                        newTagType = type
                        Haptics.light()
                    } label: {
                        Label(type.displayName, systemImage: type.icon)
                    }
                }
            } label: {
                Image(systemName: newTagType.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 28, height: 28)
                    .background { Circle().fill(AppColors.primary.opacity(0.15)) }
            }

            TextField("Add tag…", text: $newTagValue)
                .font(.subheadline)
                .foregroundStyle(.white)
                .focused($focusedField, equals: .tagValue)
                .submitLabel(.done)
                .onSubmit { addManualTag() }

            if !newTagValue.isEmpty {
                Button {
                    addManualTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
        .padding(10)
        .glassBackground(cornerRadius: 10)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var tagActionRow: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.25)) {
                    showTagInput.toggle()
                    if showTagInput { focusedField = .tagValue }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Tag")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background { Capsule().fill(.white.opacity(0.06)) }
            }

            if llmService.isAvailable && !content.isEmpty && !isExtractingTags {
                Button {
                    Task { await extractTags() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("Auto-Tag")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background { Capsule().fill(AppColors.primary.opacity(0.1)) }
                }
            }
        }
    }

    private func tagColor(_ type: StoryTagType) -> Color {
        switch type {
        case .friend: return .blue
        case .date: return .orange
        case .location: return .green
        case .topic: return .purple
        case .custom: return .gray
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            micToggle

            Spacer()

            Text("\(content.split(whereSeparator: \.isWhitespace).count) words")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var micToggle: some View {
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
    }

    // MARK: - Save Button

    @ViewBuilder
    private var saveButton: some View {
        if isSaving {
            ProgressView().tint(AppColors.primary)
        } else {
            Button(isEditing ? "Save" : "Done") {
                saveStory()
            }
            .fontWeight(.semibold)
            .disabled((title.isEmpty && content.isEmpty) || audioService.isRecording || isTranscribing)
            .foregroundStyle(AppColors.primary)
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
        focusedField = nil
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
        focusedField = nil
        contentFocused = false

        Task {
            let method = didUseDictation ? "dictated" : "typed"
            var finalTags = tags

            if finalTags.isEmpty && llmService.isAvailable && !content.isEmpty {
                let extracted = await viewModel.autoExtractTags(from: content, llmService: llmService)
                for tag in extracted where !finalTags.contains(where: { $0.type == tag.type && $0.value.lowercased() == tag.value.lowercased() }) {
                    finalTags.append(tag)
                }
            }

            if let story = existingStory {
                viewModel.updateStory(
                    story,
                    title: title,
                    content: content,
                    tags: finalTags,
                    stage: selectedStage,
                    occasion: selectedOccasion
                )
            } else {
                let resolvedTitle = title.isEmpty ? autoTitle(from: content) : title
                viewModel.createStory(
                    title: resolvedTitle,
                    content: content,
                    tags: finalTags,
                    inputMethod: method,
                    stage: selectedStage,
                    occasion: selectedOccasion
                )
            }

            Haptics.success()
            isSaving = false
            dismiss()
        }
    }

    private func addManualTag() {
        let value = newTagValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        withAnimation(.spring(response: 0.25)) {
            tags.append(StoryTag(type: newTagType, value: value))
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
                for tag in extracted where !tags.contains(where: { $0.type == tag.type && $0.value.lowercased() == tag.value.lowercased() }) {
                    tags.append(tag)
                }
            }
            Haptics.success()
        }
    }

    private func autoTitle(from text: String) -> String {
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
