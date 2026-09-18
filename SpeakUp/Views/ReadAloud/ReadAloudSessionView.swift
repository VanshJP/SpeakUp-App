import SwiftUI
import UIKit

struct ReadAloudSessionView: View {
    @Bindable var viewModel: ReadAloudViewModel
    let passage: ReadAloudPassage
    @Environment(\.dismiss) private var dismiss
    /// The finished read, and the only state its cover reads. A
    /// `showingResult` flag over `viewModel.result` presented an empty cover
    /// whenever the two disagreed — and Retry clears the result while the flag
    /// is still coming down.
    @State private var finishedRead: ReadAloudResult?
    @State private var showingExitConfirm = false
    @State private var selectedWord: WordDetail?
    @State private var pronunciationService = PronunciationService()
    @State private var lastAutoScrolledWordIndex = 0
    @State private var didAutoStartSession = false
    @State private var awaitingShadowStart = false

    @ScaledMetric(relativeTo: .title2) private var passageFontSize: CGFloat = 22

    /// One weight for the whole passage. See `passageText`.
    private static let passageWeight: Font.Weight = .semibold
    /// Roughly a line of reading before the scroll view re-centres.
    private static let scrollAdvanceWords = 8

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 0) {
                topBar

                progressBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollViewReader { proxy in
                    PageScrollView {
                        passageText
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                    }
                    .onChange(of: viewModel.currentWordIndex) { _, newIndex in
                        // Re-centring every second word meant the passage slid
                        // under the reader continuously — the other half of
                        // "the words keep moving". One nudge per line's worth
                        // of reading, animated, so the page holds still while
                        // the highlight travels across it.
                        guard abs(newIndex - lastAutoScrolledWordIndex) >= Self.scrollAdvanceWords else { return }
                        lastAutoScrolledWordIndex = newIndex
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo("word_\(max(0, newIndex - 3))", anchor: .center)
                        }
                    }
                }

                Spacer(minLength: 0)

                bottomControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
        .task {
            guard !didAutoStartSession else { return }
            didAutoStartSession = true
            if viewModel.isShadowMode {
                awaitingShadowStart = true
                pronunciationService.speak(text: passage.text, rate: 0.42)
            } else {
                await viewModel.startSession(passage: passage)
                lastAutoScrolledWordIndex = 0
            }
        }
        .onDisappear {
            pronunciationService.stop()
            if viewModel.sessionState == .listening {
                viewModel.stopSession()
            }
        }
        .onChange(of: viewModel.sessionState) { _, newState in
            guard newState == .finished, let result = viewModel.result else { return }
            finishedRead = result
            PracticeRoutineService.shared.complete(.readAloud)
        }
        .fullScreenCover(item: $finishedRead) { result in
            ReadAloudResultView(result: result, onRetry: {
                finishedRead = nil
                lastAutoScrolledWordIndex = 0
                Task { await viewModel.retryPassage() }
            }, onDone: {
                finishedRead = nil
                viewModel.reset()
                dismiss()
            })
        }
        .sheet(item: $selectedWord) { detail in
            WordDetailSheet(
                detail: detail,
                pronunciationService: pronunciationService,
                micActive: viewModel.isListening
            )
        }
        .alert(
            readAloudErrorNeedsSettings ? "Access Needed" : "Couldn't Start Read Aloud",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("Close", role: .cancel) {
                viewModel.reset()
                dismiss()
            }
            if readAloudErrorNeedsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } message: {
            Text(
                readAloudErrorNeedsSettings
                    ? "Check microphone and Speech Recognition access, then try again when you're ready."
                    : "Read Aloud couldn't start this time. Close this screen and try again when you're ready."
            )
        }
    }

    private var readAloudErrorNeedsSettings: Bool {
        viewModel.errorMessage?.localizedCaseInsensitiveContains("settings") == true
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

    /// Every word is drawn at one fixed weight, and nothing about a word's
    /// state may change its measured size.
    ///
    /// The current word used to render `.bold` while its neighbours stayed
    /// `.regular`. Bold glyphs are wider, so each time the cursor advanced the
    /// word under it grew, the word behind it shrank, and every word after
    /// them on the line re-flowed — the passage visibly squirmed as you read
    /// it. Position is carried by the highlight and the colour ramp instead,
    /// neither of which touches layout.
    private var passageText: some View {
        let words = passage.words
        let states = viewModel.wordStates

        return WrappingHStack(spacing: 6, lineSpacing: 12, metricsKey: passageFontSize) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let state = index < states.count ? states[index] : WordMatchState.upcoming
                Text(word)
                    .font(.system(size: passageFontSize, weight: Self.passageWeight, design: .default))
                    .foregroundStyle(wordColor(state))
                    .underline(state.needsAttention)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                    .background {
                        if state == .current {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColors.primary.opacity(0.28))
                        }
                    }
                    .onTapGesture {
                        guard state.isSettled else { return }
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

    private func wordColor(_ state: WordMatchState) -> Color {
        switch state {
        case .upcoming: return .white.opacity(0.45)
        case .current: return .white
        case .matched: return AppColors.success
        case .mismatched: return AppColors.error
        case .skipped: return AppColors.warning
        }
    }


    private var accuracyColor: Color {
        // Accuracy is a score, so it rides the score ramp rather than the
        // state colors — a 70 is not a "warning".
        AppColors.scoreColor(for: Int(viewModel.accuracyPercentage))
    }

    // MARK: - Bottom Controls


    /// Neither button may be disabled while the model line plays.
    ///
    /// Both used to carry `.disabled(pronunciationService.isSpeaking)`, which
    /// is precisely when someone wants them: the only way to skip the voiceover
    /// was to sit through the voiceover. "Start speaking" now stops the
    /// synthesiser and opens the mic immediately, and the secondary button
    /// becomes Stop while audio is playing.
    private var shadowControls: some View {
        let isSpeaking = pronunciationService.isSpeaking

        return VStack(spacing: 10) {
            Text(isSpeaking ? "Listen, then speak it back" : "Ready when you are")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 12) {
                GlassButton(
                    title: isSpeaking ? "Stop" : "Hear again",
                    style: .secondary,
                    size: .medium
                ) {
                    Haptics.light()
                    if isSpeaking {
                        pronunciationService.stop()
                    } else {
                        pronunciationService.speak(text: passage.text, rate: 0.42)
                    }
                }
                .accessibilityLabel(isSpeaking ? "Stop the model reading" : "Hear the model reading again")

                GlassButton(
                    title: isSpeaking ? "Skip & speak" : "Start speaking",
                    style: .primary,
                    size: .medium
                ) {
                    Haptics.medium()
                    pronunciationService.stop()
                    awaitingShadowStart = false
                    Task {
                        await viewModel.startSession(passage: passage)
                        lastAutoScrolledWordIndex = 0
                    }
                }
                .accessibilityLabel(
                    isSpeaking
                        ? "Skip the model reading and start speaking"
                        : "Start speaking"
                )
            }
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            if awaitingShadowStart {
                shadowControls
            }

            HStack(spacing: 20) {
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
                .disabled(!viewModel.isListening || awaitingShadowStart)
                .opacity(viewModel.isListening ? 1 : 0.5)
            }
        }
    }
}

// MARK: - Wrapping HStack (Flow Layout)

/// Flow layout for the passage. Caches its measurement pass.
///
/// `sizeThatFits` and `placeSubviews` each used to re-measure every subview
/// from scratch, and SwiftUI calls both on every pass. A 150-word passage
/// therefore cost ~300 text measurements per pass, and a pass ran on every
/// partial recognition result — several times a second, on the main actor,
/// for the whole read. That is what pinned the main thread and let recognition
/// tasks pile up behind it. Now the sizes and positions are computed once per
/// (width, font size) and reused, so a state change that only repaints colour
/// costs no measurement at all.
struct WrappingHStack: Layout {
    // No `alignment`: rows are packed from the leading edge, and the property
    // that used to sit here was set by every call site and read by none.
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4
    /// Anything that changes a subview's measured size must change this, or
    /// the cache will hand back stale geometry. Today that is the Dynamic Type
    /// scaled font size; the word states deliberately do not affect metrics.
    var metricsKey: CGFloat = 0

    struct Cache {
        var width: CGFloat?
        var metricsKey: CGFloat?
        var count: Int = 0
        /// Measured size of the first subview when the cache was filled. Cheap
        /// tripwire for anything that changes glyph metrics without changing
        /// the subview count — a Dynamic Type change on a caller that does not
        /// pass a `metricsKey`, for instance.
        var probe: CGSize?
        var positions: [CGPoint] = []
        var size: CGSize = .zero
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        // Only the things that move geometry invalidate. A repaint of the same
        // words keeps the cached pass.
        if cache.count != subviews.count || cache.metricsKey != metricsKey {
            cache = Cache()
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        resolve(proposal: proposal, subviews: subviews, cache: &cache)
        return cache.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        resolve(proposal: proposal, subviews: subviews, cache: &cache)
        for (index, subview) in subviews.enumerated() {
            guard index < cache.positions.count else { break }
            let position = cache.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func resolve(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let maxWidth = proposal.width ?? .infinity

        if cache.width == maxWidth,
           cache.metricsKey == metricsKey,
           cache.count == subviews.count,
           let probe = cache.probe,
           let first = subviews.first,
           first.sizeThatFits(.unspecified) == probe {
            return
        }

        var positions: [CGPoint] = []
        positions.reserveCapacity(subviews.count)
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

        cache.width = maxWidth
        cache.metricsKey = metricsKey
        cache.count = subviews.count
        cache.probe = subviews.first?.sizeThatFits(.unspecified)
        cache.positions = positions
        cache.size = CGSize(width: maxX, height: currentY + lineHeight)
    }
}
