import SwiftUI

// MARK: - Session Feedback Gate Store
//
// Shared, MainActor-isolated set of recording IDs whose post-recording feedback
// gate has already been handled (submitted or skipped). Used to coordinate
// between the pre-navigation gate shown inside RecordingView and the fallback
// gate inside RecordingDetailView so the user is not prompted twice.

@MainActor
@Observable
final class SessionFeedbackGateStore {
    static let shared = SessionFeedbackGateStore()
    private var dismissedIds: Set<UUID> = []
    private init() {}

    static func markDismissed(_ id: UUID) {
        shared.dismissedIds.insert(id)
    }

    static func isDismissed(_ id: UUID) -> Bool {
        shared.dismissedIds.contains(id)
    }

    static func reopen(_ id: UUID) {
        shared.dismissedIds.remove(id)
    }
}

struct AnalyzingView: View {
    let recording: Recording
    var isDownloadingModel: Bool = false
    var feedbackEnabled: Bool = false
    var feedbackQuestions: [FeedbackQuestion] = []
    var existingFeedback: SessionFeedback? = nil
    var onFeedbackSubmitted: ((SessionFeedback) -> Void)? = nil
    var onFeedbackCompleted: (() -> Void)? = nil
    /// Available when this view sits inside the full-screen recorder. Detail
    /// navigation already has a Back button, so that call site leaves this nil.
    var onSaveAndClose: (() -> Void)? = nil
    var analysisReady: Bool = false
    /// False once the analysis job has stopped, scored or not. Lets the
    /// self-check hand over to results when scoring failed, instead of waiting
    /// on a score that is never coming.
    var isStillProcessing: Bool = true
    /// The full-screen recorder keeps the reader on the check-in after the
    /// last answer, until the score lands, and then hands over by itself. The
    /// detail screen gates only once the score exists, so it hands over at once.
    var waitsForScore: Bool = false

    @State private var currentTipIndex = 0
    @State private var showTip = true
    @State private var progressStage = 0

    // Self-check state - typed dictionaries for proper Equatable tracking
    @State private var scaleAnswers: [UUID: Int] = [:]
    @State private var boolAnswers: [UUID: Bool] = [:]
    @State private var questionIndex = 0
    @State private var pageEdge: Edge = .trailing
    @State private var isWrappingUp = false
    @State private var submittedHere = false
    @State private var isDismissed = false
    @State private var hasHandedOver = false
    @State private var pendingAdvance: Task<Void, Never>?
    @State private var pendingHandOver: Task<Void, Never>?

    /// The take's own loudness shape, decoded once off the main actor.
    @State private var takeShape: [CGFloat] = []
    @State private var waitStartedAt = Date.now

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Long enough to see the answer land before the card moves on; short
    /// enough that the card never feels like it is waiting on you.
    private static let advanceDelay: Duration = .milliseconds(450)
    /// The "score is ready" beat before handing over, so the ready state is
    /// seen rather than flashed.
    private static let handOverBeat: Duration = .milliseconds(1400)

    private var showsSelfCheck: Bool {
        feedbackEnabled && !feedbackQuestions.isEmpty && !isDismissed
            && (existingFeedback == nil || submittedHere)
    }

    private var scoreSettled: Bool { analysisReady || !isStillProcessing }

    private var currentQuestion: FeedbackQuestion? {
        feedbackQuestions.indices.contains(questionIndex) ? feedbackQuestions[questionIndex] : nil
    }

    private func isAnswered(_ question: FeedbackQuestion) -> Bool {
        question.type == .scale ? scaleAnswers[question.id] != nil : boolAnswers[question.id] != nil
    }

    /// True when answering this question finishes the check-in.
    private func isLastOpen(_ question: FeedbackQuestion) -> Bool {
        !feedbackQuestions.contains { $0.id != question.id && !isAnswered($0) }
    }

    /// Only a device that has never had Apple's speech model downloads it,
    /// once. Saying so is what keeps that one slow first run from reading as
    /// a hang.
    private var statusTitle: String {
        isDownloadingModel ? "Downloading Speech Model..." : stages[progressStage]
    }

    private var statusSubtitle: String {
        isDownloadingModel
            ? "One-time download. Your recording is already saved, leave this screen and it will score itself when the download finishes."
            : "Your recording is safe. Scoring usually takes a moment."
    }

    private let stages = [
        "Transcribing your speech...",
        "Detecting filler words...",
        "Analyzing pace & pauses...",
        "Scoring your delivery..."
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let onSaveAndClose {
                HStack {
                    Button("Save & close", systemImage: "xmark") {
                        Haptics.light()
                        onSaveAndClose()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .accessibilityHint("Your recording stays in History and scoring continues")

                    Spacer()
                }
                // Plain 8pt. Nothing in this screen's chain ignores the safe
                // area - both hosts (`RecordingView`'s cover, the detail
                // screen's `NavigationStack`) inset their content already, so
                // the `keyWindow.safeAreaInsets.top` this used to add was
                // counted twice. That error scaled with the device: +20pt on
                // an SE, +59 here, +62 on a Pro Max, which is why the control
                // sat a different amount too low on every iPhone. Let the
                // layout supply the inset; it already knows the number.
                .padding(.top, 8)
                .padding(.horizontal, 20)
            }

            if showsSelfCheck {
                selfCheckContent
                selfCheckBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                progressContent
            }
        }
        .animation(.spring(response: 0.35), value: showsSelfCheck)
        .task { await cycleTips() }
        .task { await cycleStages() }
        .task { await loadTakeShape() }
        .onChange(of: scoreSettled) { _, settled in
            if settled { scheduleHandOverIfWrappedUp() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: analysisReady) { _, ready in
            ready && showsSelfCheck
        }
        .onDisappear {
            pendingAdvance?.cancel()
            pendingAdvance = nil
            pendingHandOver?.cancel()
            pendingHandOver = nil
        }
    }

    private var progressContent: some View {
        DetailSkeletonView(
            recording: recording,
            statusTitle: statusTitle,
            statusSubtitle: statusSubtitle,
            stage: progressStage,
            currentTipIndex: currentTipIndex,
            tipVisible: showTip
        )
    }

    // MARK: - Self-Check
    //
    // This screen exists to make the wait feel shorter. What it leans on:
    // occupied time passes faster than empty time (one small, tactile question
    // at a time); a wait with visible progress feels shorter than an open-ended
    // one (the take's own waveform filling as the progress bar, finishing only
    // when the score does); and the take is acknowledged as done before
    // anything is asked. The last answer sets up the reveal - your call against
    // the score - so the remaining wait is anticipation, not dead air.
    //
    // Layout: the question owns the page, with no card around it. Scoring
    // status lives in the floating dock at the bottom, beside the one action,
    // so the two things competing for attention are never stacked together.

    private var selfCheckContent: some View {
        // Always scroll - a custom question can overflow a small phone once
        // Dynamic Type climbs.
        PageScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if feedbackQuestions.count > 1 || isWrappingUp {
                    stepSegments
                }

                takeSavedLine

                ZStack(alignment: .topLeading) {
                    if isWrappingUp {
                        wrapUpPage
                            .transition(pageTransition)
                    } else if let question = currentQuestion {
                        questionPage(question)
                            .id(question.id)
                            .transition(pageTransition)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Header

    /// The acknowledgement, kept to one line so the question gets the page.
    private var takeSavedLine: some View {
        Label {
            Text("Take saved · \(recording.actualDuration.minutesSeconds)")
        } icon: {
            Image(systemName: "checkmark")
        }
        .eyebrowStyle(AppColors.success)
        .accessibilityLabel("Take saved, \(recording.actualDuration.minutesSeconds). The hard part's done.")
    }

    // MARK: Scoring Status

    private var liveStatusTitle: String {
        if analysisReady { return "Your score is ready" }
        if !isStillProcessing { return "Scoring stopped" }
        if isDownloadingModel { return statusTitle }
        return stages[progressStage]
    }

    private var liveStatusSubtitle: String {
        if analysisReady {
            return isWrappingUp ? "Opening it now." : "Finish up, or jump straight to it."
        }
        if !isStillProcessing { return "Open your results to see what happened." }
        if isDownloadingModel { return statusSubtitle }
        return "Reading your \(recording.actualDuration.minutesSeconds) take word by word."
    }

    private var statusTint: Color {
        if analysisReady { return AppColors.success }
        if !isStillProcessing { return AppColors.warning }
        return AppColors.primary
    }

    /// A guess, and only used to pace the waveform's fill: transcription and
    /// pitch scale with the take, a first-run model download adds its own time.
    private var expectedWait: TimeInterval {
        let base = max(4, recording.actualDuration * 0.08 + 3)
        return isDownloadingModel ? base + 20 : base
    }

    private var scoringStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 7, height: 7)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(liveStatusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)

                    Text(liveStatusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            // The waveform is the progress bar. A take with no level
            // samples draws `TakeWaveform.flat`, so the bar never vanishes.
            TakeWaveform(
                levels: takeShape,
                mode: .estimate(startedAt: waitStartedAt, expected: expectedWait),
                isComplete: scoreSettled,
                tint: statusTint
            )
            .frame(height: 32)
        }
        .motion(AppMotion.settle, value: scoreSettled)
        .accessibilityElement(children: .combine)
    }

    // MARK: Question Page

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: pageEdge).combined(with: .opacity),
            removal: .move(edge: pageEdge == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func questionPage(_ question: FeedbackQuestion) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(question.text)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Group {
                if question.type == .scale {
                    // The wheel does not move the page on by itself: one
                    // swipe rarely lands on the far end, and a page that
                    // leaves on release took the second swipe away. Next
                    // commits instead.
                    VStack(spacing: 12) {
                        FeelingDial(
                            question: question.text,
                            options: takeFeelings,
                            // Answers are stored 1...5; the dial counts from 0.
                            selected: scaleAnswers[question.id].map { $0 - 1 },
                            onSelect: { index in
                                withAnimation(AppMotion.snap) {
                                    scaleAnswers[question.id] = index + 1
                                }
                            }
                        )
                        // Full bleed: the wheel is meant to run off the screen.
                        .padding(.horizontal, -20)

                        GlassButton(
                            title: isLastOpen(question) ? "Save check-in" : "Next",
                            icon: "arrow.right",
                            iconPosition: .right,
                            style: .primary,
                            fullWidth: true
                        ) {
                            Haptics.light()
                            pendingAdvance?.cancel()
                            advance()
                        }
                        .disabled(scaleAnswers[question.id] == nil || hasHandedOver)
                        .opacity(scaleAnswers[question.id] == nil ? 0.4 : 1)
                        .motion(AppMotion.settle, value: scaleAnswers[question.id] == nil)
                    }
                } else {
                    YesNoInput(
                        selected: boolAnswers[question.id],
                        onSelect: { value in
                            Haptics.selection()
                            withAnimation(AppMotion.snap) {
                                boolAnswers[question.id] = value
                            }
                            answered()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Story-style segments: one per question, tappable to go back. Filled
    /// through the current one; all filled once the check-in is saved.
    private var stepSegments: some View {
        HStack(spacing: 6) {
            ForEach(Array(feedbackQuestions.enumerated()), id: \.element.id) { index, question in
                Button {
                    Haptics.selection()
                    pendingAdvance?.cancel()
                    go(to: index)
                } label: {
                    Capsule()
                        .fill(segmentColor(index: index, question: question))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isWrappingUp)
                .accessibilityLabel("Question \(index + 1) of \(feedbackQuestions.count)")
                .accessibilityValue(isAnswered(question) ? "Answered" : "Not answered")
            }
        }
        .motion(AppMotion.slide, value: questionIndex)
        .motion(AppMotion.slide, value: isWrappingUp)
    }

    private func segmentColor(index: Int, question: FeedbackQuestion) -> Color {
        if isWrappingUp || index == questionIndex { return .white }
        return isAnswered(question) ? .white.opacity(0.45) : .white.opacity(0.12)
    }

    // MARK: Wrap-Up

    /// What the reader said, played back as the setup for the reveal. Coach
    /// tone, not reassurance (recording-detail invariant 12a): the hook is the
    /// comparison, which is a real question the score is about to answer.
    private var wrapUpLine: String {
        let scale = feedbackQuestions
            .first(where: { $0.type == .scale })
            .flatMap { scaleAnswers[$0.id] }
        switch scale {
        case .some(...2):
            return "Takes that feel rough often score better than they felt. Let's see where this one lands."
        case .some(3):
            return "Middle of the road, by your call. Let's see what the score says."
        case .some:
            return "Felt good to you. Let's see if the score agrees."
        case .none:
            return "Your answers sit next to the score, so you can see how your read compares."
        }
    }

    private var wrapUpPage: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Check-in saved")
                    .eyebrowStyle()

                Text(wrapUpLine)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if !scoreSettled {
                let tip = MotivationalTipCard.tips[currentTipIndex]
                VStack(alignment: .leading, spacing: 6) {
                    Text("While you wait")
                        .eyebrowStyle()
                    Text(tip.text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(showTip ? 1 : 0)
                        .animation(.easeInOut(duration: 0.4), value: showTip)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Bottom Dock

    /// Scoring status and the one action share a floating panel, so the wait
    /// is always in view without competing with the question for the page.
    private var selfCheckBottomBar: some View {
        VStack(spacing: 14) {
            scoringStatus

            if scoreSettled {
                GlassButton(
                    title: analysisReady ? "See your score" : "See results",
                    icon: "arrow.right",
                    iconPosition: .right,
                    style: .primary,
                    fullWidth: true
                ) {
                    handOverNow()
                }
                .disabled(hasHandedOver)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Button {
                    handOverNow()
                } label: {
                    Text(isWrappingUp ? "Open results now" : "Skip to results")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressStyle())
                .disabled(hasHandedOver)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .motion(AppMotion.settle, value: scoreSettled)
        .motion(AppMotion.settle, value: isWrappingUp)
    }

    // MARK: - Flow

    /// Every answer moves the card on after a short beat, so the choice has
    /// time to register. A second answer inside the beat restarts it, which is
    /// what lets someone change their mind without the card running away.
    private func answered() {
        guard !isWrappingUp, !hasHandedOver else { return }
        pendingAdvance?.cancel()
        pendingAdvance = Task { @MainActor in
            try? await Task.sleep(for: Self.advanceDelay)
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    private func advance() {
        if questionIndex + 1 < feedbackQuestions.count {
            go(to: questionIndex + 1)
        } else if let firstOpen = feedbackQuestions.firstIndex(where: { !isAnswered($0) }) {
            go(to: firstOpen)
        } else {
            submitFeedback()
        }
    }

    private func go(to index: Int) {
        guard index != questionIndex, feedbackQuestions.indices.contains(index) else { return }
        pageEdge = index > questionIndex ? .trailing : .leading
        withAnimation(AppMotion.slide) {
            questionIndex = index
        }
    }

    /// Only the questions that have an answer. A partly answered check-in is
    /// still worth keeping; skipping used to throw it away.
    private var givenAnswers: [FeedbackAnswer] {
        feedbackQuestions.compactMap { question in
            switch question.type {
            case .scale:
                guard let value = scaleAnswers[question.id] else { return nil }
                return FeedbackAnswer(
                    questionId: question.id,
                    questionText: question.text,
                    type: .scale,
                    scaleValue: value
                )
            case .yesNo:
                guard let value = boolAnswers[question.id] else { return nil }
                return FeedbackAnswer(
                    questionId: question.id,
                    questionText: question.text,
                    type: .yesNo,
                    boolValue: value
                )
            }
        }
    }

    private func submitFeedback() {
        pendingAdvance?.cancel()
        guard !submittedHere else { return }
        saveAnswers()
        Haptics.success()

        guard waitsForScore else {
            handOver()
            return
        }
        pageEdge = .trailing
        withAnimation(AppMotion.slide) {
            isWrappingUp = true
        }
        scheduleHandOverIfWrappedUp()
    }

    private func saveAnswers() {
        let answers = givenAnswers
        guard !submittedHere, !answers.isEmpty else { return }
        submittedHere = true
        AnalyticsService.shared.log(.sessionFeedback(sentiment: sentiment(of: answers)))
        onFeedbackSubmitted?(SessionFeedback(answers: answers))
    }

    private func scheduleHandOverIfWrappedUp() {
        guard isWrappingUp, scoreSettled, pendingHandOver == nil, !hasHandedOver else { return }
        pendingHandOver = Task { @MainActor in
            try? await Task.sleep(for: Self.handOverBeat)
            guard !Task.isCancelled else { return }
            handOver()
        }
    }

    /// "Skip to results" and "See your score": keep whatever was answered,
    /// then go.
    private func handOverNow() {
        Haptics.light()
        pendingAdvance?.cancel()
        saveAnswers()
        handOver()
    }

    private func handOver() {
        guard !hasHandedOver else { return }
        hasHandedOver = true
        pendingAdvance?.cancel()
        pendingHandOver?.cancel()
        // The recorder replaces this whole view when it moves on; dropping the
        // check-in first would flash the skeleton for a frame.
        if !waitsForScore {
            withAnimation(.spring(response: 0.3)) {
                isDismissed = true
            }
        }
        onFeedbackCompleted?()
    }

    /// Collapses the answer set to one word. A scale answer wins when present
    /// because it is the closest thing to "how did that go"; a yes/no answer is
    /// the fallback. Nothing answered reports as unrated rather than positive.
    private func sentiment(of answers: [FeedbackAnswer]) -> String {
        if let scale = answers.compactMap(\.scaleValue).first {
            return AnalyticsBucket.sentiment(scale: scale)
        }
        if let yesNo = answers.compactMap(\.boolValue).first {
            return yesNo ? "positive" : "negative"
        }
        return "unrated"
    }

    // MARK: - Animations (task-based, auto-cancelled on disappear)

    /// The samples are a JSON blob; decoding runs off the main actor.
    private func loadTakeShape() async {
        guard takeShape.isEmpty, let data = recording.audioLevelSamplesData else { return }
        let bars = await Task.detached(priority: .userInitiated) {
            TakeWaveform.levels(fromDecibels: (try? JSONDecoder().decode([Float].self, from: data)) ?? [])
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(AppMotion.settle) { takeShape = bars }
    }

    private func cycleTips() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { showTip = false }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            currentTipIndex = (currentTipIndex + 1) % MotivationalTipCard.tips.count
            withAnimation { showTip = true }
        }
    }

    /// Walks the stages once and holds on the last. It used to wrap back to
    /// "Transcribing" after "Scoring", which read as the analysis restarting.
    /// The pipeline reports no real stage, so the pace scales with the take:
    /// a ten-minute take transcribes far longer than a thirty-second one.
    private func cycleStages() async {
        let interval = max(2.5, recording.actualDuration / 15)
        while progressStage < stages.count - 1 {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3)) {
                progressStage += 1
            }
        }
    }
}

// MARK: - Take Feelings

/// The self-check's scale, low to high, for `FeelingDial`.
private let takeFeelings: [FeelingDial.Option] = [
    .init(label: "Rough", line: "Hard going this time"),
    .init(label: "Shaky", line: "Got through it"),
    .init(label: "Okay", line: "Middle of the road"),
    .init(label: "Good", line: "Felt solid"),
    .init(label: "Great", line: "In the zone"),
]

// MARK: - Yes/No Input (extracted subview)

/// Two large round answers, side by side. Selected is the solid white pill
/// treatment the rest of the app uses for a chosen option; no polarity
/// colours, since "no" is not a bad answer to "did it make sense?".
private struct YesNoInput: View {
    let selected: Bool?
    let onSelect: (Bool) -> Void

    var body: some View {
        HStack(spacing: 28) {
            optionButton(label: "No", icon: "hand.thumbsdown.fill", value: false)
            optionButton(label: "Yes", icon: "hand.thumbsup.fill", value: true)
        }
        .padding(.top, 12)
    }

    private func optionButton(label: String, icon: String, value: Bool) -> some View {
        let isSelected = selected == value

        return Button { onSelect(value) } label: {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(red: 0.07, green: 0.07, blue: 0.08) : .white.opacity(0.8))
                    .symbolEffect(.bounce, value: isSelected)
                    .frame(width: 96, height: 96)
                    .background {
                        Circle()
                            .fill(isSelected ? Color.white : AppColors.surfaceLift)
                            .overlay {
                                Circle().strokeBorder(isSelected ? .clear : AppColors.cardStroke, lineWidth: 1)
                            }
                    }

                Text(label)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Progress Dots (extracted subview)

private struct AnalyzingProgressDots: View {
    let stage: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i <= stage ? AppColors.primary : Color.white.opacity(0.15))
                    .frame(width: i == stage ? 24 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.4), value: stage)
    }
}

// MARK: - Motivational Tip Card (extracted subview)

private struct MotivationalTipCard: View {
    let tipIndex: Int
    let isVisible: Bool

    static let tips = [
        (icon: "checkmark.circle.fill", text: "Your recording is already saved. Scoring can take a moment."),
        (icon: "timer", text: "Short sessions count. Consistency matters more than length."),
        (icon: "headphones", text: "Listening back once can reveal patterns that are hard to hear live."),
        (icon: "text.bubble", text: "While you wait: name your top filler. Next take, swap it for a pause."),
        (icon: "speedometer", text: "Pace tip: breathe at sentence ends. That alone pulls many speakers onto target."),
        (icon: "pause.circle", text: "A one-beat pause after a key point is a technique, not a stall."),
        (icon: "list.bullet", text: "Structure tip: lead with the point, then the reason. Use PREP in two moves."),
        (icon: "scope", text: "One adjustment per take beats chasing every score at once.")
    ]

    var body: some View {
        let tip = Self.tips[tipIndex]
        FeaturedGlassCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: tip.icon)
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.primary, AppColors.categoryBrandBright],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32)

                Text(tip.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: isVisible)
    }
}

// MARK: - Detail Skeleton View

private struct DetailSkeletonView: View {
    let recording: Recording
    let statusTitle: String
    let statusSubtitle: String
    let stage: Int
    let currentTipIndex: Int
    let tipVisible: Bool

    /// The take's own loudness shape, decoded once - `audioLevelSamples`
    /// parses JSON on every access, so it never runs from `body`.
    @State private var takeShape: [CGFloat] = []

    var body: some View {
        PageScrollView {
            ShimmerHost {
                VStack(spacing: 20) {
                    statusHeader
                        .padding(.top, 8)

                    DetailContextStrip(recording: recording)

                    heroScoreSkeleton
                    nextStepSkeleton
                    tabPickerSkeleton
                    metricRowsSkeleton

                    MotivationalTipCard(tipIndex: currentTipIndex, isVisible: tipVisible)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
        .task {
            // Off the main actor, like the self-check's copy: a `.task` on a
            // view runs on it, and this is a JSON decode of the whole take.
            guard let data = recording.audioLevelSamplesData else { return }
            let bars = await Task.detached(priority: .userInitiated) {
                TakeWaveform.levels(fromDecibels: (try? JSONDecoder().decode([Float].self, from: data)) ?? [])
            }.value
            guard !Task.isCancelled else { return }
            takeShape = bars
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(spacing: 10) {
            // Duration lives in the context strip below - it was printed twice.
            HStack(spacing: 6) {
                VoiceLoader(size: .small)
                    .foregroundStyle(AppColors.primary)
                Text("Analyzing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule().fill(.ultraThinMaterial)
            }

            if !takeShape.isEmpty {
                TakeWaveform(levels: takeShape)
                    .frame(height: 56)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }

            VStack(spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .multilineTextAlignment(.center)

                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            AnalyzingProgressDots(stage: stage)
        }
        .motion(AppMotion.settle, value: takeShape.isEmpty)
    }

    // MARK: - Skeleton Sections

    private var heroScoreSkeleton: some View {
        GlassCard(padding: 16, elevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SkeletonBar(width: 84, height: 10)
                    Spacer()
                    SkeletonBar(width: 30, height: 30, cornerRadius: 15)
                }

                SkeletonDonut()
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)

                HStack {
                    Spacer()
                    SkeletonBar(width: 132, height: 13)
                    Spacer()
                }
            }
        }
    }

    private var nextStepSkeleton: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                SkeletonBar(width: 108, height: 10)
                SkeletonBar(width: 152, height: 19)
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBar(width: nil, height: 12)
                    SkeletonBar(width: 210, height: 12)
                }
                HStack(spacing: 10) {
                    SkeletonBar(width: nil, height: 46, cornerRadius: 23)
                    SkeletonBar(width: 46, height: 46, cornerRadius: 23)
                }
            }
        }
    }

    private var tabPickerSkeleton: some View {
        SectionPicker(
            sections: DetailTab.allCases,
            selection: .constant(.breakdown),
            label: { $0.rawValue },
            icon: { $0.icon }
        )
        .disabled(true)
        .opacity(0.4)
    }

    private var metricRowsSkeleton: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    if i > 0 { MetricRowDivider() }
                    SkeletonMetricRow(labelWidth: [46, 52, 58, 62][i])
                }
            }
        }
    }
}

// MARK: - Skeleton Primitives

private struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.08))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .shimmer()
    }
}

private struct SkeletonDonut: View {
    private let labelInset: CGFloat = 42
    private let axisCount = 6

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = (side / 2) - labelInset
            let inner = radius * 0.38

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: radius - inner)
                    .frame(width: radius + inner, height: radius + inner)

                SkeletonBar(width: 52, height: 30)
                    .frame(width: 52)

                ForEach(0..<axisCount, id: \.self) { i in
                    let angle = (Double(i) / Double(axisCount)) * 2 * .pi - .pi / 2
                    SkeletonBar(width: 36, height: 8)
                        .frame(width: 36)
                        .position(
                            x: center.x + cos(angle) * (radius + 20),
                            y: center.y + sin(angle) * (radius + 20)
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct SkeletonMetricRow: View {
    let labelWidth: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            SkeletonBar(width: 16, height: 16, cornerRadius: 4)
            SkeletonBar(width: labelWidth, height: 12)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                SkeletonBar(width: 44, height: 17)
                SkeletonBar(width: 56, height: 9)
            }
        }
    }
}
