import SwiftUI
import SwiftData
import UIKit

struct StoryEditorView: View {
    @Bindable var viewModel: StoriesViewModel
    var existingStory: Story?
    var initialFolderId: UUID?
    var onStartPractice: ((Story) -> Void)?
    var onSendToWarmUp: ((Story) -> Void)?
    var onSendToDrill: ((Story) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @Environment(AudioService.self) private var audioService
    @Environment(SpeechService.self) private var speechService

    @Query private var settingsList: [UserSettings]
    private var userSettings: UserSettings? { settingsList.first }

    @State private var title = ""
    @State private var attributedContent: NSAttributedString = NSAttributedString(string: "")
    @State private var plainText = ""
    @State private var tags: [StoryTag] = []
    @State private var selectedStage: StoryStage = .spark
    @State private var selectedOccasion: StoryOccasion?
    @State private var selectedEntryType: StoryEntryType = .story
    @State private var selectedFolderId: UUID?
    @State private var isExtractingTags = false
    @State private var newTagValue = ""
    @State private var newTagType: StoryTagType = .topic
    @State private var errorMessage: String?
    @State private var didUseDictation = false
    @State private var isTranscribing = false
    @State private var recordingURL: URL?
    @State private var showTagInput = false
    @State private var showingMoveSheet = false
    @State private var moveSheetSelectionToken: UUID = UUID()

    // Auto-save
    @State private var draftStory: Story?
    @State private var autoSaveTask: Task<Void, Never>?

    @FocusState private var focusedField: Field?
    @State private var contentFocused = false
    @State private var richTextController = RichTextController()
    @State private var isFormattingDictation = false
    @State private var isDictationTransitioning = false
    @State private var dictationTask: Task<Void, Never>?
    private let dictationFormattingTimeout: Duration = .seconds(12)
    private let dictationTranscriptionTimeout: Duration = .seconds(120)

    private enum Field: Hashable {
        case title, tagValue
    }

    private var isEditing: Bool { existingStory != nil }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    titleField
                    folderChip

                    if !tags.isEmpty || isExtractingTags {
                        tagCloud
                    }

                    contentField
                        .padding(.top, 4)

                    if showTagInput {
                        tagInputRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 8) {
                transcribingBanner
                    .padding(.horizontal, 20)
                bottomBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    finalSave()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            ToolbarItem(placement: .principal) {
                wordCountLabel
            }
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu
            }
        }
        .sheet(isPresented: $showingMoveSheet, onDismiss: {
            syncFolderSelectionFromDraft()
        }) {
            if let story = draftStory ?? existingStory {
                NavigationStack {
                    StoryMoveFolderSheet(viewModel: viewModel, story: story) { folderId in
                        selectedFolderId = folderId
                        moveSheetSelectionToken = UUID()
                    }
                }
                .id(moveSheetSelectionToken)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            viewModel.configure(with: modelContext)
            if let story = existingStory {
                title = story.title
                attributedContent = story.attributedContent
                plainText = story.content
                tags = story.tags
                selectedStage = story.resolvedStage
                selectedOccasion = story.resolvedOccasion
                selectedEntryType = story.resolvedEntryType
                selectedFolderId = story.folderId
                draftStory = story
                contentFocused = true
            } else {
                selectedFolderId = initialFolderId
                contentFocused = true
            }
        }
        .onDisappear {
            autoSaveTask?.cancel()
            dictationTask?.cancel()
            if audioService.isRecording { audioService.cancelRecording() }
            if isTranscribing { isTranscribing = false }
            finalSave()
        }
        .onChange(of: plainText) { _, _ in scheduleAutoSave() }
        .onChange(of: title) { _, _ in scheduleAutoSave() }
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

    private var titleField: some View {
        TextField("Title", text: $title)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(.white)
            .focused($focusedField, equals: .title)
            .submitLabel(.next)
            .onSubmit { contentFocused = true }
    }

    // MARK: - Folder chip

    private var folderChip: some View {
        Button {
            if draftStory == nil && !isEditing {
                // Ensure a draft exists so move sheet can operate
                ensureDraftForMove()
            }
            showingMoveSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: currentFolder?.systemImage ?? "tray.full")
                    .font(.system(size: 11, weight: .semibold))
                Text(currentFolder?.name ?? "All Notes")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(folderColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(folderColor.opacity(0.15))
            }
        }
        .buttonStyle(.plain)
    }

    private var currentFolder: StoryFolder? {
        guard let id = selectedFolderId else { return nil }
        return viewModel.folders.first { $0.id == id }
    }

    private var folderColor: Color {
        if let folder = currentFolder {
            return Color(hex: folder.colorHex)
        }
        return AppColors.primary
    }

    // MARK: - Content

    private var contentField: some View {
        RichTextEditor(
            attributedText: $attributedContent,
            plainText: $plainText,
            controller: richTextController,
            isDisabled: audioService.isRecording || isTranscribing,
            placeholder: placeholder,
            requestFocus: $contentFocused
        )
        .frame(minHeight: 280)
    }

    private var placeholder: String {
        if isEditing { return "Continue writing…" }
        switch selectedEntryType {
        case .reflection: return "How did your practice go?"
        case .note: return "Quick thought…"
        case .story: return "Start writing or tap the mic to dictate…"
        }
    }

    // MARK: - Transcribing banner

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
                Text(isFormattingDictation ? "Formatting…" : "Transcribing…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.primary)
                Spacer()
                Button {
                    cancelDictation()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .accessibilityLabel("Cancel transcription")
            }
            .padding(12)
            .glassBackground(cornerRadius: 10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var wordCountLabel: some View {
        Text("\(plainText.split(whereSeparator: \.isWhitespace).count) words")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
    }

    // MARK: - Tags

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
        VStack(spacing: 0) {
            formatRow
            Divider().opacity(0.3)
            actionRow
        }
        .background(.ultraThinMaterial)
    }

    private var formatRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                formatButton(icon: "bold") { richTextController.bold() }
                formatButton(icon: "italic") { richTextController.italic() }
                formatButton(icon: "underline") { richTextController.underline() }

                Menu {
                    Button {
                        Haptics.light()
                        richTextController.heading()
                    } label: {
                        Label("Heading", systemImage: "textformat.size.larger")
                    }
                    Button {
                        Haptics.light()
                        richTextController.subheading()
                    } label: {
                        Label("Subheading", systemImage: "textformat.size")
                    }
                    Button {
                        Haptics.light()
                        richTextController.bodyStyle()
                    } label: {
                        Label("Body", systemImage: "textformat.size.smaller")
                    }
                } label: {
                    formatIcon("textformat")
                }

                Divider().frame(height: 18).opacity(0.3)

                formatButton(icon: "list.bullet") { richTextController.bulletList() }
                formatButton(icon: "list.number") { richTextController.numberedList() }
                formatButton(icon: "checklist") { richTextController.checklist() }

                Spacer(minLength: 8)

                formatButton(icon: "keyboard.chevron.compact.down") {
                    richTextController.dismissKeyboard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func formatButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            formatIcon(icon)
        }
        .buttonStyle(.plain)
    }

    private func formatIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 36, height: 32)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            micToggle

            tagToggle

            Spacer()

            if llmService.isAvailable && !plainText.isEmpty && !isExtractingTags {
                Button {
                    Task { await extractTags() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text("Auto-tag")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background { Capsule().fill(AppColors.primary.opacity(0.15)) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
        .disabled(isTranscribing || isDictationTransitioning)
    }

    private var tagToggle: some View {
        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.25)) {
                showTagInput.toggle()
                if showTagInput { focusedField = .tagValue }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tag")
                Text("Tag")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background { Capsule().fill(Color.white.opacity(0.06)) }
        }
    }

    // MARK: - More Menu

    private var moreMenu: some View {
        Menu {
            if let story = draftStory ?? existingStory {
                if let onStartPractice {
                    Button {
                        performSave()
                        onStartPractice(story)
                    } label: {
                        Label("Practice This", systemImage: "mic.fill")
                    }
                }
                if let onSendToWarmUp {
                    Button {
                        performSave()
                        onSendToWarmUp(story)
                    } label: {
                        Label("Send to Warm-Up", systemImage: "flame")
                    }
                }
                if let onSendToDrill {
                    Button {
                        performSave()
                        onSendToDrill(story)
                    } label: {
                        Label("Send to Drill", systemImage: "bolt")
                    }
                }

                Divider()
            }

            Button {
                if draftStory == nil { ensureDraftForMove() }
                showingMoveSheet = true
            } label: {
                Label("Move to Folder…", systemImage: "folder")
            }

            Menu {
                ForEach(StoryEntryType.allCases) { type in
                    Button {
                        selectedEntryType = type
                        Haptics.light()
                    } label: {
                        HStack {
                            Label(type.displayName, systemImage: type.icon)
                            if selectedEntryType == type { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label("Type: \(selectedEntryType.displayName)", systemImage: "rectangle.stack")
            }

            Menu {
                ForEach(StoryStage.allCases) { stage in
                    Button {
                        selectedStage = stage
                        Haptics.light()
                    } label: {
                        HStack {
                            Label(stage.displayName, systemImage: stage.icon)
                            if selectedStage == stage { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label("Stage: \(selectedStage.displayName)", systemImage: "flag")
            }

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
                Label(selectedOccasion == nil ? "Occasion" : "Occasion: \(selectedOccasion!.rawValue)", systemImage: "sparkles")
            }

            if let story = draftStory ?? existingStory {
                Divider()
                Button(role: .destructive) {
                    viewModel.deleteStory(story)
                    Haptics.warning()
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.semibold))
        }
    }

    // MARK: - Auto-Save

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            performAutoSave()
        }
    }

    private func performAutoSave() {
        let trimmedContent = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty || !trimmedTitle.isEmpty else { return }

        if let draft = draftStory {
            viewModel.autoSave(draft, title: title, attributed: attributedContent)
        } else {
            ensureDraftForMove()
        }
    }

    /// Create a draft story on demand so it can host tags, folder moves, etc.
    private func ensureDraftForMove() {
        guard draftStory == nil else { return }
        let resolvedTitle = title.isEmpty ? autoTitle(from: plainText) : title
        let method = didUseDictation ? "dictated" : "typed"
        if let story = viewModel.createStory(
            title: resolvedTitle,
            content: plainText,
            inputMethod: method,
            stage: selectedStage,
            entryType: selectedEntryType,
            folderId: selectedFolderId
        ) {
            story.attributedContent = attributedContent
            draftStory = story
        }
    }

    private func performSave() {
        let trimmedContent = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.isEmpty && trimmedTitle.isEmpty { return }

        if draftStory == nil { ensureDraftForMove() }

        guard let draft = draftStory else { return }

        let resolvedTitle = title.isEmpty ? autoTitle(from: plainText) : title
        viewModel.updateStory(
            draft,
            title: resolvedTitle,
            content: plainText,
            tags: tags,
            stage: selectedStage,
            occasion: selectedOccasion
        )
        draft.entryType = selectedEntryType.rawValue
        draft.inputMethod = didUseDictation ? "dictated" : "typed"
        draft.folderId = selectedFolderId
        draft.attributedContent = attributedContent
    }

    private func syncFolderSelectionFromDraft() {
        let latestFolderId = (draftStory ?? existingStory)?.folderId
        guard selectedFolderId != latestFolderId else { return }
        selectedFolderId = latestFolderId
        moveSheetSelectionToken = UUID()
    }

    private func finalSave() {
        autoSaveTask?.cancel()
        let trimmedContent = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let draft = draftStory {
            if trimmedContent.isEmpty && trimmedTitle.isEmpty {
                viewModel.deleteIfEmpty(draft)
            } else {
                performSave()

                if tags.isEmpty && llmService.isAvailable && !plainText.isEmpty {
                    let vm = viewModel
                    let svc = llmService
                    let savedStory = draft
                    let capturedContent = plainText
                    Task.detached { @MainActor in
                        let extracted = await vm.autoExtractTags(from: capturedContent, llmService: svc)
                        guard !extracted.isEmpty else { return }
                        vm.appendTags(to: savedStory, tags: extracted)
                    }
                }
            }
        }
    }

    // MARK: - Recording Actions

    private func toggleRecording() {
        guard !isDictationTransitioning else { return }
        if audioService.isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !isDictationTransitioning else { return }
        isDictationTransitioning = true
        Haptics.heavy()
        didUseDictation = true
        focusedField = nil
        contentFocused = false
        Task {
            defer { isDictationTransitioning = false }
            do {
                let url = try await audioService.startRecording()
                recordingURL = url
            } catch {
                errorMessage = "Could not start recording: \(error.localizedDescription)"
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        guard !isDictationTransitioning else { return }
        isDictationTransitioning = true
        Haptics.medium()
        dictationTask?.cancel()
        dictationTask = Task {
            defer {
                isDictationTransitioning = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    isTranscribing = false
                    isFormattingDictation = false
                }
            }
            guard let url = await audioService.stopRecording() else {
                errorMessage = "Recording failed."
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) { isTranscribing = true }

            do {
                try Task.checkCancellation()
                let biasTerms = buildDictationBiasTerms()
                let rawText = try await transcribeDictationWithTimeout(
                    audioURL: url,
                    preferredTerms: biasTerms
                )
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                try Task.checkCancellation()
                var finalText = rawText
                if !rawText.isEmpty,
                   (userSettings?.autoFormatDictation ?? true),
                   llmService.isAvailable {
                    withAnimation(.easeInOut(duration: 0.2)) { isFormattingDictation = true }
                    let formatted = await formatDictationWithTimeout(rawText)
                    if !formatted.isEmpty {
                        finalText = formatted
                    }
                    withAnimation(.easeInOut(duration: 0.2)) { isFormattingDictation = false }
                }

                try Task.checkCancellation()
                if finalText.isEmpty {
                    errorMessage = "No speech was detected. Try speaking closer to the mic."
                    return
                }

                let parsed: NSAttributedString
                if (userSettings?.autoFormatDictation ?? true), llmService.appleIntelligenceAvailable {
                    parsed = RichTextEditor.attributedString(fromMarkdown: finalText)
                } else {
                    parsed = NSAttributedString(
                        string: finalText,
                        attributes: RichTextEditor.defaultAttributes
                    )
                }

                withAnimation(.easeInOut(duration: 0.2)) {
                    let mutable = NSMutableAttributedString(attributedString: attributedContent)
                    if !plainText.isEmpty {
                        mutable.append(NSAttributedString(
                            string: "\n\n",
                            attributes: RichTextEditor.defaultAttributes
                        ))
                    }
                    mutable.append(parsed)
                    attributedContent = mutable
                    plainText = mutable.string
                }
            } catch is CancellationError {
                // User cancelled — silently clean up
            } catch {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
            }

            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            contentFocused = true
        }
    }

    private func formatDictationWithTimeout(_ rawText: String) async -> String {
        let stream = AsyncStream<String> { continuation in
            let formattingTask = Task {
                let formatted = await llmService.formatDictation(rawText)
                continuation.yield(formatted)
                continuation.finish()
            }

            let timeoutTask = Task {
                try? await Task.sleep(for: dictationFormattingTimeout)
                continuation.yield(rawText)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                formattingTask.cancel()
                timeoutTask.cancel()
            }
        }

        for await value in stream {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? rawText : trimmed
        }

        return rawText
    }

    private func transcribeDictationWithTimeout(
        audioURL: URL,
        preferredTerms: [String]
    ) async throws -> String {
        let stream = AsyncStream<Result<String, Error>> { continuation in
            let transcriptionTask = Task {
                do {
                    let text = try await speechService.transcribeTextOnly(
                        audioURL: audioURL,
                        preferredTerms: preferredTerms
                    )
                    continuation.yield(.success(text))
                    continuation.finish()
                } catch {
                    continuation.yield(.failure(error))
                    continuation.finish()
                }
            }

            let timeoutTask = Task {
                try? await Task.sleep(for: dictationTranscriptionTimeout)
                continuation.yield(
                    .failure(
                        NSError(
                            domain: "StoryEditorView.Dictation",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Dictation transcription timed out."]
                        )
                    )
                )
                continuation.finish()
            }

            continuation.onTermination = { _ in
                transcriptionTask.cancel()
                timeoutTask.cancel()
            }
        }

        for await result in stream {
            return try result.get()
        }

        throw NSError(
            domain: "StoryEditorView.Dictation",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Dictation transcription failed."]
        )
    }

    private func cancelDictation() {
        Haptics.light()
        dictationTask?.cancel()
        dictationTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            isTranscribing = false
            isFormattingDictation = false
        }
    }

    // MARK: - Tag Actions

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

        let extracted = await viewModel.autoExtractTags(from: plainText, llmService: llmService)
        if !extracted.isEmpty {
            withAnimation(.spring(response: 0.3)) {
                for tag in extracted where !tags.contains(where: { $0.type == tag.type && $0.value.lowercased() == tag.value.lowercased() }) {
                    tags.append(tag)
                }
            }
            Haptics.success()
        }
    }

    // MARK: - Helpers

    /// Assemble the bias-term list handed to Whisper for dictation in this editor.
    /// Includes the unified user bias terms (dictation bank + vocab bank + custom fillers)
    /// plus the current story's tag values, so story-specific names/places/people transcribe
    /// consistently across multiple dictation takes. De-duplicated case-insensitively.
    private func buildDictationBiasTerms() -> [String] {
        var terms: [String] = userSettings?.transcriptionBiasTerms ?? []
        terms.append(contentsOf: tags.map { $0.value })
        var seen: Set<String> = []
        var unique: [String] = []
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                unique.append(trimmed)
            }
        }
        return unique
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
