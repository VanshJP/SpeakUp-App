import SwiftUI

struct ReadAloudSessionView: View {
    @Bindable var viewModel: ReadAloudViewModel
    let passage: ReadAloudPassage
    @Environment(\.dismiss) private var dismiss
    @State private var showingResult = false
    @State private var showingExitConfirm = false
    @State private var selectedWord: WordDetail?
    @State private var pronunciationService = PronunciationService()
    @State private var lastAutoScrolledWordIndex = 0
    @State private var didAutoStartSession = false

    /// Passage text is the one surface the reader must see to perform; it has
    /// to scale with their Dynamic Type setting like any other reading text.
    @ScaledMetric(relativeTo: .title2) private var passageFontSize: CGFloat = 22

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 0) {
                // Top bar
                topBar

                // Progress bar
                progressBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Passage text with word highlighting
                ScrollViewReader { proxy in
                    PageScrollView {
                        passageText
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                    }
                    .onChange(of: viewModel.currentWordIndex) { _, newIndex in
                        guard abs(newIndex - lastAutoScrolledWordIndex) >= 2 else { return }
                        proxy.scrollTo("word_\(max(0, newIndex - 3))", anchor: .center)
                        lastAutoScrolledWordIndex = newIndex
                    }
                }

                Spacer(minLength: 0)

                // Bottom controls
                bottomControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
        .task {
            // .task re-fires when the result fullScreenCover dismisses — without
            // this guard it would double-start the audio engine on Retry and
            // spin up a ghost session on Done.
            guard !didAutoStartSession else { return }
            didAutoStartSession = true
            await viewModel.startSession(passage: passage)
            lastAutoScrolledWordIndex = 0
        }
        .onDisappear {
            if viewModel.sessionState == .listening {
                viewModel.stopSession()
            }
        }
        .onChange(of: viewModel.sessionState) { _, newState in
            if newState == .finished {
                showingResult = true
            }
        }
        .fullScreenCover(isPresented: $showingResult) {
            if let result = viewModel.result {
                ReadAloudResultView(result: result, onRetry: {
                    showingResult = false
                    lastAutoScrolledWordIndex = 0
                    Task { await viewModel.retryPassage() }
                }, onDone: {
                    showingResult = false
                    viewModel.reset()
                    dismiss()
                })
            }
        }
        .sheet(item: $selectedWord) { detail in
            WordDetailSheet(
                detail: detail,
                pronunciationService: pronunciationService,
                micActive: viewModel.isListening
            )
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                viewModel.reset()
                dismiss()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                Haptics.warning()
                if viewModel.sessionState == .listening {
                    showingExitConfirm = true
                } else {
                    viewModel.stopSession()
                    viewModel.reset()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle().fill(.ultraThinMaterial)
                    }
            }
            .accessibilityLabel("End session")
            .confirmationDialog(
                "End this session?",
                isPresented: $showingExitConfirm,
                titleVisibility: .visible
            ) {
                Button("End Session", role: .destructive) {
                    viewModel.stopSession()
                    viewModel.reset()
                    dismiss()
                }
                Button("Keep Reading", role: .cancel) {}
            } message: {
                Text("Your reading so far won't be scored.")
            }

            Spacer()

            // Timer
            Text(viewModel.formattedElapsedTime)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(.ultraThinMaterial)
                }
                .accessibilityLabel("Elapsed \(viewModel.formattedElapsedTime)")

            Spacer()

            // Accuracy badge
            HStack(spacing: 4) {
                Circle()
                    .fill(accuracyColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text("\(Int(viewModel.accuracyPercentage))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(.ultraThinMaterial)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Accuracy \(Int(viewModel.accuracyPercentage)) percent")
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.primary, AppColors.categoryBrandBright],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * viewModel.progressPercentage)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.progressPercentage)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Passage progress")
        .accessibilityValue("\(Int(viewModel.progressPercentage * 100)) percent")
    }

    // MARK: - Passage Text

    private var passageText: some View {
        let words = passage.words
        let states = viewModel.wordStates

        return WrappingHStack(alignment: .leading, spacing: 6, lineSpacing: 12) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let state = index < states.count ? states[index] : WordMatchState.upcoming
                Text(word)
                    .font(.system(size: passageFontSize, weight: wordWeight(for: index), design: .default))
                    .foregroundStyle(wordColor(for: index, state: state))
                    .underline(isProcessedHighlight(state))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                    .background {
                        if index < states.count && states[index] == .current {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColors.primary.opacity(0.2))
                        }
                    }
                    .onTapGesture {
                        guard isProcessed(state) else { return }
                        Haptics.light()
                        selectedWord = WordDetail(word: word, index: index, state: state)
                    }
                    .accessibilityLabel(wordLabel(word, state: state))
                    .id("word_\(index)")
            }
        }
    }

    /// Words not yet reached are noise to VoiceOver; processed words carry
    /// their match state so a non-visual reader can audit their reading.
    private func wordLabel(_ word: String, state: WordMatchState) -> String {
        switch state {
        case .upcoming:
            return ""
        case .current:
            return "\(word), current"
        case .matched:
            return word
        case .mismatched(let spoken):
            return "missed \(word), you said \(spoken)"
        case .skipped:
            return "\(word), skipped"
        }
    }

    private func wordWeight(for index: Int) -> Font.Weight {
        let states = viewModel.wordStates
        guard index < states.count else { return .regular }
        return states[index] == .current ? .bold : .regular
    }

    private func wordColor(for index: Int, state: WordMatchState) -> Color {
        switch state {
        case .upcoming: return .white.opacity(0.4)
        case .current: return .white
        case .matched: return AppColors.success
        case .mismatched: return AppColors.error
        case .skipped: return AppColors.warning
        }
    }

    private func isProcessed(_ state: WordMatchState) -> Bool {
        switch state {
        case .matched, .mismatched, .skipped: return true
        case .upcoming, .current: return false
        }
    }

    private func isProcessedHighlight(_ state: WordMatchState) -> Bool {
        switch state {
        case .mismatched, .skipped: return true
        default: return false
        }
    }

    private var accuracyColor: Color {
        // Accuracy is a score, so it rides the score ramp rather than the
        // state colors — a 70 is not a "warning".
        AppColors.scoreColor(for: Int(viewModel.accuracyPercentage))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Mic indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isListening ? AppColors.success : AppColors.scoreEmpty)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(viewModel.isListening ? "Listening..." : "Not listening")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Microphone \(viewModel.isListening ? "listening" : "not listening")")

            Spacer()

            GlassButton(
                title: "Done",
                icon: "stop.fill",
                style: .primary,
                size: .medium
            ) {
                Haptics.medium()
                viewModel.stopSession()
            }
            // Disabled while the engine is still starting — a tap during the
            // authorization await used to produce a ghost "0%" result and,
            // worse, leave the engine starting underneath it.
            .disabled(!viewModel.isListening)
            .opacity(viewModel.isListening ? 1 : 0.5)
        }
    }
}

// MARK: - Wrapping HStack (Flow Layout)

struct WrappingHStack: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let position = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
