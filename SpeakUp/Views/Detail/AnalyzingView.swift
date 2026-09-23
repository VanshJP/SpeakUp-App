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
    let isModelLoading: Bool
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

    /// A first load is a ~150 MB download; every load after it takes seconds.
    /// Showing the same spinner for both is what makes a slow first run read as
    /// a hang rather than a download.
    private var isFirstTimeModelDownload: Bool {
        isDownloadingModel && !WhisperService.hasCompletedFirstLoad
    }

    private var statusTitle: String {
        if isFirstTimeModelDownload { return "Downloading Speech Model..." }
        return isModelLoading ? "Preparing Speech Engine..." : stages[progressStage]
    }

    private var statusSubtitle: String {
        if isFirstTimeModelDownload {
            return "One-time download, about 150 MB. Your recording is already saved, leave this screen and it will score itself when the download finishes."
        }
        return isModelLoading
            ? "Warming up the speech engine"
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
    // one (the take's own waveform being scanned, and a bar that only finishes
    // when the score does); and the take is acknowledged as done before
    // anything is asked. The last answer sets up the reveal - your call against
    // the score - so the remaining wait is anticipation, not dead air.

    private var selfCheckContent: some View {
        // Always scroll - the header, status card and a custom question can
        // overflow a small phone once Dynamic Type climbs.
        PageScrollView {
            VStack(spacing: 16) {
                takeSavedHeader
                    .padding(.top, 4)

                scoringStatusCard

                selfCheckCard

                if isWrappingUp && !scoreSettled {
                    MotivationalTipCard(tipIndex: currentTipIndex, isVisible: showTip)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Header

    private var takeSavedHeader: some View {
        VStack(spacing: 6) {
            SavedSeal()

            Text("Take saved")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("\(recording.actualDuration.minutesSeconds) on the record. The hard part's done.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Scoring Status

    private var liveStatusTitle: String {
        if analysisReady { return "Your score is ready" }
        if !isStillProcessing { return "Scoring stopped" }
        if isFirstTimeModelDownload || isModelLoading { return statusTitle }
        return stages[progressStage]
    }

    private var liveStatusSubtitle: String {
        if analysisReady {
            return isWrappingUp ? "Opening it now." : "Finish up, or jump straight to it."
        }
        if !isStillProcessing { return "Open your results to see what happened." }
        if isFirstTimeModelDownload || isModelLoading { return statusSubtitle }
        return "Reading your \(recording.actualDuration.minutesSeconds) take word by word."
    }

    private var statusTint: Color {
        if analysisReady { return AppColors.success }
        if !isStillProcessing { return AppColors.warning }
        return AppColors.primary
    }

    private var statusIcon: String {
        if analysisReady { return "checkmark" }
        if !isStillProcessing { return "exclamationmark" }
        return "waveform"
    }

    /// A guess, and only used to pace the bar: transcription scales with the
    /// take, and a model that is still loading adds a few seconds on top.
    private var expectedWait: TimeInterval {
        let base = max(6, recording.actualDuration * 0.35 + 4)
        return isModelLoading || isDownloadingModel ? base + 8 : base
    }

    private var scoringStatusCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusTint)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !scoreSettled)
                        .frame(width: 32, height: 32)
                        .background { Circle().fill(statusTint.opacity(0.18)) }

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

                if !takeShape.isEmpty {
                    TakeScanView(bars: takeShape, isComplete: scoreSettled)
                        .frame(height: 40)
                        .transition(.opacity)
                }

                EstimatedProgressBar(
                    startedAt: waitStartedAt,
                    expected: expectedWait,
                    isComplete: scoreSettled,
                    tint: statusTint
                )
                .frame(height: 4)
            }
        }
        .motion(AppMotion.settle, value: scoreSettled)
        .accessibilityElement(children: .combine)
    }

    // MARK: Question Card

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: pageEdge).combined(with: .opacity),
            removal: .move(edge: pageEdge == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var selfCheckCard: some View {
        FeaturedGlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: isWrappingUp ? "checkmark.message.fill" : "checkmark.message")
                        .font(.body)
                        .foregroundStyle(AppColors.primary)
                        .contentTransition(.symbolEffect(.replace))

                    Text("Quick self-check")
                        .font(.footnote.weight(.semibold))

                    Spacer()

                    if !isWrappingUp, feedbackQuestions.count > 1 {
                        Text("\(questionIndex + 1) of \(feedbackQuestions.count)")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }

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
                // Pages slide inside the card, not across the whole screen.
                // The clip reaches out to the card's own edge (its 16pt
                // padding), so the slider thumb's glow is not cut at the ends.
                .clipShape(Rectangle().inset(by: -16))

                if !isWrappingUp, feedbackQuestions.count > 1 {
                    stepDots
                }
            }
        }
    }

    @ViewBuilder
    private func questionPage(_ question: FeedbackQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.text)
                .font(.headline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if question.type == .scale {
                FeelingSlider(
                    question: question.text,
                    selected: scaleAnswers[question.id],
                    onSelect: { value in
                        withAnimation(AppMotion.snap) {
                            scaleAnswers[question.id] = value
                        }
                        answered()
                    }
                )
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
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(feedbackQuestions.enumerated()), id: \.element.id) { index, question in
                Button {
                    Haptics.selection()
                    pendingAdvance?.cancel()
                    go(to: index)
                } label: {
                    Capsule()
                        .fill(dotColor(index: index, question: question))
                        .frame(width: index == questionIndex ? 20 : 7, height: 7)
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Question \(index + 1) of \(feedbackQuestions.count)")
                .accessibilityValue(isAnswered(question) ? "Answered" : "Not answered")
            }
        }
        .frame(maxWidth: .infinity)
        .motion(AppMotion.slide, value: questionIndex)
    }

    private func dotColor(index: Int, question: FeedbackQuestion) -> Color {
        if index == questionIndex { return AppColors.primary }
        return isAnswered(question) ? AppColors.primary.opacity(0.45) : Color.white.opacity(0.15)
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
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(AppColors.success)
                .symbolEffect(.bounce, value: isWrappingUp)
                .accessibilityHidden(true)

            Text("Check-in saved")
                .font(.headline)
                .foregroundStyle(.white)

            Text(wrapUpLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Bottom Action Bar

    private var selfCheckBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.06))

            // Vertical stack - an HStack put the helper copy beside the skip
            // control and the two collided at accessibility text sizes.
            VStack(spacing: 6) {
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
                    Text(isWrappingUp
                         ? "Your results open the moment they're ready"
                         : "Answer as many as you like, or skip ahead")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.opacity)

                    Button {
                        handOverNow()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Skip to results")
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(hasHandedOver)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
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
            TakeScanView.bars(from: (try? JSONDecoder().decode([Float].self, from: data)) ?? [])
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

// MARK: - Feeling Slider (extracted subview)

/// "How did that go", as a slider. The thumb follows the finger continuously,
/// the readout above it snaps to the nearest of five notches with a selection
/// tick per notch, and on release the thumb springs onto that notch. Tapping
/// the track jumps straight there.
///
/// It replaced a row of five small face buttons. A slider is one gesture
/// instead of a hunt for the right 40pt target, and the big readout gives the
/// answer somewhere to land.
///
/// The in-flight value stays local and commits once on release: the host
/// moves the card on a beat after `onSelect`, and reporting every notch would
/// have advanced it while the thumb was still moving.
private struct FeelingSlider: View {
    let question: String
    let selected: Int?
    let onSelect: (Int) -> Void

    /// 0...1 along the track while a finger is down; nil at rest.
    @State private var dragFraction: CGFloat?
    @State private var trackWidth: CGFloat = 0
    @State private var hintPulse = false

    private static let options: [(label: String, icon: String, line: String)] = [
        ("Rough", "cloud.bolt.rain.fill", "Hard going this time"),
        ("Shaky", "cloud.drizzle.fill", "Got through it"),
        ("Okay", "cloud.sun.fill", "Middle of the road"),
        ("Good", "sun.max.fill", "Felt solid"),
        ("Great", "sparkles", "In the zone")
    ]

    private let thumbSize: CGFloat = 30
    private let trackHeight: CGFloat = 10

    /// The notch under the finger while dragging, else the committed answer.
    private var shown: Int? {
        if let dragFraction { return Self.value(at: dragFraction) }
        return selected
    }

    private var thumbFraction: CGFloat {
        if let dragFraction { return dragFraction }
        if let selected { return CGFloat(selected - 1) / 4 }
        return 0.5
    }

    private var tint: Color {
        shown.map { AppColors.scoreColor(for: $0 * 20) } ?? .white.opacity(0.5)
    }

    static func value(at fraction: CGFloat) -> Int {
        min(5, max(1, Int((fraction * 4).rounded()) + 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            readout
            track
            HStack {
                Text("Rough")
                Spacer()
                Text("Great")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(question)
        .accessibilityValue(shown.map { Self.options[$0 - 1].label } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            let current = selected ?? 3
            switch direction {
            case .increment: onSelect(min(5, selected == nil ? 3 : current + 1))
            case .decrement: onSelect(max(1, selected == nil ? 3 : current - 1))
            @unknown default: break
            }
        }
    }

    private var readout: some View {
        HStack(spacing: 12) {
            Image(systemName: shown.map { Self.options[$0 - 1].icon } ?? "hand.draw.fill")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 48, height: 48)
                .background { Circle().fill(tint.opacity(0.16)) }

            VStack(alignment: .leading, spacing: 2) {
                Text(shown.map { Self.options[$0 - 1].label } ?? "Slide to rate")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                    .contentTransition(.interpolate)

                Text(shown.map { Self.options[$0 - 1].line } ?? "Drag the dot, or tap along the line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .motion(AppMotion.snap, value: shown)
    }

    private var track: some View {
        let travel = max(0, trackWidth - thumbSize)
        let thumbX = thumbSize / 2 + travel * thumbFraction

        return ZStack(alignment: .leading) {
            // Rail, inset by the thumb's radius so the thumb never overhangs
            // the card at either end.
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: trackHeight)
                .padding(.horizontal, thumbSize / 2 - trackHeight / 2)

            // The full score ramp, revealed up to the thumb, so the fill
            // under the thumb is the colour the readout is using.
            LinearGradient(
                colors: [AppColors.scoreLow, AppColors.scoreMid, AppColors.scoreGood, AppColors.scoreHigh],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: trackHeight)
            .clipShape(Capsule())
            .padding(.horizontal, thumbSize / 2 - trackHeight / 2)
            .mask(alignment: .leading) {
                Capsule()
                    .frame(width: shown == nil ? 0 : thumbX + trackHeight / 2, height: trackHeight)
            }

            // Five notches, so the stops are visible before the first drag.
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(shown.map { $0 - 1 >= index } == true ? 0.9 : 0.25))
                    .frame(width: 4, height: 4)
                    .position(x: thumbSize / 2 + travel * CGFloat(index) / 4, y: thumbSize / 2 + 7)
            }

            thumb
                .position(x: thumbX, y: thumbSize / 2 + 7)
        }
        .frame(height: thumbSize + 14)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trackWidth = $0 }
        .contentShape(Rectangle())
        .gesture(drag(travel: travel))
        .sensoryFeedback(.selection, trigger: shown) { old, new in
            dragFraction != nil && old != nil && new != old
        }
        .ambientLoop(AppMotion.ambient(duration: 1.1)) { hintPulse = true }
    }

    private var thumb: some View {
        ZStack {
            if shown == nil {
                // An idle nudge until the first touch, so the control reads as
                // something to move rather than a finished meter.
                Circle()
                    .stroke(AppColors.primary.opacity(hintPulse ? 0 : 0.55), lineWidth: 2)
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(hintPulse ? 1.7 : 1)
            } else {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tint.opacity(0.45), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: thumbSize
                        )
                    )
                    .frame(width: thumbSize * 2, height: thumbSize * 2)
            }

            Circle()
                .fill(Color.white)
                .frame(width: thumbSize, height: thumbSize)
                .overlay {
                    Circle()
                        .fill(shown == nil ? AppColors.primary : tint)
                        .frame(width: 10, height: 10)
                }
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .scaleEffect(dragFraction == nil ? 1 : 1.12)
        }
        .allowsHitTesting(false)
        .motion(AppMotion.snap, value: dragFraction == nil)
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard travel > 0 else { return }
                let fraction = (drag.location.x - thumbSize / 2) / travel
                dragFraction = min(1, max(0, fraction))
            }
            .onEnded { _ in
                guard let dragFraction else { return }
                let value = Self.value(at: dragFraction)
                withAnimation(AppMotion.snap) {
                    self.dragFraction = nil
                }
                Haptics.selection()
                onSelect(value)
            }
    }
}

// MARK: - Yes/No Input (extracted subview)

private struct YesNoInput: View {
    let selected: Bool?
    let onSelect: (Bool) -> Void

    var body: some View {
        // Buttons already say No / Yes. The old "Not really" / "Strong"
        // polarity captions belonged to a slider and sat under the buttons,
        // colliding with them when the card was height-compressed.
        HStack(spacing: 12) {
            optionButton(label: "No", icon: "hand.thumbsdown.fill", value: false, tint: AppColors.warning)
            optionButton(label: "Yes", icon: "hand.thumbsup.fill", value: true, tint: AppColors.success)
        }
    }

    private func optionButton(label: String, icon: String, value: Bool, tint: Color) -> some View {
        let isSelected = selected == value

        return Button { onSelect(value) } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? tint : .white.opacity(0.3))
                    .symbolEffect(.bounce, value: isSelected)

                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? tint.opacity(0.15) : Color.white.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? tint.opacity(0.5) : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
            }
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(
            isSelected ? [.isButton, .isSelected] : .isButton
        )
    }
}

// MARK: - Saved Seal (extracted subview)

/// The "take saved" mark: the seal springs in and a ring breaks off it once.
/// Resting state is fully shown, so an interrupted animation cannot leave the
/// header half-drawn.
private struct SavedSeal: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.success.opacity(burst ? 0 : 0.5), lineWidth: 2)
                .frame(width: 48, height: 48)
                .scaleEffect(burst ? 1.8 : 1)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 38))
                .foregroundStyle(AppColors.success)
                .symbolEffect(.bounce, value: burst)
        }
        .frame(width: 64, height: 64)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.9)) { burst = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Estimated Progress Bar (extracted subview)

/// A progress line for a job that reports none. It eases toward 90 % over the
/// expected wait and only completes when the score actually lands, so it can
/// run slow but never claims to be done early. A wait with visible progress
/// feels shorter than an open-ended spinner, which is the whole point here.
private struct EstimatedProgressBar: View {
    let startedAt: Date
    let expected: TimeInterval
    let isComplete: Bool
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 15.0, paused: isComplete)) { timeline in
            let fraction = isComplete
                ? 1
                : Self.fraction(elapsed: timeline.date.timeIntervalSince(startedAt), expected: expected)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * fraction)
                }
            }
        }
        // Per-tick growth is unanimated; the jump to full when the score
        // lands is the one step that eases.
        .motion(AppMotion.settle, value: isComplete)
        .accessibilityHidden(true)
    }

    nonisolated static func fraction(elapsed: TimeInterval, expected: TimeInterval) -> CGFloat {
        guard expected > 0 else { return 0 }
        return CGFloat(0.9 * (1 - exp(-2.2 * max(0, elapsed) / expected)))
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
            takeShape = TakeScanView.bars(from: recording.audioLevelSamples ?? [])
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(spacing: 10) {
            // Duration lives in the context strip below - it was printed twice.
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppColors.primary)
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
                TakeScanView(bars: takeShape)
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

// MARK: - Take Scan

/// The take you just gave, drawn as its loudness over time, with a scan line
/// sweeping across it while the pipeline works. The wait shows *your* speech
/// being read instead of a spinner that could belong to any app.
///
/// The sweep loops on purpose: nothing reports real progress, and a scanner
/// that restarts reads as "still looking", where stage text that restarts
/// reads as "started over".
private struct TakeScanView: View {
    let bars: [CGFloat]
    /// Scoring finished: every bar lit, no scan line.
    var isComplete: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sweep: Double = 2.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || isComplete)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let scan = reduceMotion || isComplete ? -1 : (t / Self.sweep).truncatingRemainder(dividingBy: 1)
            Canvas { context, size in
                draw(in: context, size: size, scan: CGFloat(scan))
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize, scan: CGFloat) {
        let count = bars.count
        guard count > 0 else { return }
        let slot = size.width / CGFloat(count)
        let barWidth = max(1.5, slot * 0.55)
        let scanX = scan * size.width

        for (index, level) in bars.enumerated() {
            let x = (CGFloat(index) + 0.5) * slot
            let height = max(3, level * size.height)
            let rect = CGRect(x: x - barWidth / 2, y: (size.height - height) / 2, width: barWidth, height: height)

            // Lit where the line is, settled teal where it has been this
            // sweep, dim ahead of it.
            let distance = abs(x - scanX)
            let glow = max(0, 1 - distance / (size.width * 0.12))
            let color: Color
            let opacity: Double
            if isComplete {
                color = AppColors.success
                opacity = 0.75
            } else if scan < 0 {
                color = AppColors.primary
                opacity = 0.6
            } else if glow > 0 {
                color = AppColors.categoryBrandBright
                opacity = 0.45 + 0.55 * Double(glow)
            } else if x < scanX {
                color = AppColors.primary
                opacity = 0.7
            } else {
                color = .white
                opacity = 0.16
            }
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(color.opacity(opacity))
            )
        }

        guard scan >= 0 else { return }
        var line = context
        line.blendMode = .plusLighter
        line.fill(
            Path(CGRect(x: scanX - 1, y: 0, width: 2, height: size.height)),
            with: .linearGradient(
                Gradient(colors: [.clear, AppColors.categoryBrandBright.opacity(0.9), .clear]),
                startPoint: CGPoint(x: scanX, y: 0),
                endPoint: CGPoint(x: scanX, y: size.height)
            )
        )
    }

    /// Level samples (dB) → `count` bar heights in 0...1. Averages each
    /// bucket so a single spike cannot dominate, and floors silence so a
    /// pause still draws as a quiet stub rather than a gap.
    nonisolated static func bars(from samples: [Float], count: Int = 56) -> [CGFloat] {
        guard samples.count >= 4 else { return [] }
        let bucket = max(1, samples.count / count)
        return stride(from: 0, to: samples.count, by: bucket).prefix(count).map { start in
            let slice = samples[start..<min(start + bucket, samples.count)]
            let mean = slice.reduce(0, +) / Float(slice.count)
            let unit = CGFloat(min(1, max(0, (mean + 55) / 50)))
            return 0.1 + 0.9 * pow(unit, 1.3)
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
