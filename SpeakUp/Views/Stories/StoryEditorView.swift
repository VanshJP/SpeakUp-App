import SwiftUI
import SwiftData
import UIKit

struct StoryEditorView: View {
    @Bindable var viewModel: StoriesViewModel
    var existingStory: Story?
    var initialFolderId: UUID?
    /// Called once when the editor closes having created a story that
    /// survives (not emptied). The Library pushes that story's page, where
    /// Practice / Warm up / Drill live: this sheet cannot start them itself,
    /// because ContentView's session cover cannot present over a sheet.
    var onCreated: ((Story) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LLMService.self) private var llmService
    @Environment(AudioService.self) private var audioService
    @Environment(SpeechService.self) private var speechService

    @Query private var settingsList: [UserSettings]
    private var userSettings: UserSettings? { settingsList.first }

    @State private var title = ""
    @State private var showingDeleteConfirm = false
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
    @State private var showTagInput = false
    @State private var showingMoveSheet = false
    @State private var moveSheetSelectionToken: UUID = UUID()

    @State private var draftStory: Story?
    @State private var autoSaveTask: Task<Void, Never>?
    /// Set by the first `finalSave()` (or a delete). The close button saves
    /// and then `onDisappear` saves again; the second pass must not create
    /// a duplicate story or resurrect a deleted one.
    @State private var isFinished = false
    /// "No tags found" on the Auto-tag button for a moment after a pass
    /// that added nothing - it used to end in silence.
    @State private var autoTagNotice: String?

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
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    titleField
                    folderChip

                    if !tags.isEmpty {
                        tagCloud
                    }

                    contentField
                        .padding(.top, 4)

                    if showTagInput {
                        tagInputRow
                    }
                }
                .padding(.horizontal, AppLayout.pageHorizontal)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            // A bar, not an overlay: the page scrolls under it with the
            // system's soft edge and knows its height. It was a material slab
            // in a ZStack with a guessed 96pt of clearance for a ~100pt bar,
            // so the tag field - last on the page - focused underneath it.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    transcribingBanner
                        .padding(.horizontal, AppLayout.pageHorizontal)
                    bottomBar
                }
            }
        }
        .navigationTitle(isEditing ? "Edit story" : "New story")
        .navigationBarTitleDisplayMode(.inline)
        .alert(StoryDeleteCopy.title, isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let story = draftStory ?? existingStory {
                    // Finish first: dismissing runs `finalSave()` from
                    // `onDisappear`, which wrote the editor's fields back into
                    // the story it had just deleted - a write to a deleted
                    // SwiftData object - or recreated it from the text.
                    isFinished = true
                    autoSaveTask?.cancel()
                    draftStory = nil
                    viewModel.deleteStory(story)
                    Haptics.warning()
                    dismiss()
                }
            }
        } message: {
            Text(StoryDeleteCopy.message)
        }
        .toolbar {
            // The editor autosaves, so closing is saving: no Cancel/Save pair.
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .close) {
                    finalSave()
                    dismiss()
                }
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
            // Never cancel while stop is finalizing - that deletes the take.
            if audioService.isRecording, !audioService.isFinalizingRecording {
                audioService.cancelRecording()
            }
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
            .font(.title.weight(.bold))
            .foregroundStyle(.white)
            .focused($focusedField, equals: .title)
            .submitLabel(.next)
            .onSubmit { contentFocused = true }
    }

    // MARK: - Folder chip

    private var folderChip: some View {
        StoryFolderChip(folder: currentFolder) {
            if draftStory == nil && !isEditing {
                // Ensure a draft exists so move sheet can operate
                ensureDraftForMove()
            }
            showingMoveSheet = true
        }
    }

    private var currentFolder: StoryFolder? {
        guard let id = selectedFolderId else { return nil }
        return viewModel.folders.first { $0.id == id }
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
                VoiceLoader(size: .small).foregroundStyle(AppColors.primary)
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
                        // 44pt to the finger without growing the banner.
                        .padding(12)
                        .contentShape(.rect)
                        .padding(-12)
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

    /// Progress for Auto-tag shows on its button, where the tap was; the
    /// cloud only holds tags.
    private var tagCloud: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags) { tag in
                StoryTagPill(tag: tag, size: .small, onRemove: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        tags.removeAll { $0.id == tag.id }
                    }
                    Haptics.light()
                })
                .transition(.scale.combined(with: .opacity))
            }
        }
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
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Tag type")

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
                        .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Add tag")
            }
        }
        .padding(10)
        .glassBackground(cornerRadius: 10)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Bottom Bar

    /// Rides in the page's `.safeAreaBar`: no slab of its own.
    private var bottomBar: some View {
        VStack(spacing: 0) {
            formatRow
            actionRow
        }
    }

    private var formatRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                formatButton("Bold", icon: "bold") { richTextController.bold() }
                formatButton("Italic", icon: "italic") { richTextController.italic() }
                formatButton("Underline", icon: "underline") { richTextController.underline() }

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
                .accessibilityLabel("Text style")

                Divider()
                    .frame(height: 18)
                    .opacity(0.3)
                    .padding(.horizontal, 4)

                formatButton("Bulleted list", icon: "list.bullet") { richTextController.bulletList() }
                formatButton("Numbered list", icon: "list.number") { richTextController.numberedList() }
                formatButton("Checklist", icon: "checklist") { richTextController.checklist() }

                Spacer(minLength: 8)

                formatButton("Hide keyboard", icon: "keyboard.chevron.compact.down") {
                    richTextController.dismissKeyboard()
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func formatButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            formatIcon(icon)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(label)
    }

    /// A 36×32 plate inside a 44pt target.
    private func formatIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 36, height: 32)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
            .frame(minWidth: AppLayout.minHitTarget, minHeight: AppLayout.minHitTarget)
            .contentShape(.rect)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            micToggle

            tagToggle

            Spacer(minLength: 0)

            if llmService.isAvailable && !plainText.isEmpty {
                GlassButton(
                    title: autoTagNotice ?? "Auto-tag",
                    icon: "sparkles",
                    style: .secondary,
                    size: .small,
                    isLoading: isExtractingTags
                ) {
                    Task { await extractTags() }
                }
                .disabled(autoTagNotice != nil)
            }
        }
        .padding(.horizontal, AppLayout.pageHorizontal)
        .padding(.vertical, 8)
    }

    private var micToggle: some View {
        GlassButton(
            title: audioService.isRecording ? "Stop" : "Dictate",
            icon: audioService.isRecording ? "stop.fill" : "mic.fill",
            style: .secondary,
            size: .small
        ) {
            toggleRecording()
        }
        .disabled(isTranscribing || isDictationTransitioning)
    }

    private var tagToggle: some View {
        GlassButton(title: "Tag", icon: "tag", style: .secondary, size: .small) {
            Haptics.light()
            withAnimation(.spring(response: 0.25)) {
                showTagInput.toggle()
                if showTagInput { focusedField = .tagValue }
            }
        }
    }

    // MARK: - More Menu

    /// Practice, Warm-Up and Drill are not here: they open ContentView's
    /// session cover and sheets, which cannot present over this sheet, so
    /// they did nothing. The story's page owns them; a new story's page is
    /// pushed when this editor closes (`onCreated`).
    private var moreMenu: some View {
        Menu {
            Button {
                if draftStory == nil { ensureDraftForMove() }
                showingMoveSheet = true
            } label: {
                Label("Move to Folder…", systemImage: "folder")
            }

            // Pickers, so each current value wears the system checkmark - a
            // checkmark Image inside a menu button's label was dropped.
            Picker(selection: $selectedEntryType) {
                ForEach(StoryEntryType.allCases) { type in
                    Label(type.displayName, systemImage: type.icon)
                        .tag(type)
                }
            } label: {
                Label("Type", systemImage: "rectangle.stack")
            }
            .pickerStyle(.menu)

            Picker(selection: $selectedStage) {
                ForEach(StoryStage.allCases) { stage in
                    Label(stage.displayName, systemImage: stage.icon)
                        .tag(stage)
                }
            } label: {
                Label("Stage", systemImage: "flag")
            }
            .pickerStyle(.menu)

            Picker(selection: $selectedOccasion) {
                Text("None")
                    .tag(StoryOccasion?.none)
                ForEach(StoryOccasion.allCases) { occasion in
                    Label(occasion.rawValue, systemImage: occasion.icon)
                        .tag(StoryOccasion?.some(occasion))
                }
            } label: {
                Label("Occasion", systemImage: "sparkles")
            }
            .pickerStyle(.menu)

            if draftStory != nil || existingStory != nil {
                Divider()
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.semibold))
        }
        .accessibilityLabel("More")
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
        // A late dictation result after closing must not recreate a draft.
        guard !isFinished else { return }
        let trimmedContent = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty || !trimmedTitle.isEmpty else { return }

        if let draft = draftStory {
            viewModel.autoSave(draft, title: title, attributed: attributedContent)
        } else {
            ensureDraftForMove()
        }
    }

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

    private func save(_ draft: Story) {
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

    /// Runs once, when the editor goes away: the close button, a swipe down,
    /// or `onDisappear` after either (`isFinished` makes the second call a
    /// no-op).
    private func finalSave() {
        guard !isFinished else { return }
        isFinished = true
        autoSaveTask?.cancel()

        let isEmpty = plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Typed and closed inside the 2s autosave window: no draft exists
        // yet, and the text used to be dropped.
        if draftStory == nil && !isEmpty {
            ensureDraftForMove()
        }
        guard let draft = draftStory else { return }

        if isEmpty && existingStory == nil {
            // A draft this editor created and the writer emptied. An existing
            // story is never deleted for being empty - that was a delete with
            // no confirmation, and its takes lost their subject.
            draftStory = nil
            viewModel.deleteStory(draft)
            return
        }

        save(draft)
        if existingStory == nil {
            onCreated?(draft)
        }

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
                _ = try await audioService.startRecording()
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
            // Transcribed once and deleted, so it never goes to iCloud.
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
                // User cancelled - silently clean up
            } catch {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
            }

            try? FileManager.default.removeItem(at: url)
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
        let countBefore = tags.count
        withAnimation(.spring(response: 0.3)) {
            for tag in extracted where !tags.contains(where: { $0.type == tag.type && $0.value.lowercased() == tag.value.lowercased() }) {
                tags.append(tag)
            }
        }

        guard tags.count > countBefore else {
            // A pass that adds nothing used to end in silence: the button
            // came back and the page looked unchanged.
            Haptics.warning()
            showAutoTagNotice("No tags found")
            return
        }
        Haptics.success()
    }

    private func showAutoTagNotice(_ message: String) {
        autoTagNotice = message
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            try? await Task.sleep(for: .seconds(2))
            autoTagNotice = nil
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

    /// The first line's first six words. Splitting the whole text on spaces
    /// kept newlines inside the "words", so "Toast⏎⏎Good evening…" became a
    /// title that ran over three lines.
    private func autoTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .first { !$0.allSatisfy(\.isWhitespace) } ?? ""
        let words = firstLine.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
        if words.count > 40 { return String(words.prefix(40)) + "…" }
        return words.isEmpty ? "Untitled" : words
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        duration.minutesSeconds
    }
}
