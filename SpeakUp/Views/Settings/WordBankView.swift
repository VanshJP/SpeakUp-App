import SwiftUI

/// The three lists behind a take: words to use, names and terms transcripts
/// should spell right, and the words that count as fillers.
nonisolated enum WordListTab: Int, CaseIterable, Identifiable {
    case words, names, fillers

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .words: "Words"
        case .names: "Names & terms"
        case .fillers: "Fillers"
        }
    }
}

struct WordBankView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SettingsViewModel
    let showDismissButton: Bool
    @State private var selectedTab: WordListTab
    @State private var isWordInputFocused = false
    @State private var isDictationInputFocused = false
    @State private var isFillerInputFocused = false
    @State private var newFillerIsContextDependent = false
    @State private var showingFillerReset = false

    @State private var dictationEngine = DictationService()

    /// `initialTab` lets a caller land on the list it is about - Analysis'
    /// filler toggle opens straight on Fillers.
    init(viewModel: SettingsViewModel, showDismissButton: Bool = true, initialTab: WordListTab = .words) {
        _viewModel = Bindable(viewModel)
        self.showDismissButton = showDismissButton
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {
                SectionPicker(
                    sections: WordListTab.allCases,
                    selection: $selectedTab,
                    label: { $0.title }
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                PageScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .words: wordBankTab
                        case .names: dictationDictionaryTab
                        case .fillers: fillerWordsTab
                        }
                    }
                    .padding()
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // A bar, not a material slab: the list scrolls under a soft
                // edge instead of stopping at a flat grey band.
                .safeAreaBar(edge: .bottom) { bottomInputBar }
            }
        }
        .navigationTitle("Word Lists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showDismissButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .onChange(of: selectedTab) { previousTab, _ in
            if dictationEngine.isListening {
                stopDictationAndAdd(into: previousTab)
            }
        }
        // Leaving mid-dictation - closing the sheet, or opening the Word
        // Library - must still hand the mic and the session back.
        .onDisappear {
            if dictationEngine.isListening {
                stopDictationAndAdd()
            }
        }
        .alert("Reset filler words?", isPresented: $showingFillerReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                withAnimation(.spring(duration: 0.3)) {
                    viewModel.resetFillersToDefaults()
                }
            }
        } message: {
            Text("Your custom fillers are deleted and every default filler comes back.")
        }
    }

    // MARK: - Bottom Input Bar

    @ViewBuilder
    private var bottomInputBar: some View {
        VStack(spacing: 8) {
            if let error = dictationEngine.errorMessage {
                errorLabel(error)
            } else if selectedTab == .words, let error = viewModel.vocabWordError {
                errorLabel(error)
            } else if selectedTab == .names, let error = viewModel.dictationWordError {
                errorLabel(error)
            } else if selectedTab == .fillers, let error = viewModel.fillerWordError {
                errorLabel(error)
            }

            switch selectedTab {
            case .words: bottomVocabInput
            case .names: bottomDictionaryInput
            case .fillers: bottomFillerInput
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var bottomVocabInput: some View {
        HStack(spacing: 10) {
            micButton(tint: AppColors.primary)

            inputField {
                PersistentTextField(
                    hint: "Add a word…",
                    text: $viewModel.newVocabWord,
                    isFocused: $isWordInputFocused,
                    onSubmit: { viewModel.addVocabWord() }
                )
                .frame(height: 22)

                if !viewModel.newVocabWord.isEmpty {
                    clearButton {
                        viewModel.newVocabWord = ""
                        viewModel.vocabWordError = nil
                    }
                }
            }
        }
    }

    private var bottomDictionaryInput: some View {
        HStack(spacing: 10) {
            micButton(tint: AppColors.primary)

            inputField {
                PersistentTextField(
                    hint: "Add a name or term…",
                    text: $viewModel.newDictationBiasWord,
                    isFocused: $isDictationInputFocused,
                    onSubmit: { viewModel.addDictationBiasWord() }
                )
                .frame(height: 22)

                if !viewModel.newDictationBiasWord.isEmpty {
                    clearButton {
                        viewModel.newDictationBiasWord = ""
                        viewModel.dictationWordError = nil
                    }
                }
            }
        }
    }

    private var bottomFillerInput: some View {
        VStack(spacing: 4) {
            inputField {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                PersistentTextField(
                    hint: "Add a filler word…",
                    text: $viewModel.newFillerWord,
                    isFocused: $isFillerInputFocused,
                    onSubmit: { viewModel.addCustomFiller(isContextDependent: newFillerIsContextDependent) }
                )
                .frame(height: 22)

                if !viewModel.newFillerWord.isEmpty {
                    clearButton {
                        viewModel.newFillerWord = ""
                        viewModel.fillerWordError = nil
                    }
                }
            }

            HStack(spacing: 6) {
                Text("Detect")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                CardPill(label: "Always", isSelected: !newFillerIsContextDependent) {
                    newFillerIsContextDependent = false
                }

                CardPill(label: "In context", isSelected: newFillerIsContextDependent) {
                    newFillerIsContextDependent = true
                }
            }
        }
    }

    private func inputField<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
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

    /// Drawn at glyph size, hit-tested at 44pt: the negative padding hands the
    /// extra back so the field keeps its height when the button appears.
    private func clearButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .padding(-12)
        .accessibilityLabel("Clear")
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
                    .symbolSwap(dictationEngine.isListening)
            }
            .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
            .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(dictationEngine.isListening ? "Stop dictating and add words" : "Dictate words")
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

    /// `tab` is the list the words were dictated for. A tab switch calls this
    /// after `selectedTab` has already moved on, which used to file the words
    /// under the tab you were leaving for.
    private func stopDictationAndAdd(into tab: WordListTab? = nil) {
        let words = dictationEngine.recognizedWords
        dictationEngine.stop()

        guard !words.isEmpty else { return }

        withAnimation(.spring(duration: 0.25)) {
            switch tab ?? selectedTab {
            case .words: _ = viewModel.addVocabWords(words)
            case .names: _ = viewModel.addDictationBiasWords(words)
            case .fillers: break
            }
        }
    }

    // MARK: - Word Bank Tab

    private var wordBankTab: some View {
        VStack(spacing: 16) {
            if dictationEngine.isListening {
                dictationPreview(tint: AppColors.primary)
            }

            // The reading end of the same list. This tab is a form for typing
            // words in; the library is where you find one worth typing.
            NavigationLink {
                WordLibraryView()
            } label: {
                GlassCard(tint: AppColors.categorySage.opacity(0.06), padding: 14) {
                    HStack(spacing: 12) {
                        IconChip(icon: "character.book.closed.fill", tint: AppColors.categorySage, size: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Browse the word library")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                            Text("Search any word, read the definition, add it here")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Browse the word library")

            vocabWordsSection

            Text("Words here are highlighted in your transcripts and counted each time you use them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Dictionary Tab

    private var dictationDictionaryTab: some View {
        VStack(spacing: 16) {
            Text("Add names, places, and jargon so your transcripts spell them right. They don't count toward your vocabulary.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

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
                    Text("Listening. Say the words to add.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    GlassButton(title: "Done", style: .secondary, size: .small) {
                        Haptics.light()
                        stopDictationAndAdd()
                    }
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
        let terms = viewModel.dictationBiasWords
        if terms.isEmpty {
            GlassCard {
                EmptyStateInline(
                    icon: "waveform.and.magnifyingglass",
                    message: "No names or terms yet. Add the ones your transcripts get wrong."
                )
            }
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    GlassCardTitle(terms.count == 1 ? "1 name or term" : "\(terms.count) names and terms")
                        .monospacedDigit()

                    FlowLayout(spacing: 6) {
                        ForEach(terms, id: \.self) { word in
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
        let words = viewModel.vocabWords
        if words.isEmpty {
            GlassCard {
                EmptyStateInline(
                    icon: "character.book.closed",
                    message: "No words yet. Add a few below to start tracking them."
                )
            }
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    GlassCardTitle(words.count == 1 ? "1 word" : "\(words.count) words")
                        .monospacedDigit()

                    FlowLayout(spacing: 6) {
                        ForEach(words, id: \.self) { word in
                            chipView(word, tint: AppColors.primary) {
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
            Text("Choose which words count as fillers when a take is scored.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            alwaysDetectedSection

            contextDependentSection

            if !viewModel.removedDefaultFillers.isEmpty {
                removedFillersSection
            }

            if viewModel.hasFillerCustomizations {
                GlassButton(title: "Reset to defaults", icon: "arrow.counterclockwise", style: .outline, fullWidth: true) {
                    Haptics.warning()
                    showingFillerReset = true
                }
            }
        }
    }

    private var alwaysDetectedSection: some View {
        let unconditional = viewModel.activeFillerWords.filter { !$0.isContextDependent }
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Always detected")

                if unconditional.isEmpty {
                    Text("You've removed every always-detected filler.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(unconditional, id: \.word) { item in
                            chipView(item.word, tint: item.isCustom ? AppColors.warning : AppColors.error) {
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
                GlassCardTitle("Detected in context")

                Text("Flagged only when the pattern says filler, like a pause on either side.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if contextual.isEmpty {
                    Text("You've removed every in-context filler.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(contextual, id: \.word) { item in
                            chipView(item.word, tint: AppColors.info) {
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
                GlassCardTitle("Removed")

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

            chipButton(icon: "xmark", label: "Remove \(word)", color: .white.opacity(0.6)) {
                Haptics.light()
                onRemove()
            }
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
                .foregroundStyle(.secondary)

            chipButton(icon: "plus", label: "Restore \(word)", color: AppColors.success) {
                Haptics.light()
                withAnimation(.spring(duration: 0.25)) {
                    viewModel.restoreDefaultFiller(word)
                }
            }
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

    /// A chip's own ✕ or +, drawn at caption size and hit-tested at 44pt. The
    /// negative padding returns the extra to the layout, so chips keep their
    /// size; the old 8pt glyph was the whole target and VoiceOver could not
    /// say which word it removed.
    private func chipButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .padding(-14)
        .accessibilityLabel(label)
    }

    private func errorLabel(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
            Text(error)
                .font(.caption)
        }
        .foregroundStyle(AppColors.error)
        .padding(.horizontal, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Daily word workout

private enum VocabLevelChoice: Int {
    case automatic = 0
    case easy = 1
    case medium = 2
    case hard = 3

    var label: String {
        switch self {
        case .automatic: return "Auto"
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }
}

private let vocabLevelChoices: [VocabLevelChoice] = [.automatic, .easy, .medium, .hard]

struct VocabChallengeSettingsCard: View {
    @Bindable var viewModel: SettingsViewModel

    private static let workoutCaption = "Spotlight a few words. Use each one in a sentence."
    private static let teachCaption = "Mixes in a word you don't track yet."

    var body: some View {
        // Rules start under the row titles: 14pt inset + 24pt glyph + 12pt gap.
        GlassRowGroup(dividerInset: 50) {
            row {
                Toggle(isOn: $viewModel.vocabChallengeEnabled) {
                    Label("Daily word workout", systemImage: "character.book.closed")
                        .font(.subheadline)
                }
                .tint(AppColors.primary)
                .accessibilityHint(Self.workoutCaption)

                caption(Self.workoutCaption)
            }
            .onChange(of: viewModel.vocabChallengeEnabled) { _, _ in
                viewModel.saveVocabChallengeSettings()
            }

            if viewModel.vocabChallengeEnabled {
                row {
                    HStack(spacing: 6) {
                        Label("Words per day", systemImage: "number")
                            .font(.subheadline)
                        Spacer(minLength: 12)
                        ForEach([1, 2, 3], id: \.self) { count in
                            CardPill(
                                label: "\(count)",
                                isSelected: viewModel.vocabChallengeWordCount == count,
                                minWidth: 36
                            ) {
                                viewModel.vocabChallengeWordCount = count
                                viewModel.saveVocabChallengeSettings()
                            }
                            .accessibilityLabel(count == 1 ? "1 word per day" : "\(count) words per day")
                        }
                    }
                }

                row {
                    Toggle(isOn: $viewModel.vocabChallengeIntroduceNew) {
                        Label("Teach new words", systemImage: "sparkles")
                            .font(.subheadline)
                    }
                    .tint(AppColors.primary)
                    .accessibilityHint(Self.teachCaption)

                    caption(Self.teachCaption)
                }
                .onChange(of: viewModel.vocabChallengeIntroduceNew) { _, _ in
                    viewModel.saveVocabChallengeSettings()
                }

                if viewModel.vocabChallengeIntroduceNew {
                    row {
                        Label("Word level", systemImage: "chart.bar")
                            .font(.subheadline)

                        HStack(spacing: 6) {
                            ForEach(vocabLevelChoices, id: \.rawValue) { choice in
                                CardPill(
                                    label: choice.label,
                                    isSelected: viewModel.vocabChallengeLevelOverride == choice.rawValue
                                ) {
                                    viewModel.vocabChallengeLevelOverride = choice.rawValue
                                    viewModel.saveVocabChallengeSettings()
                                }
                                .accessibilityLabel("Word level \(choice.label)")
                            }
                        }
                        .padding(.leading, 36)
                    }
                }
            }
        }
        .labelStyle(.row)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 36)
            .accessibilityHidden(true)
    }
}

/// A single-choice chip. Selected is the solid white pill every filter chip
/// wears (`FilterChip`, `SectionPicker`); idle is the painted capsule used on
/// a plate, since these sit inside cards and glass on glass turns murky.
private struct CardPill: View {
    let label: String
    let isSelected: Bool
    var minWidth: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                // Same ink as the primary GlassButton on its white fill.
                .foregroundStyle(isSelected ? Color(red: 0.07, green: 0.07, blue: 0.08) : .white.opacity(0.8))
                .padding(.horizontal, 12)
                .frame(minWidth: minWidth, minHeight: 30)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.10))
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(isSelected ? 0 : 0.16), lineWidth: 1)
                        }
                }
                // A 30pt chip in a 44pt target: the hit area grows around it.
                .frame(minHeight: AppLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
