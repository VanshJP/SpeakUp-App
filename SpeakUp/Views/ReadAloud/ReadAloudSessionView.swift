import SwiftUI
import UIKit

struct ReadAloudSessionView: View {
    @Bindable var viewModel: ReadAloudViewModel
    let passage: ReadAloudPassage
    @Environment(\.dismiss) private var dismiss
    /// The finished read, and the only state its cover reads. A
    /// `showingResult` flag over `viewModel.result` presented an empty cover
    /// whenever the two disagreed - and Retry clears the result while the flag
    /// is still coming down.
    @State private var finishedRead: ReadAloudResult?
    @State private var showingExitConfirm = false
    @State private var selectedWord: WordDetail?
    @State private var pronunciationService = PronunciationService()
    @State private var lastAutoScrolledWordIndex = 0
    @State private var didAutoStartSession = false
    /// The short passage "Drill what you missed" or a sound's Practice swaps
    /// in, run in this same cover. Nil while reading the passage the session
    /// opened on.
    @State private var drilledPassage: ReadAloudPassage?

    private var currentPassage: ReadAloudPassage { drilledPassage ?? passage }

    @ScaledMetric(relativeTo: .title2) private var passageFontSize: CGFloat = 22

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
                        ReadAloudPassageText(
                            words: currentPassage.words,
                            states: viewModel.wordStates,
                            fontSize: passageFontSize,
                            selectedWord: $selectedWord
                        )
                        // A new passage gets a new layout: the flow cache is
                        // keyed on word count and font size, which two
                        // passages can share.
                        .id(currentPassage.id)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                    .onChange(of: viewModel.currentWordIndex) { _, newIndex in
                        // A retry or a drill drops back to word 0: jump to
                        // the top whatever the last nudge was. Resetting the
                        // marker before the index fell made the guard below
                        // swallow this scroll, so a retry opened on the end of
                        // a long passage with the mic already live.
                        if newIndex == 0 {
                            lastAutoScrolledWordIndex = 0
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo("word_0", anchor: .top)
                            }
                            return
                        }
                        // Re-centring every second word meant the passage slid
                        // under the reader continuously - the other half of
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
        // A read is minutes of speaking without touching the glass - exactly
        // what Auto-Lock waits for. Locking mid-passage took the mic with it.
        .keepsScreenAwake(viewModel.sessionState == .listening)
        .task {
            guard !didAutoStartSession else { return }
            didAutoStartSession = true
            await viewModel.startSession(passage: passage)
            lastAutoScrolledWordIndex = 0
        }
        .onChange(of: pronunciationService.isSpeaking) { wasSpeaking, isSpeaking in
            // The model line ended, by finishing or by Stop. Either way the
            // mic comes back on the transcript it left.
            guard wasSpeaking, !isSpeaking else { return }
            viewModel.resumeAfterModel()
        }
        .onDisappear {
            if viewModel.sessionState == .listening {
                viewModel.stopSession()
            }
            pronunciationService.stop()
        }
        .onChange(of: viewModel.sessionState) { _, newState in
            guard newState == .finished, let result = viewModel.result else { return }
            finishedRead = result
            PracticeRoutineService.shared.complete(.readAloud)
        }
        .fullScreenCover(item: $finishedRead) { result in
            ReadAloudResultView(result: result, onRetry: {
                finishedRead = nil
                Task { await viewModel.retryPassage() }
            }, onDone: {
                finishedRead = nil
                viewModel.reset()
                dismiss()
            }, onPractice: { drill in
                finishedRead = nil
                drilledPassage = drill
                Task { await viewModel.startSession(passage: drill) }
            }, onReadFullPassage: readFullPassage)
        }
        .sheet(item: $selectedWord) { detail in
            // Mid-read, the word plays under the same hold as "Hear it". The
            // sheet used to say "Stop session to hear pronunciation", and
            // stopping scored the read - on a minimal pair, hearing the word
            // is the whole point.
            WordDetailSheet(
                detail: detail,
                pronunciationService: pronunciationService,
                onHear: {
                    playModel { pronunciationService.speak(word: detail.word) }
                }
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
            } else {
                // Same passage, no trip back to the list.
                Button("Try Again") {
                    Task { await viewModel.retryPassage() }
                }
            }
        } message: {
            Text(
                readAloudErrorNeedsSettings
                    ? "Check microphone and Speech Recognition access, then try again when you're ready."
                    : "Read Aloud couldn't start this time. Try again, or close and come back when you're ready."
            )
        }
    }

    private var readAloudErrorNeedsSettings: Bool {
        viewModel.errorMessage?.localizedCaseInsensitiveContains("settings") == true
    }

    /// Only a drill's result offers it: back to the passage the drill came
    /// from, to check the fix where it has to hold.
    private var readFullPassage: (() -> Void)? {
        guard drilledPassage != nil else { return nil }
        return {
            finishedRead = nil
            drilledPassage = nil
            Task { await viewModel.startSession(passage: passage) }
        }
    }

    /// Plays a model line with the read held: the mic goes down first, so the
    /// recogniser cannot score the synthesiser, and `onChange(of: isSpeaking)`
    /// brings it back on the same transcript when the line ends.
    private func playModel(_ play: () -> Void) {
        viewModel.pauseForModel()
        play()
        // Nothing to wait for if the synthesiser declined the text.
        if !pronunciationService.isSpeaking {
            viewModel.resumeAfterModel()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                Haptics.light()
                if viewModel.sessionState == .listening {
                    showingExitConfirm = true
                } else {
                    viewModel.stopSession()
                    viewModel.reset()
                    dismiss()
                }
            } label: {
                // The runner ✕ the warm-up and confidence screens wear.
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassCircle()
            }
            .buttonStyle(.plain)
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

            ReadAloudClock(viewModel: viewModel)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(accuracyColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text("\(Int(viewModel.accuracyPercentage))%")
                    .font(.statValue)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Accuracy \(Int(viewModel.accuracyPercentage)) percent")
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // MARK: - Progress Bar

    /// The app's determinate meter. A `Canvas` reads the fraction, so it is
    /// not animated (gotcha §28) - it steps a tick at a time.
    private var progressBar: some View {
        TickMeter(fraction: viewModel.progressPercentage, color: AppColors.primary)
            .frame(height: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Passage progress")
            .accessibilityValue("\(Int(viewModel.progressPercentage * 100)) percent")
    }

    private var accuracyColor: Color {
        // Accuracy is a score, so it rides the score ramp rather than the
        // state colors - a 70 is not a "warning".
        AppColors.scoreColor(for: Int(viewModel.accuracyPercentage))
    }

    // MARK: - Bottom Controls


    /// Shadow practice, as a control rather than a mode.
    ///
    /// It was a toggle at the top of the catalog that had to be flipped before
    /// the passage opened, which put it furthest from the moment it is wanted:
    /// mid-read, having just fumbled a line. Here it is one button, live for
    /// the whole session and on every passage. Pressing it holds the read -
    /// the mic goes down so the recogniser cannot score the synthesiser - and
    /// the words already matched are still there when it comes back.
    ///
    /// Never disabled while the model plays: that is exactly when someone
    /// reaches for it, and the only way past the voiceover used to be sitting
    /// through it. While speaking it reads Stop.
    ///
    /// It plays from the start of the sentence the reader is in, not from the
    /// top: someone who fumbled line five used to sit through lines one to
    /// four first. Before the first word that is the whole passage.
    private var hearItButton: some View {
        let isSpeaking = pronunciationService.isSpeaking

        return GlassButton(
            title: isSpeaking ? "Stop" : "Hear it",
            icon: isSpeaking ? "stop.fill" : "speaker.wave.2.fill",
            style: .secondary,
            size: .medium,
            fullWidth: true
        ) {
            Haptics.light()
            if isSpeaking {
                pronunciationService.stop()
            } else {
                let line = Self.modelLine(in: currentPassage.words, from: viewModel.currentWordIndex)
                playModel { pronunciationService.speak(text: line, rate: 0.42) }
            }
        }
        .accessibilityLabel(
            isSpeaking
                ? "Stop the model reading and go back to the mic"
                : "Hear the passage from this sentence. Your reading is held until it finishes."
        )
    }

    private var micStatus: (label: String, color: Color) {
        if viewModel.isStalled { return ("Mic stopped", AppColors.warning) }
        if viewModel.isHearingModel { return ("Hearing it", AppColors.toolReadAloud) }
        if viewModel.isHeldBySystem { return ("Paused", AppColors.scoreEmpty) }
        if viewModel.isListening { return ("Listening...", AppColors.success) }
        return ("Not listening", AppColors.scoreEmpty)
    }

    /// The mic stopped and could not be brought back automatically. The read
    /// is held, not lost: this used to end the session, and the only way on
    /// was to start the passage again from the first word.
    private var stalledNotice: some View {
        VStack(spacing: 10) {
            Text("The mic stopped. Your place is saved, so you can pick up where you left off.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            GlassButton(
                title: "Resume reading",
                icon: "mic.fill",
                style: .primary,
                size: .medium,
                fullWidth: true
            ) {
                Haptics.medium()
                viewModel.resumeListening()
            }
            .accessibilityLabel("Resume reading from where you stopped")
        }
    }

    private var bottomControls: some View {
        let status = micStatus

        return VStack(spacing: 12) {
            if viewModel.isStalled {
                stalledNotice
            } else {
                hearItButton
                    .disabled(!viewModel.isListening)
                    .opacity(viewModel.isListening ? 1 : 0.5)
            }

            HStack(spacing: 20) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(status.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Microphone \(status.label)")

                Spacer(minLength: 8)

                // One white button at a time: while the mic is stalled,
                // Resume reading is the primary and Done steps back.
                GlassButton(
                    title: "Done",
                    icon: "stop.fill",
                    style: viewModel.isStalled ? .secondary : .primary,
                    size: .medium
                ) {
                    Haptics.medium()
                    pronunciationService.stop()
                    viewModel.stopSession()
                }
                .disabled(!viewModel.isListening)
                .opacity(viewModel.isListening ? 1 : 0.5)
            }
        }
    }
}

// MARK: - Model Line

extension ReadAloudSessionView {
    /// The passage from the start of the sentence holding `index` to the end.
    /// "Hear it" plays this; Stop hands the mic back whenever the reader has
    /// heard enough. An abbreviation reads as a sentence end, which only
    /// starts the line a few words late.
    static func modelLine(in words: [String], from index: Int) -> String {
        guard !words.isEmpty else { return "" }
        var start = min(max(index, 0), words.count - 1)
        while start > 0, !endsSentence(words[start - 1]) {
            start -= 1
        }
        return words[start...].joined(separator: " ")
    }

    private static func endsSentence(_ word: String) -> Bool {
        // Closing quotes and brackets sit outside the full stop: `end."`
        let closers = CharacterSet(charactersIn: "\"')]\u{201D}\u{2019}")
        guard let last = word.trimmingCharacters(in: closers).last else { return false }
        return ".!?\u{2026}".contains(last)
    }
}

// MARK: - Clock

/// Reads `elapsedTime` in its own body, so the tick redraws this capsule and
/// not the session screen. Read from the session view, a clock that wrote four
/// times a second rebuilt every word of the passage four times a second.
private struct ReadAloudClock: View {
    let viewModel: ReadAloudViewModel

    var body: some View {
        let elapsed = viewModel.formattedElapsedTime

        Text(elapsed)
            .font(.statValue)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .accessibilityLabel("Elapsed \(elapsed)")
    }
}

// MARK: - Passage Text

/// The passage, one view per word. Its own view so a session-screen pass that
/// changes neither the words nor their states skips the rebuild.
///
/// Every word is drawn at one fixed weight, and nothing about a word's state
/// may change its measured size. The current word used to render `.bold`
/// while its neighbours stayed `.regular`. Bold glyphs are wider, so each time
/// the cursor advanced the word under it grew, the word behind it shrank, and
/// every word after them on the line re-flowed - the passage visibly squirmed
/// as you read it. Position is carried by the highlight and the colour ramp
/// instead, neither of which touches layout.
private struct ReadAloudPassageText: View {
    let words: [String]
    let states: [WordMatchState]
    let fontSize: CGFloat
    @Binding var selectedWord: WordDetail?

    private static let weight: Font.Weight = .semibold

    var body: some View {
        WrappingHStack(spacing: 6, lineSpacing: 12, metricsKey: fontSize) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let state = index < states.count ? states[index] : WordMatchState.upcoming
                Text(word)
                    .font(.system(size: fontSize, weight: Self.weight, design: .default))
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
                    // A read word opens its sheet, so VoiceOver says so.
                    .accessibilityAddTraits(state.isSettled ? .isButton : [])
                    .accessibilityHidden(state == .upcoming)
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
}

// MARK: - Wrapping HStack (Flow Layout)

/// Flow layout for the passage. Caches its measurement pass.
///
/// `sizeThatFits` and `placeSubviews` each used to re-measure every subview
/// from scratch, and SwiftUI calls both on every pass. A 150-word passage
/// therefore cost ~300 text measurements per pass, and a pass ran on every
/// partial recognition result - several times a second, on the main actor,
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
        /// the subview count - a Dynamic Type change on a caller that does not
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
