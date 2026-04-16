import SwiftUI

struct AnalyzingView: View {
    let recording: Recording
    let isModelLoading: Bool
    var feedbackEnabled: Bool = false
    var feedbackQuestions: [FeedbackQuestion] = []
    var existingFeedback: SessionFeedback? = nil
    var onFeedbackSubmitted: ((SessionFeedback) -> Void)? = nil
    var onFeedbackCompleted: (() -> Void)? = nil
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

    private var statusTitle: String {
        if isModelLoading {
            return "Preparing Speech Engine..."
        } else if analysisReady && shouldShowFeedback {
            return "Before you see your results..."
        } else {
            return stages[progressStage]
        }
    }

    private var statusSubtitle: String {
        if isModelLoading {
            return "Loading the AI model for first-time use"
        } else if analysisReady && shouldShowFeedback {
            return "How did you feel about that session?"
        } else {
            return "Sit tight — we're crunching the numbers"
        }
    }

    private let stages = [
        "Transcribing your speech...",
        "Detecting filler words...",
        "Analyzing pace & pauses...",
        "Scoring your delivery..."
    ]

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowFeedback {
                feedbackContent
                feedbackBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                progressContent
            }
        }
        .animation(.spring(response: 0.35), value: shouldShowFeedback)
        .task { await animateWaveform() }
        .task { await animatePulse() }
        .task { await cycleTips() }
        .task { await cycleStages() }
        .onDisappear {
            pendingAutoSubmit?.cancel()
            pendingAutoSubmit = nil
        }
    }

    private var progressContent: some View {
        RecordingContinuitySkeleton(
            recording: recording,
            statusTitle: statusTitle,
            statusSubtitle: statusSubtitle,
            stage: progressStage,
            currentTipIndex: currentTipIndex,
            tipVisible: showTip
        )
    }

    private var feedbackContent: some View {
        Group {
            if feedbackQuestions.count > 2 {
                ScrollView {
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
                .frame(height: 8)

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

            feedbackBanner
            allQuestionsCard

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Feedback Banner

    private var feedbackBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Analysis complete!")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Take a moment to reflect before viewing results")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    // MARK: - All Questions Card

    private var allQuestionsCard: some View {
        FeaturedGlassCard(
            gradientColors: [.teal.opacity(0.08), .cyan.opacity(0.04)],
            padding: 16
        ) {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "checkmark.message")
                        .font(.body)
                        .foregroundStyle(.teal)

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
                    .tint(.teal)
                Text("Saving...")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.teal)
            }
            .padding(.horizontal, 12)
            .transition(.opacity)
        } else {
            Text("Tap a response for each question")
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
        Haptics.success()

        withAnimation(.spring(response: 0.3)) {
            feedbackSubmitted = true
        }

        onFeedbackSubmitted?(feedback)
        onFeedbackCompleted?()
    }

    // MARK: - Animations (task-based, auto-cancelled on disappear)

    private func animateWaveform() async {
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            waveformPhase = .pi * 2
        }
    }

    private func animatePulse() async {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.06
        }
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
        ("Very Poor", "face.dashed"),
        ("Poor", "face.smiling.inverse"),
        ("Okay", "face.smiling"),
        ("Good", "hand.thumbsup"),
        ("Excellent", "star.fill")
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
                Text("Needs work")
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
                        Color.teal.opacity(0.08 - Double(i) * 0.02),
                        lineWidth: 1.5
                    )
                    .frame(width: 140 + CGFloat(i) * 30, height: 140 + CGFloat(i) * 30)
                    .scaleEffect(pulseScale + CGFloat(i) * 0.03)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.teal.opacity(0.2), .teal.opacity(0.05), .clear],
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
                    .fill(Color.teal.opacity(0.6 + Double(i % 3) * 0.15))
                    .frame(width: 3, height: barHeight)
                    .offset(y: -45)
                    .rotationEffect(.degrees(angle))
            }

            Image(systemName: showCheckmark ? "checkmark" : "waveform")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.teal)
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
                    .fill(i <= stage ? Color.teal : Color.white.opacity(0.15))
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
        (icon: "star.fill", text: "Great job showing up! Consistency is the key to confident speaking."),
        (icon: "brain.head.profile.fill", text: "Every recording builds stronger neural pathways for fluent speech."),
        (icon: "chart.line.uptrend.xyaxis", text: "Speakers who review their recordings improve 3x faster."),
        (icon: "flame.fill", text: "You're building a habit that most people never start. Be proud."),
        (icon: "trophy.fill", text: "The best speakers in the world still practice every day."),
        (icon: "sparkles", text: "Your voice is unique. The goal isn't perfection -- it's progress."),
        (icon: "bolt.fill", text: "Each session sharpens your clarity, pace, and confidence."),
        (icon: "heart.fill", text: "Speaking gets easier the more you do it. You've already done the hard part.")
    ]

    var body: some View {
        let tip = Self.tips[tipIndex]
        FeaturedGlassCard(
            gradientColors: [.teal.opacity(0.1), .cyan.opacity(0.05)]
        ) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: tip.icon)
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.teal, .cyan],
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

// MARK: - Recording Continuity Skeleton
//
// Post-recording loading state. Mirrors the RecordingView layout — same top
// bar silhouette, frozen TimerView at the final duration, auto-animated
// CircularWaveformView around a sparkles icon where the record button lived —
// so the transition from recording → processing feels like a single continuous
// screen rather than a jump to an unrelated view.

private struct RecordingContinuitySkeleton: View {
    let recording: Recording
    let statusTitle: String
    let statusSubtitle: String
    let stage: Int
    let currentTipIndex: Int
    let tipVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBarShell
                .padding(.top, 50)

            Spacer(minLength: 12)

            TimerView(
                remainingTime: recording.actualDuration,
                totalTime: max(recording.actualDuration, 1),
                progress: 1.0,
                color: .teal,
                isRecording: false,
                isOvertime: false,
                timerLabel: "final"
            )

            Spacer(minLength: 12)

            VStack(spacing: 16) {
                statusPill

                AnalyzingProgressDots(stage: stage)

                ZStack {
                    CircularWaveformView(autoAnimate: true)
                        .opacity(0.85)

                    // Silhouette where the record button lived.
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.teal.opacity(0.35), lineWidth: 1)
                            }

                        Image(systemName: "sparkles")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.teal, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                }
                .frame(width: 200, height: 200)

                MotivationalTipCard(tipIndex: currentTipIndex, isVisible: tipVisible)
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal)
    }

    private var topBarShell: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                }

            Spacer()

            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.teal)
                Text("Analyzing")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.teal)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
        }
    }

    private var statusPill: some View {
        VStack(spacing: 4) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }
}
