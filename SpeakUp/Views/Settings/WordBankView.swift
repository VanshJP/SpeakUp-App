import SwiftUI
import SwiftData
import Speech

struct WordBankView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var selectedTab = 0
    @State private var isWordInputFocused = false
    @State private var isDictationInputFocused = false
    @State private var isFillerInputFocused = false
    @State private var newFillerIsContextDependent = false

    // Dictation state
    @State private var dictationEngine = DictationEngine()

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {
                // Segmented picker
                Picker("", selection: $selectedTab) {
                    Text("Vocab").tag(0)
                    Text("Dictionary").tag(1)
                    Text("Filler Words").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ScrollView {
                    VStack(spacing: 16) {
                        if selectedTab == 0 {
                            wordBankTab
                        } else if selectedTab == 1 {
                            dictationDictionaryTab
                        } else {
                            fillerWordsTab
                        }
                    }
                    .padding()
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                // Bottom input area — pinned outside scroll
                bottomInputBar
            }
        }
        .navigationTitle("Words")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedTab) {
            if dictationEngine.isListening {
                stopDictationAndAdd()
            }
        }
    }

    // MARK: - Bottom Input Bar

    @ViewBuilder
    private var bottomInputBar: some View {
        VStack(spacing: 8) {
            // Error messages
            if selectedTab == 0, let error = viewModel.vocabWordError {
                errorLabel(error)
            } else if selectedTab == 1, let error = viewModel.dictationWordError {
                errorLabel(error)
            } else if selectedTab == 2, let error = viewModel.fillerWordError {
                errorLabel(error)
            }

            if selectedTab == 0 {
                bottomVocabInput
            } else if selectedTab == 1 {
                bottomDictionaryInput
            } else {
                bottomFillerInput
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private var bottomVocabInput: some View {
        HStack(spacing: 10) {
            // Mic button
            micButton(tint: .teal)

            // Text input
            HStack(spacing: 8) {
                PersistentTextField(
                    hint: "Add a word...",
                    text: $viewModel.newVocabWord,
                    isFocused: $isWordInputFocused,
                    onSubmit: { viewModel.addVocabWord() }
                )
                .frame(height: 22)

                if !viewModel.newVocabWord.isEmpty {
                    Button {
                        viewModel.newVocabWord = ""
                        viewModel.vocabWordError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(.white.opacity(0.06))
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    }
            }
        }
    }

    private var bottomDictionaryInput: some View {
        HStack(spacing: 10) {
            // Mic button
            micButton(tint: AppColors.primary)

            // Text input
            HStack(spacing: 8) {
                PersistentTextField(
                    hint: "Add a name or phrase...",
                    text: $viewModel.newDictationBiasWord,
                    isFocused: $isDictationInputFocused,
                    onSubmit: { viewModel.addDictationBiasWord() }
                )
                .frame(height: 22)

                if !viewModel.newDictationBiasWord.isEmpty {
                    Button {
                        viewModel.newDictationBiasWord = ""
                        viewModel.dictationWordError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(.white.opacity(0.06))
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    }
            }
        }
    }

    private var bottomFillerInput: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)

                PersistentTextField(
                    hint: "Add custom filler...",
                    text: $viewModel.newFillerWord,
                    isFocused: $isFillerInputFocused,
                    onSubmit: { viewModel.addCustomFiller(isContextDependent: newFillerIsContextDependent) }
                )
                .frame(height: 22)

                if !viewModel.newFillerWord.isEmpty {
                    Button {
                        viewModel.newFillerWord = ""
                        viewModel.fillerWordError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(.white.opacity(0.06))
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    }
            }

            // Detection type picker
            HStack(spacing: 6) {
                Text("Detect as")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))

                detectionTypePill(label: "Always", isSelected: !newFillerIsContextDependent) {
                    withAnimation(.spring(response: 0.25)) {
                        newFillerIsContextDependent = false
                    }
                }

                detectionTypePill(label: "Context-only", isSelected: newFillerIsContextDependent) {
                    withAnimation(.spring(response: 0.25)) {
                        newFillerIsContextDependent = true
                    }
                }
            }
        }
    }

    private func micButton(tint: Color) -> some View {
        Button {
            toggleDictation()
        } label: {
            ZStack {
                Circle()
                    .fill(dictationEngine.isListening ? tint.opacity(0.25) : .white.opacity(0.06))
                    .overlay {
                        Circle()
                            .strokeBorder(
                                dictationEngine.isListening ? tint.opacity(0.6) : .white.opacity(0.1),
                                lineWidth: 0.5
                            )
                    }
                    .frame(width: 40, height: 40)

                Image(systemName: dictationEngine.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(dictationEngine.isListening ? tint : .white.opacity(0.5))
                    .symbolEffect(.pulse, isActive: dictationEngine.isListening)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dictation Handling

    private func toggleDictation() {
        if dictationEngine.isListening {
            stopDictationAndAdd()
        } else {
            dictationEngine.recognizedWords = []
            dictationEngine.lastAddedIndex = 0
            Haptics.medium()
            Task {
                await dictationEngine.start()
            }
        }
    }

    private func stopDictationAndAdd() {
        let words = dictationEngine.recognizedWords
        dictationEngine.stop()

        guard !words.isEmpty else { return }

        withAnimation(.spring(duration: 0.25)) {
            if selectedTab == 0 {
                viewModel.addVocabWords(words)
            } else if selectedTab == 1 {
                viewModel.addDictationBiasWords(words)
            }
        }
    }

    /// Add newly recognized words incrementally while dictation is still active.
    private func addNewWords() {
        let words = dictationEngine.recognizedWords
        let startIndex = dictationEngine.lastAddedIndex
        guard words.count > startIndex else { return }

        let newWords = Array(words[startIndex...])
        dictationEngine.lastAddedIndex = words.count

        withAnimation(.spring(duration: 0.25)) {
            if selectedTab == 0 {
                viewModel.addVocabWords(newWords)
            } else if selectedTab == 1 {
                viewModel.addDictationBiasWords(newWords)
            }
        }
    }

    // MARK: - Word Bank Tab

    private var wordBankTab: some View {
        VStack(spacing: 16) {
            // Explanation text (compact)
            HStack(spacing: 8) {
                Image(systemName: "character.book.closed.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("Tracked vocab is highlighted and counted in transcript analytics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            // Live dictation preview
            if dictationEngine.isListening {
                dictationPreview(tint: .teal)
            }

            // Word chips
            vocabWordsSection
        }
    }

    // MARK: - Dictionary Tab

    private var dictationDictionaryTab: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.and.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(AppColors.primary)
                Text("Words and names here bias Whisper transcription accuracy. They do not count as vocab usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            // Live dictation preview
            if dictationEngine.isListening {
                dictationPreview(tint: AppColors.primary)
            }

            dictationWordsSection
        }
    }

    // MARK: - Dictation Preview

    private func dictationPreview(tint: Color) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(tint)
                        .symbolEffect(.pulse)
                    Text("Listening — say words to add")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button {
                        stopDictationAndAdd()
                    } label: {
                        Text("Done")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background {
                                Capsule()
                                    .fill(tint.opacity(0.3))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(tint.opacity(0.5), lineWidth: 0.5)
                                    }
                            }
                    }
                    .buttonStyle(.plain)
                }

                if !dictationEngine.recognizedWords.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(dictationEngine.recognizedWords.enumerated()), id: \.offset) { _, word in
                            Text(word)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background {
                                    Capsule()
                                        .fill(tint.opacity(0.15))
                                        .overlay {
                                            Capsule()
                                                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                                        }
                                }
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.spring(duration: 0.25), value: dictationEngine.recognizedWords.count)
                }
            }
        }
    }

    @ViewBuilder
    private var dictationWordsSection: some View {
        if viewModel.dictationBiasWords.isEmpty {
            GlassCard {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.and.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.15))

                    Text("No dictation terms yet")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.3))

                    Text("Add names and terms below to bias transcription")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(viewModel.dictationBiasWords.count) dictation terms")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    FlowLayout(spacing: 6) {
                        ForEach(viewModel.dictationBiasWords, id: \.self) { word in
                            chipView(word, tint: AppColors.primary) {
                                withAnimation(.spring(duration: 0.25)) {
                                    viewModel.removeDictationBiasWord(word)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var vocabWordsSection: some View {
        if viewModel.vocabWords.isEmpty {
            GlassCard {
                VStack(spacing: 12) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.15))

                    Text("No words yet")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.3))

                    Text("Add words below to start tracking them")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(viewModel.vocabWords.count) words")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    FlowLayout(spacing: 6) {
                        ForEach(viewModel.vocabWords, id: \.self) { word in
                            chipView(word, tint: .teal) {
                                withAnimation(.spring(duration: 0.25)) {
                                    viewModel.removeVocabWord(word)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Filler Words Tab

    private var fillerWordsTab: some View {
        VStack(spacing: 16) {
            // Explanation
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.minus")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Manage which words are detected as fillers during analysis. Custom fillers are always detected; context-dependent ones use speech patterns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            // Always Detected section
            alwaysDetectedSection

            // Context-Dependent section
            contextDependentSection

            // Removed section (only if any removed)
            if !viewModel.removedDefaultFillers.isEmpty {
                removedFillersSection
            }

            // Reset button (only if customized)
            if viewModel.hasFillerCustomizations {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        viewModel.resetFillersToDefaults()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                        Text("Reset to Defaults")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func detectionTypePill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(isSelected ? .orange.opacity(0.25) : .white.opacity(0.05))
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected ? .orange.opacity(0.5) : .white.opacity(0.08),
                                    lineWidth: 0.5
                                )
                        }
                }
        }
        .buttonStyle(.plain)
    }

    private var alwaysDetectedSection: some View {
        let unconditional = viewModel.activeFillerWords.filter { !$0.isContextDependent }
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Always Detected", icon: "exclamationmark.triangle.fill")

                if unconditional.isEmpty {
                    Text("All unconditional fillers removed")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(unconditional, id: \.word) { item in
                            chipView(item.word, tint: item.isCustom ? .orange : .red) {
                                withAnimation(.spring(duration: 0.25)) {
                                    viewModel.removeFillerWord(item.word)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var contextDependentSection: some View {
        let contextual = viewModel.activeFillerWords.filter { $0.isContextDependent }
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Context-Dependent", icon: "text.magnifyingglass")

                Text("These are only flagged when speech patterns suggest filler usage (e.g. surrounded by pauses).")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))

                if contextual.isEmpty {
                    Text("All context-dependent fillers removed")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(contextual, id: \.word) { item in
                            chipView(item.word, tint: .blue) {
                                withAnimation(.spring(duration: 0.25)) {
                                    viewModel.removeFillerWord(item.word)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var removedFillersSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Removed", icon: "eye.slash")

                FlowLayout(spacing: 6) {
                    ForEach(viewModel.removedDefaultFillers.sorted(), id: \.self) { word in
                        removedChip(word)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Shared Components

    private func chipView(_ word: String, tint: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Text(word)
                .font(.caption.weight(.medium))

            Button {
                Haptics.light()
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(tint.opacity(0.15))
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func removedChip(_ word: String) -> some View {
        HStack(spacing: 5) {
            Text(word)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.35))

            Button {
                Haptics.light()
                withAnimation(.spring(duration: 0.25)) {
                    viewModel.restoreDefaultFiller(word)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.white.opacity(0.04))
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func errorLabel(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
            Text(error)
                .font(.caption)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Dictation Engine

/// Lightweight speech recognizer that extracts individual words from live audio.
@Observable
@MainActor
private class DictationEngine {
    var isListening = false
    var recognizedWords: [String] = []
    var lastAddedIndex = 0

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func start() async {
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard authorized else { return }
        guard let recognizer, recognizer.isAvailable else { return }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        // Configure audio session for recording
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("DictationEngine: audio session setup failed: \(error)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            try engine.start()
        } catch {
            print("DictationEngine: audio engine failed to start: \(error)")
            cleanup()
            return
        }

        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let segments = result.bestTranscription.segments
                let words = segments.map { $0.substring }
                    .filter { $0.count >= 2 }
                    .map { $0.capitalized }

                // Deduplicate while preserving order
                var seen = Set<String>()
                var unique: [String] = []
                for word in words {
                    let key = word.lowercased()
                    if !seen.contains(key) {
                        seen.insert(key)
                        unique.append(word)
                    }
                }

                Task { @MainActor in
                    self.recognizedWords = unique
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    self.cleanup()
                    self.isListening = false
                }
            }
        }
    }

    func stop() {
        recognitionRequest?.endAudio()
        cleanup()
        isListening = false
    }

    private func cleanup() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}
