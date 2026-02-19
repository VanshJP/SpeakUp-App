import SwiftUI

struct WordBankInputView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var errorID = 0
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.teal)
                    }

                    Spacer()

                    Text("Word Bank")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Spacer()

                    // Balance the back button
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .hidden()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                // Word chips
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if viewModel.vocabWords.isEmpty {
                                emptyState
                            } else {
                                wordChips
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.vocabWords.count) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }

                // Input bar
                bottomInputBar
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFocused = true
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.2))

            Text("Type a word and press return")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Word Chips

    private var wordChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(viewModel.vocabWords, id: \.self) { word in
                wordChip(word)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func wordChip(_ word: String) -> some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.subheadline.weight(.medium))

            Button {
                Haptics.light()
                withAnimation(.spring(duration: 0.25)) {
                    viewModel.removeVocabWord(word)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(.teal.opacity(0.12))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Bottom Input Bar

    private var bottomInputBar: some View {
        VStack(spacing: 6) {
            if showError, let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                    Text(errorMessage)
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.teal)

                TextField("Add a word...", text: $inputText)
                    .font(.body)
                    .foregroundStyle(.white)
                    .tint(.teal)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isInputFocused)
                    .submitLabel(.return)
                    .onSubmit {
                        addWord()
                        DispatchQueue.main.async {
                            isInputFocused = true
                        }
                    }

                if !inputText.isEmpty {
                    Button {
                        inputText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(.white.opacity(0.04))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Add Word Logic

    private func addWord() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        withAnimation(.easeOut(duration: 0.15)) {
            showError = false
            errorMessage = nil
        }

        guard !trimmed.isEmpty else {
            inputText = ""
            return
        }

        guard !viewModel.vocabWords.contains(trimmed) else {
            flashError("Already in your word bank")
            return
        }

        if FillerWordList.unconditionalFillers.contains(trimmed)
            || FillerWordList.contextDependentFillers.contains(trimmed)
            || FillerWordList.fillerPhrases.contains(trimmed) {
            flashError("That's a filler word — tracked separately")
            return
        }

        let checker = UITextChecker()
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: trimmed, range: range, startingAt: 0,
            wrap: false, language: "en"
        )
        guard misspelled.location == NSNotFound else {
            flashError("Not a recognized word")
            return
        }

        viewModel.vocabWords.append(trimmed)
        Haptics.light()
        inputText = ""
        Task { await viewModel.saveSettings() }
    }

    private func flashError(_ message: String) {
        Haptics.warning()
        errorID += 1
        let currentID = errorID
        errorMessage = message
        withAnimation(.easeOut(duration: 0.15)) {
            showError = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard currentID == errorID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showError = false
            }
        }
    }
}

