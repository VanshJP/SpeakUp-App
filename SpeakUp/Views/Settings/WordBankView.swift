import SwiftUI
import SwiftData

struct WordBankView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var selectedTab = 0
    @State private var isWordInputFocused = false
    @State private var isFillerInputFocused = false
    @State private var newFillerIsContextDependent = false

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {
                // Segmented picker
                Picker("", selection: $selectedTab) {
                    Text("Word Bank").tag(0)
                    Text("Filler Words").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ScrollView {
                    VStack(spacing: 16) {
                        if selectedTab == 0 {
                            wordBankTab
                        } else {
                            fillerWordsTab
                        }
                    }
                    .padding()
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle("Words")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Word Bank Tab

    private var wordBankTab: some View {
        VStack(spacing: 16) {
            // Explanation text (compact)
            HStack(spacing: 8) {
                Image(systemName: "character.book.closed.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("Words and names here are highlighted in transcripts and also bias Whisper transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            // Input at top
            vocabInputField

            if let error = viewModel.vocabWordError {
                errorLabel(error)
            }

            // Word chips
            vocabWordsSection
        }
    }

    private var vocabInputField: some View {
        GlassCard {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.teal)

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

                    Text("Add words above to start tracking them")
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

            // Input at top
            fillerInputField

            if let error = viewModel.fillerWordError {
                errorLabel(error)
            }

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

    private var fillerInputField: some View {
        GlassCard {
            VStack(spacing: 12) {
                // Text input row
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
