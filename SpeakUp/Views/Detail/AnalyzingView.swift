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

    @State private var currentTipIndex = 0
    @State private var showTip = true
    @State private var waveformPhase: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var progressStage = 0

    // Feedback state - typed dictionaries for proper Equatable tracking
    @State private var scaleAnswers: [UUID: Int] = [:]
    @State private var boolAnswers: [UUID: Bool] = [:]
    @State private var feedbackSubmitted = false
    @State private var pendingAutoSubmit: Task<Void, Never>?

    private static let autoSubmitDelay: Duration = .milliseconds(350)

    private var shouldShowFeedback: Bool {
        feedbackEnabled && !feedbackQuestions.isEmpty && existingFeedback == nil && !feedbackSubmitted
    }

    private var allQuestionsAnswered: Bool {
        feedbackQuestions.allSatisfy { question in
            question.type == .scale ? scaleAnswers[question.id] != nil : boolAnswers[question.id] != nil
        }
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

            if shouldShowFeedback {
                feedbackContent
                feedbackBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                progressContent
            }
        }
        .animation(.spring(response: 0.35), value: shouldShowFeedback)
        .ambientLoop(.linear(duration: 2).repeatForever(autoreverses: false)) {
            waveformPhase = .pi * 2
        }
        .ambientLoop(AppMotion.ambient(duration: 1.5)) { pulseScale = 1.06 }
        .task { await cycleTips() }
        .task { await cycleStages() }
        .onDisappear {
            pendingAutoSubmit?.cancel()
            pendingAutoSubmit = nil
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

    private var feedbackContent: some View {
        // Always scroll - two default questions plus the status orb already
        // overflow a small phone once Dynamic Type climbs, and a non-scrolling
        // stack was compressing the Yes/No row onto its polarity labels.
        PageScrollView {
            feedbackContentStack
        }
        .scrollIndicators(.hidden)
    }

    private var feedbackContentStack: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 8)

            // scaleEffect does not change layout size. Size the host to the
            // scaled bounds and clip so the orb cannot paint over the status
            // copy or the self-check card.
            WaveformOrb(
                phase: waveformPhase,
                pulseScale: pulseScale,
                showCheckmark: analysisReady
            )
            .frame(width: 200, height: 200)
            .scaleEffect(0.58)
            .frame(width: 116, height: 116)
            .clipped()

            VStack(spacing: 6) {
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                    .multilineTextAlignment(.center)

                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            allQuestionsCard

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - All Questions Card

    private var allQuestionsCard: some View {
        FeaturedGlassCard(padding: 16) {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "checkmark.message")
                        .font(.body)
                        .foregroundStyle(AppColors.primary)

                    Text("Quick Self-Check")
                        .font(.footnote.weight(.semibold))

                    Spacer()
                }

                ForEach(Array(feedbackQuestions.enumerated()), id: \.element.id) { index, question in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(question.text)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        if question.type == .scale {
                            ScaleInput(
                                selected: scaleAnswers[question.id],
                                onSelect: { value in
                                    Haptics.selection()
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                        scaleAnswers[question.id] = value
                                    }
                                    answerChanged()
                                }
                            )
                        } else {
                            YesNoInput(
                                selected: boolAnswers[question.id],
                                onSelect: { value in
                                    Haptics.selection()
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                        boolAnswers[question.id] = value
                                    }
                                    answerChanged()
                                }
                            )
                        }
                    }

                    if index < feedbackQuestions.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var feedbackBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.06))

            // Vertical stack - the old HStack put "Skip to Results" beside
            // "Answer any you'd like, or skip to results" and the two collided
            // at accessibility text sizes / narrow widths.
            VStack(spacing: 6) {
                autoSubmitStatusLabel

                Button {
                    Haptics.light()
                    pendingAutoSubmit?.cancel()
                    withAnimation(.spring(response: 0.3)) {
                        feedbackSubmitted = true
                    }
                    onFeedbackCompleted?()
                } label: {
                    HStack(spacing: 4) {
                        Text("Skip to Results")
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .animation(.easeInOut(duration: 0.2), value: allQuestionsAnswered)
    }

    @ViewBuilder
    private var autoSubmitStatusLabel: some View {
        if allQuestionsAnswered {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppColors.primary)
                Text("Saving...")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.primary)
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        } else {
            Text("Answer any you'd like, or skip to results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        }
    }

    // MARK: - Auto-Submit

    /// Called from each answer selection. Schedules a debounced auto-submit
    /// once every question has a response. Cancelling and re-scheduling on each
    /// call lets the user change their mind during the grace window.
    private func answerChanged() {
        guard !feedbackSubmitted else { return }
        pendingAutoSubmit?.cancel()

        guard allQuestionsAnswered else {
            pendingAutoSubmit = nil
            return
        }

        pendingAutoSubmit = Task { @MainActor in
            try? await Task.sleep(for: Self.autoSubmitDelay)
            guard !Task.isCancelled,
                  !feedbackSubmitted,
                  allQuestionsAnswered else { return }
            submitFeedback()
        }
    }

    // MARK: - Submit

    private func submitFeedback() {
        let answers: [FeedbackAnswer] = feedbackQuestions.map { question in
            FeedbackAnswer(
                questionId: question.id,
                questionText: question.text,
                type: question.type,
                scaleValue: question.type == .scale ? scaleAnswers[question.id] : nil,
                boolValue: question.type == .yesNo ? boolAnswers[question.id] : nil
            )
        }

        let feedback = SessionFeedback(answers: answers)
        AnalyticsService.shared.log(.sessionFeedback(sentiment: sentiment(of: answers)))
        Haptics.success()

        withAnimation(.spring(response: 0.3)) {
            feedbackSubmitted = true
        }

        onFeedbackSubmitted?(feedback)
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

// MARK: - Scale Input (extracted subview)

/// Five faces you can tap — or scrub. A drag across the row moves the
/// selection under the finger with a detent tick per notch, and a glow in the
/// face's colour follows it. The in-flight value stays local and commits once
/// on release: the host debounces an auto-submit off `onSelect`, and reporting
/// every notch would have submitted the card while the thumb was still moving.
private struct ScaleInput: View {
    let selected: Int?
    let onSelect: (Int) -> Void

    @State private var scrubValue: Int?
    @State private var rowWidth: CGFloat = 0

    private let options: [(label: String, icon: String)] = [
        ("Rough", "face.dashed"),
        ("Shaky", "face.smiling.inverse"),
        ("Okay", "face.smiling"),
        ("Good", "hand.thumbsup"),
        ("Great", "star.fill")
    ]

    private let faceSize: CGFloat = 40
    private let glowSize: CGFloat = 96

    private var shown: Int? { scrubValue ?? selected }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                if let shown {
                    glow(for: shown)
                }

                HStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { value in
                        face(value)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .simultaneousGesture(scrub)
            .sensoryFeedback(.selection, trigger: scrubValue) { _, new in new != nil }

            // Progress track - centered between first and last circle
            scaleTrack
        }
    }

    private func face(_ value: Int) -> some View {
        let isSelected = shown == value
        let option = options[value - 1]
        let scoreColor = AppColors.scoreColor(for: value * 20)

        return Button { onSelect(value) } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected
                              ? scoreColor.opacity(0.22)
                              : Color.white.opacity(0.06))
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    isSelected ? scoreColor.opacity(0.7) : Color.white.opacity(0.1),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        }

                    Image(systemName: option.icon)
                        .font(.system(size: isSelected ? 18 : 14))
                        .foregroundStyle(isSelected ? scoreColor : .white.opacity(0.4))
                }
                .frame(width: faceSize, height: faceSize)
                .scaleEffect(isSelected ? 1.18 : 1.0)

                Text(option.label)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? scoreColor : .white.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .animation(AppMotion.snap, value: isSelected)
        .accessibilityLabel("\(option.label), \(value) of 5")
        .accessibilityAddTraits(
            isSelected ? [.isButton, .isSelected] : .isButton
        )
    }

    /// A radial wash behind the chosen face — no `.blur`, which would cost an
    /// offscreen pass on every notch; the gradient alone reads as a glow.
    private func glow(for value: Int) -> some View {
        let color = AppColors.scoreColor(for: value * 20)
        let segment = rowWidth / 5

        return Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.42), color.opacity(0.12), .clear],
                    center: .center,
                    startRadius: 4,
                    endRadius: glowSize / 2
                )
            )
            .frame(width: glowSize, height: glowSize)
            // Centred on the face at the top of its column, not on the row.
            .offset(
                x: segment * (CGFloat(value) - 0.5) - glowSize / 2,
                y: faceSize / 2 - glowSize / 2
            )
            .motion(AppMotion.slide, value: value)
            .allowsHitTesting(false)
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag in
                guard rowWidth > 0 else { return }
                let index = Int(drag.location.x / (rowWidth / 5))
                scrubValue = min(5, max(1, index + 1))
            }
            .onEnded { _ in
                if let scrubValue, scrubValue != selected {
                    onSelect(scrubValue)
                }
                scrubValue = nil
            }
    }

    private var scaleTrack: some View {
        GeometryReader { geo in
            let circleCenter = geo.size.width / 10 // half of one segment (width/5 / 2)
            let trackStart = circleCenter
            let trackEnd = geo.size.width - circleCenter
            let trackWidth = trackEnd - trackStart

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: trackWidth, height: 3)

                if let sel = shown, sel > 1 {
                    let fraction = CGFloat(sel - 1) / 4.0
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.scoreColor(for: 20),
                                    AppColors.scoreColor(for: sel * 20)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: trackWidth * fraction, height: 3)
                        .animation(.spring(response: 0.25), value: sel)
                }
            }
            .position(x: geo.size.width / 2, y: 1.5)
        }
        .frame(height: 3)
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

// MARK: - Waveform Orb (extracted subview)

private struct WaveformOrb: View {
    let phase: CGFloat
    let pulseScale: CGFloat
    let showCheckmark: Bool

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(
                        AppColors.primary.opacity(0.08 - Double(i) * 0.02),
                        lineWidth: 1.5
                    )
                    .frame(width: 140 + CGFloat(i) * 30, height: 140 + CGFloat(i) * 30)
                    .scaleEffect(pulseScale + CGFloat(i) * 0.03)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.primary.opacity(0.2), AppColors.primary.opacity(0.05), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)

            // The ring turns rather than the bars growing: `phase` animates
            // 0 → 2π, and bar heights keyed on sin(phase) land exactly where
            // they started, so the old per-bar wave never visibly moved.
            ZStack {
                ForEach(0..<24, id: \.self) { i in
                    let angle = Double(i) * (360.0 / 24.0)
                    let barHeight = 8 + 12 * max(0, CGFloat(sin(Double(i) * 0.5)))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.primary.opacity(0.6 + Double(i % 3) * 0.15))
                        .frame(width: 3, height: barHeight)
                        .offset(y: -45)
                        .rotationEffect(.degrees(angle))
                }
            }
            .rotationEffect(.radians(phase))

            Image(systemName: showCheckmark ? "checkmark" : "waveform")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppColors.primary)
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(height: 200)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sweep: Double = 2.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let scan = reduceMotion ? -1 : (t / Self.sweep).truncatingRemainder(dividingBy: 1)
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
            if scan < 0 {
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
    static func bars(from samples: [Float], count: Int = 56) -> [CGFloat] {
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
