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
    // Observable so views reading isDismissed() re-render when the gate reopens
    // (the reflection card's "Answer Quick Questions" path).
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
    /// True only while Whisper is actually downloading from Hub.
    /// Distinct from `isModelLoading` so a failed first download does not keep
    /// the "Downloading…" copy up through Apple Speech fallback.
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

    // Feedback state — typed dictionaries for proper Equatable tracking
    @State private var scaleAnswers: [UUID: Int] = [:]
    @State private var boolAnswers: [UUID: Bool] = [:]
    @State private var feedbackSubmitted = false
    @State private var pendingAutoSubmit: Task<Void, Never>?

    // Debounce window before auto-submit fires. Matches the selection spring
    // (~0.3 s response) so the user sees their tap register before the view
    // transitions to results.
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

    // Parent RecordingView uses .ignoresSafeArea(); go through UIKit to get
    // the true system inset so feedback content clears the Dynamic Island.
    private var systemTopSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if let onSaveAndClose {
                HStack {
                    Spacer()
                    Button("Save & close", systemImage: "xmark") {
                        Haptics.light()
                        onSaveAndClose()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .accessibilityHint("Your recording stays in History and scoring continues")
                }
                .padding(.top, systemTopSafeAreaInset + 8)
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
            tipVisible: showTip,
            hasExternalTopBar: onSaveAndClose != nil
        )
    }

    private var feedbackContent: some View {
        Group {
            if feedbackQuestions.count > 2 {
                PageScrollView {
                    feedbackContentStack
                }
                .scrollIndicators(.hidden)
            } else {
                feedbackContentStack
            }
        }
    }

    private var feedbackContentStack: some View {
        VStack(spacing: 14) {
            Spacer()
                .frame(height: onSaveAndClose == nil ? systemTopSafeAreaInset + 8 : 8)

            WaveformOrb(
                phase: waveformPhase,
                pulseScale: pulseScale,
                showCheckmark: analysisReady
            )
            .scaleEffect(0.58)
            .frame(height: 94)

            VStack(spacing: 4) {
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())

                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            allQuestionsCard

            Spacer(minLength: 6)
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

            HStack(spacing: 12) {
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Spacer()

                autoSubmitStatusLabel
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
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
            .padding(.horizontal, 12)
            .transition(.opacity)
        } else {
            Text("Answer any you'd like, or skip to results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
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
    //
    // The waveform and pulse loops moved to `.ambientLoop` — they never used
    // the async context for anything (a `repeatForever` animation lives on the
    // view, not the task, so cancellation never reached them) and they now go
    // still under Reduce Motion.

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

    private func cycleStages() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3)) {
                progressStage = (progressStage + 1) % stages.count
            }
        }
    }
}

// MARK: - Scale Input (extracted subview)

private struct ScaleInput: View {
    let selected: Int?
    let onSelect: (Int) -> Void

    private let options: [(label: String, icon: String)] = [
        ("Rough", "face.dashed"),
        ("Shaky", "face.smiling.inverse"),
        ("Okay", "face.smiling"),
        ("Good", "hand.thumbsup"),
        ("Great", "star.fill")
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { value in
                    let isSelected = selected == value
                    let option = options[value - 1]
                    let scoreColor = AppColors.scoreColor(for: value * 20)

                    Button { onSelect(value) } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(isSelected
                                          ? scoreColor.opacity(0.2)
                                          : Color.white.opacity(0.06))
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                isSelected ? scoreColor.opacity(0.6) : Color.white.opacity(0.1),
                                                lineWidth: isSelected ? 2 : 1
                                            )
                                    }

                                Image(systemName: option.icon)
                                    .font(.system(size: isSelected ? 18 : 14))
                                    .foregroundStyle(isSelected ? scoreColor : .white.opacity(0.4))
                            }
                            .frame(width: 40, height: 40)
                            .scaleEffect(isSelected ? 1.1 : 1.0)

                            Text(option.label)
                                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? scoreColor : .white.opacity(0.4))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
                    .accessibilityLabel("\(option.label), \(value) of 5")
                    .accessibilityAddTraits(
                        isSelected ? [.isButton, .isSelected] : .isButton
                    )
                }
            }

            // Progress track — centered between first and last circle
            scaleTrack
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

                if let sel = selected, sel > 1 {
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
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                optionButton(label: "No", icon: "hand.thumbsdown.fill", value: false, tint: AppColors.warning)
                optionButton(label: "Yes", icon: "hand.thumbsup.fill", value: true, tint: AppColors.success)
            }

            HStack {
                Text("Not really")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Strong")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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

            ForEach(0..<24, id: \.self) { i in
                let angle = Double(i) * (360.0 / 24.0)
                let base: CGFloat = 8
                let wave = sin(phase + Double(i) * 0.5) * 12
                let barHeight = max(base, base + CGFloat(wave))

                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.primary.opacity(0.6 + Double(i % 3) * 0.15))
                    .frame(width: 3, height: barHeight)
                    .offset(y: -45)
                    .rotationEffect(.degrees(angle))
            }

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
        (icon: "list.bullet", text: "Structure tip: lead with the point, then the reason — PREP in two moves."),
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
//
// Post-recording loading state. Mirrors `RecordingDetailView.readyContent`
// block for block — context strip, hero score card, next step, tab picker,
// metric rows — so nothing jumps when the score lands. Same 20pt stack spacing
// and 16pt page padding as the real screen, same card paddings, and the header
// is literally the same view: everything it shows (prompt, category, date,
// duration) is known before analysis starts, so it renders for real instead of
// as a grey bar. Only the parts that need the analysis are placeholders.

private struct DetailSkeletonView: View {
    let recording: Recording
    let statusTitle: String
    let statusSubtitle: String
    let stage: Int
    let currentTipIndex: Int
    let tipVisible: Bool
    let hasExternalTopBar: Bool

    var body: some View {
        PageScrollView {
            // Single ShimmerHost drives one animation for every skeleton
            // primitive in this view via the shimmerPhase environment value.
            ShimmerHost {
                // 20pt, matching RecordingDetailView.readyContent.
                VStack(spacing: 20) {
                    statusHeader
                        // The parent RecordingView ZStack uses .ignoresSafeArea()
                        // so the recording UI can paint edge-to-edge. When the
                        // skeleton takes over, that inherited modifier pushes
                        // the status pill under the notch / Dynamic Island.
                        // Pad the header by the system top safe area so it
                        // clears the status bar regardless of device.
                        .padding(.top, hasExternalTopBar ? 8 : systemTopSafeAreaInset + 8)

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
    }

    /// Top safe-area inset read directly from the key window. Using
    /// GeometryProxy.safeAreaInsets here would return 0 because a parent view
    /// in the hierarchy calls .ignoresSafeArea(); going through UIKit bypasses
    /// the ignored value and gives us the true system inset.
    private var systemTopSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(spacing: 10) {
            // Duration lives in the context strip below — it was printed twice.
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
    }

    // MARK: - Skeleton Sections
    //
    // Each mirrors the card it will be replaced by: same GlassCard padding,
    // same element order, same heights.

    /// `ScoreHeroCard` — eyebrow row, subscore donut, verdict line.
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

    /// `NextStepCard` — eyebrow, area, coaching line, action pill + repeat.
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

    /// The real picker, inert. Rebuilding its frame as a placeholder would fork
    /// the styling; the tabs themselves are not waiting on the analysis.
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

    /// `MetricRowGroup` — pace, fillers, words, pauses.
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

/// Stand-in for `SubscoreRadarChart`: the annulus at the geometry the chart
/// itself uses (42pt label inset, inner radius 0.38 of outer), the centre score,
/// and the orbiting axis labels.
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

/// Stand-in for one `MetricRow`: icon, label, and a right-aligned value.
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
