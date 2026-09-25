import SwiftUI

nonisolated struct ReadAloudTextReplacement {
    let text: String
    let sourceNote: String?
}

struct ReadAloudComposerSheet: View {
    let initialText: String
    let isEditing: Bool
    let onCancel: () -> Void
    let onSave: (String) -> Void
    let onPractice: (String) -> Void

    @State private var text: String
    @State private var pronunciationService = PronunciationService()
    @State private var showingDictionary = false
    @State private var showingFileImporter = false
    @State private var isImporting = false
    @State private var sourceNote: String?
    @State private var errorMessage: String?
    @State private var pendingReplacement: ReadAloudTextReplacement?
    @State private var showingDiscardConfirm = false
    @FocusState private var textFieldFocused: Bool

    init(
        initialText: String,
        isEditing: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void,
        onPractice: @escaping (String) -> Void
    ) {
        self.initialText = initialText
        self.isEditing = isEditing
        self.onCancel = onCancel
        self.onSave = onSave
        self.onPractice = onPractice
        _text = State(initialValue: initialText)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var characterCount: Int {
        trimmedText.count
    }

    private var wordCount: Int {
        trimmedText.split(whereSeparator: \.isWhitespace).count
    }

    private var isOverLimit: Bool {
        characterCount > ReadAloudPassage.customMaxCharacters
    }

    private var normalizedText: String? {
        guard !isOverLimit else { return nil }
        return ReadAloudPassage.normalizedCustomText(text)
    }

    private var canUseText: Bool {
        normalizedText != nil
    }

    private var canDefine: Bool {
        canUseText && PronunciationService.canDefine(trimmedText)
    }

    /// Anything typed, pasted or imported that Save has not kept. A swipe
    /// down used to throw it away without a word.
    private var isDirty: Bool {
        trimmedText != initialText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            PageScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    sourceActions
                    editor
                    previewActions
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            // Pinned, so Save rides above the keyboard. The editor takes
            // focus on open, and the buttons used to sit under it.
            .safeAreaBar(edge: .bottom) {
                saveActions
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .navigationTitle(isEditing ? "Edit Passage" : "Add Your Passage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            showingDiscardConfirm = true
                        } else {
                            close()
                        }
                    }
                    .confirmationDialog(
                        isEditing ? "Discard your changes?" : "Discard this passage?",
                        isPresented: $showingDiscardConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Discard", role: .destructive) { close() }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .appBackground(.subtle)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: ReadAloudDocumentImporter.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingDictionary) {
            DictionaryView(term: trimmedText)
        }
        .confirmationDialog(
            "Replace current text?",
            isPresented: Binding(
                get: { pendingReplacement != nil },
                set: { if !$0 { pendingReplacement = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace Text", role: .destructive) {
                guard let pendingReplacement else { return }
                applyReplacement(pendingReplacement)
            }
            Button("Keep Current Text", role: .cancel) {
                pendingReplacement = nil
            }
        } message: {
            Text("Your current edits will be replaced.")
        }
        .alert(
            "Could Not Import",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if initialText.isEmpty {
                textFieldFocused = true
            }
        }
        .onDisappear {
            pronunciationService.stop()
        }
    }

    // MARK: - Content

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Practice text that matters to you")
                .font(.title3.weight(.bold))
            Text("Paste, type, or import a document. Big Talk keeps it on this device and scores one focused section at a time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceActions: some View {
        HStack(spacing: 10) {
            // The system paste control: reading `UIPasteboard` from our own
            // button raised iOS's "Allow Paste" alert on every tap, and it
            // greys itself out when there is no text to paste.
            PasteButton(payloadType: String.self) { @Sendable strings in
                // The payload can arrive off the main actor.
                let pasted = strings.first
                Task { @MainActor in paste(pasted) }
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
            .controlSize(.large)
            // iOS refuses a paste control it cannot clearly see, so this one
            // stays opaque rather than wearing the Import button's glass.
            .tint(AppColors.categoryNeutralCool)
            .disabled(isImporting)

            GlassButton(
                title: "Import file",
                icon: "doc.badge.plus",
                style: .secondary,
                size: .small,
                isLoading: isImporting,
                fullWidth: true
            ) {
                textFieldFocused = false
                showingFileImporter = true
            }
        }
    }

    private var editor: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste or type a word, speech excerpt, article, or short story.")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .focused($textFieldFocused)
                        .frame(minHeight: 210)
                        .accessibilityLabel("Passage text")
                }

                Divider()
                    .overlay(Color.white.opacity(0.10))

                HStack(alignment: .firstTextBaseline) {
                    Text("\(wordCount) word\(wordCount == 1 ? "" : "s")")
                    Spacer()
                    Text("\(characterCount) / \(ReadAloudPassage.customMaxCharacters)")
                        .foregroundStyle(isOverLimit ? AppColors.warning : .secondary)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                if let sourceNote {
                    Label(sourceNote, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isOverLimit {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This is too long for one scored take. Use a practice-sized opening, or edit it down to \(ReadAloudPassage.customMaxCharacters) characters.")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                            .fixedSize(horizontal: false, vertical: true)

                        // A real button: this was caption text, the only way
                        // out of an over-limit draft, with a hit area the size
                        // of its words.
                        GlassButton(
                            title: "Use first practice section",
                            icon: "scissors",
                            style: .secondary,
                            size: .small
                        ) {
                            useFirstPracticeSection()
                        }
                    }
                }
            }
        }
    }

    /// Reads Stop while the passage plays, like the session's Hear it. It used
    /// to disable itself instead, and an 800-character passage could only be
    /// silenced by leaving the sheet.
    private var previewActions: some View {
        let isSpeaking = pronunciationService.isSpeaking

        return HStack(spacing: 10) {
            GlassButton(
                title: isSpeaking ? "Stop" : "Hear it",
                icon: isSpeaking ? "stop.fill" : "speaker.wave.2.fill",
                style: .secondary,
                size: .small,
                fullWidth: true
            ) {
                Haptics.light()
                if isSpeaking {
                    pronunciationService.stop()
                } else {
                    textFieldFocused = false
                    pronunciationService.speak(word: trimmedText)
                }
            }
            .disabled(!canUseText)
            .opacity(canUseText ? 1 : 0.45)
            .accessibilityLabel(isSpeaking ? "Stop playback" : "Hear passage")

            if canDefine {
                GlassButton(
                    title: "Full definition",
                    icon: "book.fill",
                    style: .secondary,
                    size: .small,
                    fullWidth: true
                ) {
                    Haptics.light()
                    pronunciationService.stop()
                    showingDictionary = true
                }
            }
        }
    }

    private var saveActions: some View {
        VStack(spacing: 10) {
            GlassButton(
                title: "Save and practice",
                icon: "mic.fill",
                style: .primary,
                fullWidth: true
            ) {
                guard let normalizedText else { return }
                pronunciationService.stop()
                onPractice(normalizedText)
            }
            .disabled(!canUseText)
            .opacity(canUseText ? 1 : 0.45)

            GlassButton(
                title: isEditing ? "Save changes" : "Save for later",
                icon: "bookmark.fill",
                style: .secondary,
                fullWidth: true
            ) {
                guard let normalizedText else { return }
                pronunciationService.stop()
                onSave(normalizedText)
            }
            .disabled(!canUseText)
            .opacity(canUseText ? 1 : 0.45)
        }
    }

    // MARK: - Sources

    private func close() {
        pronunciationService.stop()
        onCancel()
    }

    private func paste(_ pastedText: String?) {
        guard let pastedText,
              !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Haptics.light()
        requestReplacement(
            ReadAloudTextReplacement(
                text: pastedText,
                sourceNote: "Pasted from Clipboard"
            )
        )
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first else {
            if case .failure(let error) = result,
               !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
            return
        }

        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let document = try await ReadAloudDocumentImporter.importDocument(from: url)
                let importedText: String
                let note: String
                if document.text.count > ReadAloudPassage.customMaxCharacters,
                   let excerpt = ReadAloudPassage.practiceSizedExcerpt(from: document.text) {
                    importedText = excerpt
                    note = "Loaded a practice-sized opening from \(document.name)."
                } else {
                    importedText = document.text
                    note = "Imported from \(document.name)."
                }

                requestReplacement(
                    ReadAloudTextReplacement(text: importedText, sourceNote: note)
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestReplacement(_ replacement: ReadAloudTextReplacement) {
        if trimmedText.isEmpty {
            applyReplacement(replacement)
        } else {
            pendingReplacement = replacement
        }
    }

    private func applyReplacement(_ replacement: ReadAloudTextReplacement) {
        pronunciationService.stop()
        text = replacement.text
        sourceNote = replacement.sourceNote
        pendingReplacement = nil
        textFieldFocused = true
    }

    private func useFirstPracticeSection() {
        guard let excerpt = ReadAloudPassage.practiceSizedExcerpt(from: text) else { return }
        text = excerpt
        sourceNote = "Using the first practice-sized section."
        Haptics.light()
    }
}
