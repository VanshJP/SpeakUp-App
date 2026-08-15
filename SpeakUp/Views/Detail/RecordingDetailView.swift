import SwiftUI
import SwiftData
import AVFoundation
import UIKit

struct RecordingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let recordingId: String
    /// Re-runs the session that produced this recording. Owned by ContentView
    /// because the countdown + recording covers live at the app root.
    var onPracticeAgain: ((Prompt?) -> Void)? = nil

    @State private var recording: Recording?
    @State private var isLoading = true
    @State private var showingDeleteAlert = false
    @State private var showFillerHighlights = true
    @State private var showVocabHighlights = true
    @State private var showSpeakerTurns = true
    @State private var waveformHeights: [CGFloat] = []
    @State private var selectedDetailTab: DetailTab = .breakdown
    @State private var isEditingTitle = false
    @State private var editingTitleText = ""
    @State private var showingListenBackEncouragement = false
    @State private var showingScoreWeights = false
    @State private var settingsViewModel = SettingsViewModel()
    @State private var llmInsight: String?
    @State private var playbackErrorMessage: String?
    @State private var showCopiedConfirmation = false
    @State private var journalReflectionText = ""
    @State private var showingJournalReflection = false
    @State private var journalSaved = false
    @State private var storiesViewModel = StoriesViewModel()
    @State private var playbackViewModel = RecordingDetailPlaybackViewModel()
    @State private var coherenceEnhanceInFlight = false
    @State private var playableMediaAvailable = false
    /// Set while the user is choosing whether the prompt text goes on the card.
    @State private var pendingShareRecording: Recording?
    /// The first score has to be the first thing the user sees. A questionnaire
    /// in front of it costs the moment the whole install was for. Resolved once
    /// on load — a fetch count in `body` would run on every redraw.
    @State private var isFirstAnalyzedSession = false
    /// Rolling baselines every number on this screen is read against. Loads in
    /// the background, so all fields start nil and fill in together.
    @State private var baselines = PersonalAverage.Baselines()

    // Next-step routing — the practice tool that targets this session's weakest area.
    @State private var nextStepDrill: DrillMode?
    @State private var showingNextStepWarmUp = false
    @State private var showingNextStepReadAloud = false

    @Query private var userSettings: [UserSettings]

    // Services
    @Environment(AudioService.self) private var audioService
    @Environment(SpeechService.self) private var speechService
    @Environment(LLMService.self) private var llmService

    private enum DetailScreenState {
        case loading
        case processing(Recording)
        case ready(Recording)
        case missing
    }

    private var detailScreenState: DetailScreenState {
        guard let recording else {
            return isLoading ? .loading : .missing
        }
        return (recording.isProcessing || shouldGateFeedback(for: recording))
            ? .processing(recording)
            : .ready(recording)
    }

    private var feedbackEnabled: Bool {
        userSettings.first?.sessionFeedbackEnabled ?? false
    }

    private func shouldGateFeedback(for recording: Recording) -> Bool {
        feedbackEnabled &&
        !isFirstAnalyzedSession &&
        recording.analysis != nil &&
        recording.sessionFeedback == nil &&
        !SessionFeedbackGateStore.isDismissed(recording.id)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground(style: .subtle)

            switch detailScreenState {
            case .loading:
                ProgressView("Loading...")
                    .padding(.top, 100)

            case .missing:
                ContentUnavailableView(
                    "Recording Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This recording may have been deleted.")
                )

            case .processing(let recording):
                AnalyzingView(
                    recording: recording,
                    isModelLoading: !speechService.isModelLoaded,
                    feedbackEnabled: feedbackEnabled,
                    feedbackQuestions: feedbackQuestionsForAnalyzing,
                    existingFeedback: recording.sessionFeedback,
                    onFeedbackSubmitted: { feedback in
                        recording.sessionFeedback = feedback
                        try? modelContext.save()
                    },
                    onFeedbackCompleted: {
                        SessionFeedbackGateStore.markDismissed(recording.id)
                        if recording.analysis != nil {
                            recording.isProcessing = false
                            try? modelContext.save()
                        }
                        runReadySetupIfNeeded()
                    },
                    analysisReady: recording.analysis != nil
                )

            case .ready(let recording):
                readyContent(recording)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        if case .ready(let recording) = detailScreenState {
                            beginScoreCardShare(for: recording)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                            .frame(width: 28, height: 28)
                    }

                    Menu {
                        if case .ready(let recording) = detailScreenState {
                            Button {
                                editingTitleText = recording.customTitle ?? ""
                                isEditingTitle = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button {
                                toggleFavorite(recording)
                            } label: {
                                Label(
                                    recording.isFavorite ? "Remove Favorite" : "Add to Favorites",
                                    systemImage: recording.isFavorite ? "heart.slash" : "heart"
                                )
                            }
                        }

                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                            .frame(width: 28, height: 28)
                    }
                }
            }
        }
        .task {
            settingsViewModel.configure(with: modelContext)
            await loadRecording()
            if let recording {
                enqueueProcessingIfNeeded(recording)
            }
            runReadySetupIfNeeded()
        }
        .onChange(of: recording?.isProcessing) { _, isProcessing in
            // Analysis landed while this view was showing AnalyzingView —
            // run the ready-state setup that .task skipped at appear time.
            if isProcessing == false {
                runReadySetupIfNeeded()
            }
        }
        .onDisappear {
            audioService.stop()
        }
        .alert("Delete Recording?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteRecording()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Playback Error", isPresented: Binding(
            get: { playbackErrorMessage != nil },
            set: { if !$0 { playbackErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { playbackErrorMessage = nil }
        } message: {
            Text(playbackErrorMessage ?? "")
        }
        .confirmationDialog(
            "Challenge a friend?",
            isPresented: Binding(
                get: { pendingShareRecording != nil },
                set: { if !$0 { pendingShareRecording = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingShareRecording
        ) { shareTarget in
            Button("Send Prompt & Scores") {
                presentScoreCardShare(for: shareTarget, includePromptText: true)
            }
            Button("Scores Only") {
                presentScoreCardShare(for: shareTarget, includePromptText: false)
            }
            Button("Cancel", role: .cancel) {
                pendingShareRecording = nil
            }
        } message: { shareTarget in
            Text("Your scores go on the card. Include \(shareCaptionDescription(for: shareTarget)) to send a link your friend can tap to try the same one.")
        }
        .sheet(isPresented: $showingScoreWeights) {
            NavigationStack {
                ScoreWeightsView(viewModel: settingsViewModel)
            }
        }
        .sheet(item: $nextStepDrill) { mode in
            DrillSelectionView(initialMode: mode)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingNextStepWarmUp) {
            WarmUpListView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingNextStepReadAloud) {
            ReadAloudSelectionView()
                .presentationDetents([.large])
        }
        .overlay {
            if showingListenBackEncouragement {
                ListenBackEncouragementView {
                    showingListenBackEncouragement = false
                    proceedWithPlayback()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingListenBackEncouragement)
    }

    @ViewBuilder
    private func readyContent(_ recording: Recording) -> some View {
        ScrollView(.vertical) {
            // Three blocks, then tabs. Context → score → what to do about it.
            // Every metric surface (radar, stat tiles, pace chart, goal) moved
            // under Breakdown: they are evidence for the score, and stacking
            // them above the tabs gave the page a six-card preamble that
            // buried the one number the user came here to read.
            VStack(spacing: 20) {
                contextStrip(recording)

                if let analysis = recording.analysis {
                    scoreHero(analysis)
                    nextStepSection(analysis, recording: recording)
                    // Challenge CTA sits next to the score — burying it in
                    // Coaching was the moment the share loop went unseen.
                    shareCTASection(recording)

                    detailTabPicker

                    switch selectedDetailTab {
                    case .breakdown:
                        breakdownTabContent(recording, analysis: analysis)
                    case .transcript:
                        transcriptTabContent(recording)
                    case .coaching:
                        coachingTabContent(recording)
                    }
                } else if recording.analysisBlockedByAllowance {
                    // Held back by the free allowance, not broken.
                    analysisDeferredCard(recording)
                } else {
                    // Analysis never landed (transcription failed or was
                    // interrupted) — say so and offer a way out instead of
                    // leaving a silent dead-end. A transcript may still exist.
                    analysisUnavailableCard(recording)
                    transcriptTabContent(recording)
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .contentMargins(.horizontal, 0)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playableMediaAvailable {
                PlaybackDrawerContainer(
                    recording: recording,
                    waveformHeights: waveformHeights,
                    playbackViewModel: playbackViewModel,
                    onTogglePlayback: { togglePlayback(recording) },
                    onSeek: { progress in
                        audioService.seek(to: progress)
                        playbackViewModel.sync(from: audioService, fallbackDuration: recording.actualDuration)
                    }
                )
            }
        }
    }

    /// One-time setup for the ready state (waveform, playback, WPM series,
    /// LLM coherence pass). Safe to call repeatedly — each step guards itself.
    private func runReadySetupIfNeeded() {
        guard case .ready(let recording) = detailScreenState else { return }
        // The paywall is allowed to exist from here on: the user has seen a
        // complete result, which is what earns the right to ask.
        if recording.analysis != nil {
            PaywallCoordinator.shared.markFirstResultSeen()
        }
        // Resolved once here instead of in body — hasPlayableMedia hits the
        // filesystem (iCloud/local existence checks) on every call.
        playableMediaAvailable = hasPlayableMedia(recording)
        prepareDetailAssets(for: recording)
        configurePlaybackState(for: recording)
        populateWPMTimeSeriesIfNeeded()

        // Post-analysis: enhance coherence in background — don't block the detail view
        Task {
            await enhanceCoherenceIfNeeded()
        }

        loadPersonalAverageIfNeeded(excluding: recording.id)
    }

    /// Loads the baselines the hero delta and the metric tiles read against.
    /// See `PersonalAverage` for why the window is bounded.
    private func loadPersonalAverageIfNeeded(excluding currentID: UUID) {
        guard baselines.score == nil else { return }
        let container = modelContext.container

        Task {
            let loaded = await PersonalAverage.all(excluding: currentID, container: container)
            await MainActor.run {
                baselines = loaded
                considerReviewPromptForStrongResult()
            }
        }
    }

    /// A new personal best or a top-band score is the only moment on this
    /// screen worth spending one of the year's review prompts on. Waits for the
    /// baselines because "was this good?" is a question about the user's own
    /// history, not an absolute threshold.
    private func considerReviewPromptForStrongResult() {
        guard !isFirstAnalyzedSession,
              case .ready(let recording) = detailScreenState,
              let score = recording.analysis?.speechScore.overall else { return }

        let beatPersonalBest = baselines.best.map { score > $0 } ?? false
        guard beatPersonalBest || score >= 85 else { return }

        noteReviewWorthyMoment(.strongResult)
    }

    /// The recording is saved and playable; only the scoring is waiting. Said
    /// plainly, because "analysis failed" for a paywall reason reads as a bug.
    @ViewBuilder
    private func analysisDeferredCard(_ recording: Recording) -> some View {
        // Read through the existing query rather than fetching: a fetch here
        // would re-run on every body evaluation of this screen.
        let decision = AllowanceGate.decision(settings: userSettings.first)

        GlassCard(tint: AppColors.glassTintPrimary) {
            VStack(spacing: 12) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(AppColors.primary)

                VStack(spacing: 4) {
                    Text("Saved, not scored yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(deferredMessage(for: decision))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    GlassButton(title: "Unlock Lifetime", icon: "sparkles", style: .primary) {
                        Haptics.medium()
                        PaywallCoordinator.shared.present(
                            .unlimitedAnalyses,
                            trigger: "deferred_analysis",
                            userInitiated: true
                        )
                    }
                    GlassButton(title: "Try Again", icon: "arrow.clockwise", style: .secondary, size: .small) {
                        Haptics.light()
                        enqueueProcessingIfNeeded(recording, force: true)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func deferredMessage(for decision: AllowanceDecision) -> String {
        guard case .exhausted(let resetsOn) = decision else {
            return "This recording is safe. Tap Try Again to score it now."
        }
        let date = resetsOn.formatted(date: .abbreviated, time: .omitted)
        return "Your free analyses are used up for now. The audio is safe — it scores automatically on \(date), or the moment you unlock Lifetime."
    }

    @ViewBuilder
    private func analysisUnavailableCard(_ recording: Recording) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Text(recording.lastProcessingError == nil ? "Analysis Unavailable" : "Analysis Failed")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(recording.lastProcessingError ?? "This recording hasn't been analyzed yet. You can still listen back, or try analyzing again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                GlassButton(title: "Analyze Again", icon: "arrow.clockwise", style: .secondary) {
                    Haptics.medium()
                    enqueueProcessingIfNeeded(recording, force: true)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    /// Starts a score-card share. When the session has a prompt or a story
    /// behind it, the user is asked whether that text travels with the card —
    /// the score is theirs to show off, the subject matter may not be.
    private func beginScoreCardShare(for recording: Recording) {
        guard ScoreCardRenderer.promptCaption(for: recording) != nil else {
            presentScoreCardShare(for: recording, includePromptText: false)
            return
        }
        pendingShareRecording = recording
    }

    /// What the include-prompt choice would actually reveal.
    private func shareCaptionDescription(for recording: Recording) -> String {
        recording.prompt != nil ? "the prompt you answered" : "your story's title"
    }

    /// Renders the score card and hands it to the system share sheet, with a
    /// caption that carries a tappable try-this-prompt link when the sender
    /// opted to include the prompt.
    private func presentScoreCardShare(for recording: Recording, includePromptText: Bool) {
        pendingShareRecording = nil
        guard let image = ScoreCardRenderer.render(
            recording: recording,
            includePromptText: includePromptText
        ) else { return }

        let score = recording.analysis?.speechScore.overall
        let url: URL?
        let promptText: String?
        if includePromptText, let prompt = recording.prompt {
            let payload = SharedPromptPayload(
                promptID: prompt.id,
                text: prompt.text,
                category: prompt.category,
                difficulty: prompt.difficulty.rawValue,
                beatScore: score,
                source: SharedPromptLink.shareSource
            )
            url = SharedPromptLink.shareURL(for: payload)
            promptText = prompt.text
        } else if includePromptText {
            // Story title is on the card, but a friend cannot open someone
            // else's story. Send them into a fresh session instead.
            url = SharedPromptLink.shareURL(for: SharedPromptPayload(source: SharedPromptLink.shareSource))
            promptText = recording.storyTitle
        } else {
            url = nil
            promptText = nil
        }

        let message = SharedPromptLink.message(
            score: score,
            verdict: score.map { AppColors.scoreVerdict(for: $0) },
            promptText: includePromptText ? promptText : nil,
            url: url
        )

        SharePresenter.present(
            image: image,
            cardType: includePromptText ? "score_card_with_prompt" : "score_card",
            trigger: "recording_detail",
            message: message
        ) {
            noteReviewWorthyMoment(.shareCompleted)
        }
    }

    /// A good thing just happened. The service decides whether it is worth
    /// spending one of the year's review prompts on.
    private func noteReviewWorthyMoment(_ trigger: ReviewRequestService.Trigger) {
        let settings = userSettings.first
        guard ReviewRequestService.shared.requestIfEligible(trigger, settings: settings) else { return }
        try? modelContext.save()
    }

    private func enqueueProcessingIfNeeded(_ recording: Recording, force: Bool = false) {
        // Never mark an already-analyzed recording as processing — doing so
        // before this guard used to strand the screen on AnalyzingView forever.
        guard recording.analysis == nil else { return }
        if force {
            recording.isProcessing = true
            try? modelContext.save()
        }
        RecordingProcessingCoordinator.shared.enqueue(
            recordingID: recording.id,
            modelContext: modelContext,
            speechService: speechService,
            llmService: llmService
        )
    }

    // MARK: - Score Hero

    private func subscoreAxes(_ analysis: SpeechAnalysis) -> [SubscoreRadarChart.Axis] {
        SubscoreRadarChart.Axis.from(
            subscores: analysis.speechScore.subscores,
            isPromptRelevance: analysis.promptRelevanceScore != nil && recording?.prompt != nil
        )
    }

    @ViewBuilder
    private func scoreHero(_ analysis: SpeechAnalysis) -> some View {
        let axes = subscoreAxes(analysis)
        let emphasis = SubscoreRadarChart.Axis.emphasisIDs(in: axes)
        ScoreHeroCard(
            score: analysis.speechScore.overall,
            personalAverage: baselines.score,
            axes: axes,
            strongestAxisID: emphasis.strongest,
            weakestAxisID: emphasis.weakest,
            onShowWeights: { showingScoreWeights = true }
        )
    }

    // MARK: - Tab Picker

    private var detailTabPicker: some View {
        SectionPicker(
            sections: DetailTab.allCases,
            selection: $selectedDetailTab,
            label: { $0.rawValue },
            icon: { $0.icon }
        )
    }

    // MARK: - Context Strip

    /// Layout lives in `DetailContextStrip` — the analyzing skeleton renders the
    /// same header, so it must not fork.
    @ViewBuilder
    private func contextStrip(_ recording: Recording) -> some View {
        DetailContextStrip(recording: recording) {
            editingTitleText = recording.customTitle ?? ""
            isEditingTitle = true
        }
        .alert("Name This Session", isPresented: $isEditingTitle) {
            TextField("e.g. Elevator pitch practice", text: $editingTitleText)
            Button("Save") {
                let trimmed = editingTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
                recording.customTitle = trimmed.isEmpty ? nil : trimmed
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this session a name or the question you were answering.")
        }
    }

    // MARK: - Processing Section (moved to AnalyzingView)

    // MARK: - Next Step

    /// Closes the practice loop: names the weakest area and routes to the tool
    /// that trains it, so the screen ends in an action instead of metrics.
    @ViewBuilder
    private func nextStepSection(_ analysis: SpeechAnalysis, recording: Recording) -> some View {
        NextStepCard(
            step: NextStep.from(analysis.speechScore.subscores),
            onAction: { action in
                switch action {
                case .drill(let mode): nextStepDrill = mode
                case .warmUp: showingNextStepWarmUp = true
                case .readAloud: showingNextStepReadAloud = true
                case .practiceAgain: onPracticeAgain?(recording.prompt)
                }
            },
            onPracticeAgain: { onPracticeAgain?(recording.prompt) }
        )
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private func statsGrid(_ analysis: SpeechAnalysis) -> some View {
        // One stat sheet, not four boxes. The 2×2 tile grid stacked label,
        // value, baseline, and pill vertically in each cell, which left the
        // right half of every tile empty and made the section twice as tall as
        // the numbers warranted.
        MetricRowGroup {
            MetricRow(
                icon: "speedometer",
                label: "Pace",
                value: "\(Int(analysis.wordsPerMinute))",
                unit: "wpm",
                baseline: baselines.paceLabel,
                status: paceStatus(for: analysis.wordsPerMinute)
            )
            MetricRowDivider()
            MetricRow(
                icon: "exclamationmark.bubble",
                label: "Fillers",
                value: "\(analysis.totalFillerCount)",
                baseline: baselines.fillerLabel,
                status: fillerStatus(for: analysis.totalFillerCount)
            )
            MetricRowDivider()
            MetricRow(
                icon: "text.word.spacing",
                label: "Words",
                value: "\(analysis.totalWords)",
                baseline: baselines.wordsLabel,
                status: lengthStatus(for: analysis)
            )
            MetricRowDivider()
            MetricRow(
                icon: "pause.circle",
                label: "Pauses",
                value: "\(analysis.pauseCount)",
                baseline: baselines.pauseLabel,
                status: pauseStatus(for: analysis)
            )
        }
    }

    /// Whether the pauses were deliberate or stumbles. Two sessions can both
    /// show "9 pauses" and mean opposite things, so the count alone was the
    /// least useful number on the grid — this is the part worth reading.
    private func pauseStatus(for analysis: SpeechAnalysis) -> MetricRow.Status {
        guard analysis.pauseCount > 0 else { return .neutral("None") }
        if analysis.hesitationPauseCount > analysis.strategicPauseCount { return .caution("Hesitant") }
        if analysis.strategicPauseCount > 0 { return .good("Strategic") }
        return .neutral("Even")
    }

    /// Whether there was enough here to say something, from the scoring
    /// engine's own substance composite.
    ///
    /// Deliberately not words-per-minute — that is the Pace tile, and grading
    /// this one by rate too would print the same judgement twice. Substance
    /// blends word count, duration, lexical variety, and run length, which is
    /// the question a raw word count actually raises.
    private func lengthStatus(for analysis: SpeechAnalysis) -> MetricRow.Status? {
        guard analysis.totalWords > 0 else { return .bad("Silent") }
        guard let substance = analysis.enhancedMetrics?.substanceScore else { return nil }
        switch substance {
        case ..<30: return .caution("Brief")
        case ..<75: return .good("Solid")
        default: return .good("Full")
        }
    }

    private func paceStatus(for wpm: Double) -> MetricRow.Status {
        let target = Double(userSettings.first.resolvedTargetWPM)
        if wpm < target - 40 { return .neutral("Slow") }
        if wpm > target + 40 { return .caution("Fast") }
        return .good("On pace")
    }

    private func fillerStatus(for count: Int) -> MetricRow.Status {
        switch count {
        case 0...2: return .good("Clean")
        case 3...7: return .caution("A few")
        default: return .bad("Many")
        }
    }

    // MARK: - WPM Chart Section

    @ViewBuilder
    private func wpmChartSection(_ wpmData: [WPMDataPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Pace Over Time", icon: "chart.line.uptrend.xyaxis")

            GlassCard {
                WPMChartView(
                    dataPoints: wpmData,
                    targetWPM: userSettings.first.resolvedTargetWPM,
                    averageWPM: recording?.analysis?.wordsPerMinute ?? 0
                )
            }
        }
    }

    // MARK: - Filler Words Section

    @ViewBuilder
    private func fillerWordsSection(_ fillerWords: [FillerWord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Filler Words Used", icon: "exclamationmark.bubble.fill")

            GlassCard {
                VStack(spacing: 12) {
                    ForEach(fillerWords.prefix(5)) { filler in
                        HStack {
                            Text(filler.word)
                                .font(.subheadline)

                            Spacer()

                            Text("\(filler.count)×")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.warning)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Transcript Section

    @ViewBuilder
    private func transcriptSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // GlassSectionHeader supplies its own trailing Spacer.
                GlassSectionHeader("Transcript", icon: "doc.text.fill")

                copyTranscriptButton(text: text)
            }

            GlassCard {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func transcriptSectionWithHighlights(_ words: [TranscriptionWord], recording: Recording) -> some View {
        let turns = speakerTurns(from: words)
        let hasSpeakerSeparation = hasSeparatedSpeakers(in: turns)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // GlassSectionHeader supplies its own trailing Spacer.
                GlassSectionHeader("Transcript", icon: "doc.text.fill")

                HStack(spacing: 6) {
                    copyTranscriptButton(text: words.map(\.word).joined(separator: " "))

                    if hasSpeakerSeparation {
                        Button {
                            showSpeakerTurns.toggle()
                        } label: {
                            Image(systemName: showSpeakerTurns ? "person.2.fill" : "person")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(showSpeakerTurns ? AppColors.primary : .secondary)
                                .padding(6)
                                .background {
                                    Circle()
                                        .fill(showSpeakerTurns ? AppColors.primary.opacity(0.15) : .clear)
                                }
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Show speaker turns")
                    }

                    if let analysis = recording.analysis, !analysis.fillerWords.isEmpty {
                        Button {
                            showFillerHighlights.toggle()
                        } label: {
                            Image(systemName: showFillerHighlights ? "bubble.left.fill" : "bubble.left")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(showFillerHighlights ? AppColors.warning : .secondary)
                                .padding(6)
                                .background {
                                    Circle()
                                        .fill(showFillerHighlights ? AppColors.warning.opacity(0.1) : .clear)
                                }
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Highlight filler words")
                    }

                    if let analysis = recording.analysis, !analysis.vocabWordsUsed.isEmpty {
                        Button {
                            showVocabHighlights.toggle()
                        } label: {
                            Image(systemName: showVocabHighlights ? "character.book.closed.fill" : "character.book.closed")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(showVocabHighlights ? AppColors.success : .secondary)
                                .padding(6)
                                .background {
                                    Circle()
                                        .fill(showVocabHighlights ? AppColors.success.opacity(0.1) : .clear)
                                }
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Highlight vocabulary words")
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 0) {
                    TranscriptContentView(
                        words: words,
                        turns: turns,
                        showFillerHighlights: showFillerHighlights,
                        showVocabHighlights: showVocabHighlights,
                        showSpeakerTurns: showSpeakerTurns,
                        hasSpeakerSeparation: hasSpeakerSeparation
                    )

                    if let analysis = recording.analysis, !analysis.vocabWordsUsed.isEmpty {
                        Divider()
                            .padding(.vertical, 10)

                        HStack(spacing: 6) {
                            Image(systemName: "text.badge.checkmark")
                                .font(.caption)
                                .foregroundStyle(AppColors.success)

                            Text("Vocab:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.success)

                            Text(analysis.vocabWordsUsed.map { "\($0.word) (\($0.count))" }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func copyTranscriptButton(text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
            Haptics.success()
            showCopiedConfirmation = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCopiedConfirmation = false
            }
        } label: {
            Image(systemName: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.medium))
                .foregroundStyle(showCopiedConfirmation ? AppColors.success : .secondary)
                .padding(6)
                .background {
                    Circle()
                        .fill(showCopiedConfirmation ? AppColors.success.opacity(0.1) : .clear)
                }
                .animation(.easeInOut(duration: 0.2), value: showCopiedConfirmation)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(showCopiedConfirmation ? "Copied" : "Copy transcript")
    }

    private func speakerTurns(from words: [TranscriptionWord]) -> [SpeakerTurn] {
        let ordered = words
            .filter { !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        guard let first = ordered.first else { return [] }

        var rawTurns: [(isPrimary: Bool, words: [TranscriptionWord])] = []
        var currentSpeaker = first.isPrimarySpeaker
        var currentWords: [TranscriptionWord] = []

        for word in ordered {
            if word.isPrimarySpeaker != currentSpeaker, !currentWords.isEmpty {
                rawTurns.append((isPrimary: currentSpeaker, words: currentWords))
                currentWords = []
            }
            currentSpeaker = word.isPrimarySpeaker
            currentWords.append(word)
        }
        if !currentWords.isEmpty {
            rawTurns.append((isPrimary: currentSpeaker, words: currentWords))
        }

        // Merge micro-turns: if a turn has only 1-2 words, absorb it into the adjacent turn
        // with the most words. This prevents single noise-burst words from creating a
        // spurious speaker-turn bubble in the UI.
        var merged: [(isPrimary: Bool, words: [TranscriptionWord])] = []
        for (_, turn) in rawTurns.enumerated() {
            if turn.words.count <= 2 && !merged.isEmpty {
                // Absorb into the previous turn (same speaker label as previous)
                let last = merged.removeLast()
                merged.append((isPrimary: last.isPrimary, words: last.words + turn.words))
            } else {
                merged.append(turn)
            }
        }

        return merged.enumerated().map { index, turn in
            SpeakerTurn(id: index, isPrimarySpeaker: turn.isPrimary, words: turn.words)
        }
    }

    private func hasSeparatedSpeakers(in turns: [SpeakerTurn]) -> Bool {
        guard turns.count >= 2 else { return false }
        let primaryWordCount = turns
            .filter(\.isPrimarySpeaker)
            .reduce(0) { $0 + $1.words.count }
        let otherWordCount = turns
            .filter { !$0.isPrimarySpeaker }
            .reduce(0) { $0 + $1.words.count }
        // Lowered otherWordCount threshold from 4 to 3:
        // In a short conversation (e.g. a Q&A), the other speaker may only contribute
        // a brief question or acknowledgement. Requiring 4 words was hiding the speaker
        // turn UI for legitimate two-speaker recordings.
        // Also require at least 2 distinct turns (not just 2 total words) to avoid
        // showing the UI for a single isolated noise burst.
        let otherTurnCount = turns.filter { !$0.isPrimarySpeaker }.count
        return primaryWordCount >= 8 && otherWordCount >= 3 && otherTurnCount >= 1
    }

    // MARK: - Share CTA Section

    @ViewBuilder
    private func shareCTASection(_ recording: Recording) -> some View {
        let hasPrompt = recording.prompt != nil
        GlassCard(tint: AppColors.primary.opacity(0.1)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasPrompt ? "Challenge a friend" : "Share your score")
                        .font(.subheadline.weight(.medium))
                    Text(hasPrompt
                         ? "Send your score and a link to this prompt"
                         : "Create a shareable score card")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    Haptics.light()
                    beginScoreCardShare(for: recording)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.primary)
                }
                .accessibilityLabel(hasPrompt ? "Challenge a friend" : "Share your score")
            }
        }
    }

    // MARK: - Tab Content

    /// Evidence for the score that the hero card does not already show: the
    /// headline numbers, pace over time, and goal progress.
    ///
    /// The subscore radar lives in the hero card now, and the old pause /
    /// vocal-variety / advanced-metrics stack under this tab restated axes the
    /// radar already labels — duplicated detail nobody opened.
    @ViewBuilder
    private func breakdownTabContent(_ recording: Recording, analysis: SpeechAnalysis) -> some View {
        statsGrid(analysis)

        // Attaches the filler count above to the words that produced it.
        // Renders nothing on a clean take.
        if let words = recording.transcriptionWords, !words.isEmpty {
            TranscriptExcerptCard(words: words) {
                withAnimation(AppMotion.slide) { selectedDetailTab = .transcript }
            }
        }

        if let wpmData = analysis.wpmTimeSeries, wpmData.count >= 2 {
            wpmChartSection(wpmData)
        }

        if recording.goalId != nil {
            goalProgressCard(recording)
        }
    }

    @ViewBuilder
    private func transcriptTabContent(_ recording: Recording) -> some View {
        if let words = recording.transcriptionWords, !words.isEmpty {
            transcriptSectionWithHighlights(words, recording: recording)
        } else if let text = recording.transcriptionText, !text.isEmpty {
            transcriptSection(text)
        }

        if let analysis = recording.analysis, !analysis.fillerWords.isEmpty {
            fillerWordsSection(analysis.fillerWords)
        }
    }

    @ViewBuilder
    private func coachingTabContent(_ recording: Recording) -> some View {
        if let analysis = recording.analysis {
            // AI Insights — available when Apple Intelligence or local LLM is ready
            if llmService.isAvailable {
                aiInsightsSection(recording)
            }

            CoachingTipsView(tips: CoachingTipService.generateTips(from: analysis))
        }

        if let feedback = recording.sessionFeedback {
            selfAssessmentSection(feedback)
        } else if userSettings.first?.sessionFeedbackEnabled ?? false {
            reflectionPromptCard
        }

        journalReflectionSection(recording)
    }

    // MARK: - AI Insights Section

    @ViewBuilder
    private func aiInsightsSection(_ recording: Recording) -> some View {
        let isAppleIntelligence = llmService.activeBackend == .appleIntelligence

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Label(
                    "AI Insights",
                    systemImage: isAppleIntelligence ? "apple.intelligence" : "cpu"
                )
                .font(.headline)

                Text(isAppleIntelligence ? "AI" : llmService.localLLM.modelDisplayName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: isAppleIntelligence
                                        ? [.purple, .blue]
                                        : [AppColors.categoryBrandBright, AppColors.primary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }

                Spacer()
            }

            if llmService.isGenerating {
                GlassCard {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(AppColors.primary)
                        Text("Generating personalized insights...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            } else if let insight = llmInsight {
                GlassCard(tint: AppColors.categoryBrandBright.opacity(0.05)) {
                    let blocks = formattedAIInsightBlocks(insight)
                    VStack(alignment: .leading, spacing: 10) {
                        if blocks.isEmpty {
                            Text(insight)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                aiInsightBlockView(block)
                            }
                        }
                    }
                }
            } else {
                GlassButton(title: "Generate AI Coaching", icon: "sparkles", style: .secondary, fullWidth: true) {
                    Haptics.medium()
                    Task {
                        guard let analysis = recording.analysis else { return }
                        let transcript = resolvedTranscript(for: recording)
                        llmInsight = await llmService.generateCoachingInsight(
                            from: analysis,
                            transcript: transcript
                        )
                    }
                }
            }
        }
    }

    // MARK: - Reflection Prompt Card

    private var reflectionPromptCard: some View {
        FeaturedGlassCard {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.message.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("How did you feel?")
                            .font(.subheadline.weight(.semibold))
                        Text("Reflect on this session to track your growth")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                GlassButton(title: "Answer Quick Questions", icon: "pencil.line", style: .primary, fullWidth: true) {
                    Haptics.medium()
                    // Reopen the feedback gate — detailScreenState flips back to
                    // .processing and AnalyzingView shows the questionnaire.
                    if case .ready(let recording) = detailScreenState {
                        SessionFeedbackGateStore.reopen(recording.id)
                    }
                }
            }
        }
    }

    // MARK: - Journal Reflection

    @ViewBuilder
    private func journalReflectionSection(_ recording: Recording) -> some View {
        if journalSaved {
            GlassCard(tint: AppColors.glassTintSuccess) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                    Text("Reflection saved to Journal")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
        } else if showingJournalReflection {
            GlassCard(tint: AppColors.glassTintPrimary.opacity(0.5)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "bubble.left.fill")
                            .foregroundStyle(AppColors.primary)
                        Text("Quick Reflection")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            withAnimation { showingJournalReflection = false }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("How did that feel?", text: $journalReflectionText, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial)
                        }

                    GlassButton(title: "Save to Journal", icon: "text.book.closed", style: .primary, size: .small) {
                        saveReflectionToJournal(recording)
                    }
                    .disabled(journalReflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } else {
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.3)) {
                    showingJournalReflection = true
                }
            } label: {
                GlassCard(tint: AppColors.glassTintAccent) {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundStyle(.secondary)
                        Text("How did that feel? Add a reflection...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func saveReflectionToJournal(_ recording: Recording) {
        storiesViewModel.configure(with: modelContext)

        let title = "Reflection — \(recording.date.formatted(date: .abbreviated, time: .omitted))"
        storiesViewModel.createStory(
            title: title,
            content: journalReflectionText,
            tags: [],
            inputMethod: "typed",
            stage: .polished,
            occasion: nil,
            entryType: .reflection
        )

        Haptics.success()
        withAnimation(.spring(response: 0.3)) {
            journalSaved = true
            showingJournalReflection = false
        }
    }

    // MARK: - Goal Progress Card

    @ViewBuilder
    private func goalProgressCard(_ recording: Recording) -> some View {
        if let goalId = recording.goalId {
            GoalProgressBadge(goalId: goalId)
        }
    }

    // MARK: - Helpers

    // MARK: - Self-Assessment Section

    @ViewBuilder
    private func selfAssessmentSection(_ feedback: SessionFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Self-Assessment", icon: "checkmark.message")

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(feedback.answers) { answer in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(answer.questionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if answer.type == .scale, let value = answer.scaleValue {
                                HStack(spacing: 6) {
                                    ForEach(1...5, id: \.self) { i in
                                        Circle()
                                            .fill(i <= value
                                                  ? AppColors.scoreColor(for: value * 20)
                                                  : Color.white.opacity(0.1))
                                            .frame(width: 10, height: 10)
                                    }

                                    Text(selfAssessmentLabel(for: value))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(AppColors.scoreColor(for: value * 20))
                                        .padding(.leading, 4)
                                }
                            } else if answer.type == .yesNo, let value = answer.boolValue {
                                HStack(spacing: 6) {
                                    Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(value ? AppColors.success : AppColors.warning)
                                    Text(value ? "Yes" : "No")
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                        }

                        if answer.id != feedback.answers.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func selfAssessmentLabel(for value: Int) -> String {
        switch value {
        case 1: return "Very Poor"
        case 2: return "Poor"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "Excellent"
        default: return ""
        }
    }

    private var feedbackQuestionsForAnalyzing: [FeedbackQuestion] {
        let custom = userSettings.first?.customFeedbackQuestions ?? []
        return DefaultFeedbackQuestions.questions + custom
    }

    private func resolvedTranscript(for recording: Recording) -> String {
        let wordsTranscript = recording.transcriptionWords?
            .map(\.word)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let wordsTranscript, !wordsTranscript.isEmpty {
            return wordsTranscript
        }

        let fallbackText = recording.transcriptionText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackText, !fallbackText.isEmpty {
            return fallbackText
        }

        return ""
    }

    private func formattedAIInsightBlocks(_ insight: String) -> [AIInsightBlock] {
        let trimmed = insight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var blocks: [AIInsightBlock] = []
        for line in lines where !line.isEmpty {
            if let headingRange = line.range(of: #"^#{1,3}\s+"#, options: .regularExpression) {
                let headingText = String(line[headingRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !headingText.isEmpty else { continue }
                blocks.append(.heading(parseInlineMarkdown(headingText)))
                continue
            }

            if let bulletPrefixRange = line.range(of: #"^(?:[-*•]|\d+[.)])\s+"#, options: .regularExpression) {
                let bulletText = String(line[bulletPrefixRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bulletText.isEmpty else { continue }
                blocks.append(.bullet(parseInlineMarkdown(bulletText)))
                continue
            }

            blocks.append(.paragraph(parseInlineMarkdown(line)))
        }

        return blocks
    }

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)
            )
        } catch {
            return AttributedString(text)
        }
    }

    @ViewBuilder
    private func aiInsightBlockView(_ block: AIInsightBlock) -> some View {
        switch block {
        case .heading(let heading):
            Text(heading)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let paragraph):
            Text(paragraph)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let bullet):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .padding(.top, 6)

                Text(bullet)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func prepareDetailAssets(for recording: Recording) {
        guard waveformHeights.isEmpty || audioService.playbackDuration <= 0 else { return }
        let mediaURL = recording.resolvedAudioURL ?? recording.resolvedVideoURL
        let needsWaveform = waveformHeights.isEmpty
        let cachedPeaks = recording.waveformPeaks

        // Use cached peaks synchronously — no file I/O needed.
        if needsWaveform, let cachedPeaks, !cachedPeaks.isEmpty {
            waveformHeights = AudioWaveformGenerator.heights(from: cachedPeaks)
        }

        let shouldGeneratePeaks = needsWaveform && (cachedPeaks == nil || cachedPeaks?.isEmpty == true)

        Task(priority: .utility) {
            if shouldGeneratePeaks, let mediaURL {
                let peaks = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        let generated = AudioWaveformGenerator.generatePeaks(from: mediaURL, binCount: 50)
                        continuation.resume(returning: generated)
                    }
                }

                guard !Task.isCancelled else { return }

                if !peaks.isEmpty {
                    waveformHeights = AudioWaveformGenerator.heights(from: peaks)
                    recording.waveformPeaks = peaks
                    try? modelContext.save()
                } else if waveformHeights.isEmpty {
                    waveformHeights = AudioWaveformGenerator.heights(from: [])
                }
            }

            if let mediaURL, audioService.playbackDuration <= 0 {
                let asset = AVURLAsset(url: mediaURL)
                if let duration = try? await asset.load(.duration) {
                    let seconds = CMTimeGetSeconds(duration)
                    if seconds.isFinite && seconds > 0 {
                        audioService.playbackDuration = seconds
                    }
                }
            }
        }
    }

    private func configurePlaybackState(for recording: Recording) {
        playbackViewModel.sync(from: audioService, fallbackDuration: recording.actualDuration)
    }

    private func loadRecording() async {
        isLoading = true
        defer { isLoading = false }

        guard let uuid = UUID(uuidString: recordingId) else { return }

        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.id == uuid }
        )

        do {
            let recordings = try modelContext.fetch(descriptor)
            recording = recordings.first

            // Counted on `transcriptionText`, not `analysis`: SwiftData stores
            // the Codable `analysis` as a composite attribute with no queryable
            // column, so a predicate touching it raises an ObjC exception during
            // SQL generation that `try?` cannot catch — it terminates the app.
            // Transcript and analysis are written in the same save, so the count
            // matches. Same reasoning in `RecordingProcessingCoordinator`.
            let analyzedCount = (try? modelContext.fetchCount(
                FetchDescriptor<Recording>(predicate: #Predicate { $0.transcriptionText != nil })
            )) ?? 0
            isFirstAnalyzedSession = analyzedCount <= 1

            // Reset stale isProcessing flag — if the app crashed mid-transcription,
            // this flag stays true in SwiftData but no task is actually running.
            // Clear it so the view doesn't get stuck on the AnalyzingView spinner.
            // enqueueProcessingIfNeeded() will re-process if analysis is still nil.
            // Skip when the coordinator is actively processing this recording,
            // otherwise the view flashes an empty "ready" state mid-transcription.
            if let loadedRecording = recording, loadedRecording.isProcessing,
               !RecordingProcessingCoordinator.shared.isProcessing(loadedRecording.id) {
                loadedRecording.isProcessing = false
                try? modelContext.save()
            }
        } catch {
            recording = nil
        }
    }

    private func populateWPMTimeSeriesIfNeeded() {
        guard let recording,
              let analysis = recording.analysis,
              analysis.wpmTimeSeries == nil,
              let words = recording.transcriptionWords,
              words.count >= 2 else { return }

        Task(priority: .utility) {
            let wordsSnapshot = words
            let durationSnapshot = recording.actualDuration
            let wpmData = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    // computeWPMTimeSeries never touches the Whisper model; a
                    // throwaway instance avoids hopping the MainActor service.
                    let data = SpeechService().computeWPMTimeSeries(
                        words: wordsSnapshot,
                        actualDuration: durationSnapshot
                    )
                    continuation.resume(returning: data)
                }
            }
            guard !Task.isCancelled else { return }
            recording.analysis?.wpmTimeSeries = wpmData
            try? modelContext.save()
        }
    }

    private func enhanceCoherenceIfNeeded() async {
        // Single writer: runReadySetupIfNeeded can fire from multiple triggers
        // (.task, isProcessing change, feedback completion). Two concurrent LLM
        // passes would both write recording.analysis and jump the visible score.
        guard !coherenceEnhanceInFlight else { return }
        coherenceEnhanceInFlight = true
        defer { coherenceEnhanceInFlight = false }

        guard case .ready(let recording) = detailScreenState,
              var analysis = recording.analysis else { return }

        let transcript = resolvedTranscript(for: recording)
        guard !transcript.isEmpty else { return }

        // Skip if LLM has already enhanced this analysis. Re-running blends
        // non-deterministic LLM output back into the persisted score and drifts
        // the overall by ±1-2 points across opens.
        if analysis.llmEnhancedAt != nil { return }

        // If local model is downloaded but not loaded, start loading in background
        // and skip enhancement for this session to avoid blocking the view.
        if !llmService.isAvailable && llmService.localLLM.isModelDownloaded {
            Task(priority: .background) {
                await llmService.loadLocalModelIfNeeded()
            }
            return
        }

        guard llmService.isAvailable else { return }

        let weights = ScoreWeights(from: userSettings.first)

        // Story-linked recordings score against the script, matching the base
        // analysis in RecordingProcessingCoordinator — story wins over prompt.
        let effectivePrompt: String? = {
            if let storyId = recording.storyId {
                var descriptor = FetchDescriptor<Story>(predicate: #Predicate { $0.id == storyId })
                descriptor.fetchLimit = 1
                if let story = (try? modelContext.fetch(descriptor))?.first {
                    let trimmed = story.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return recording.prompt?.text
        }()

        await speechService.enhanceWithLLM(
            analysis: &analysis,
            transcript: transcript,
            llmService: llmService,
            promptText: effectivePrompt,
            scoreWeights: weights
        )

        // Guard against view dismissal during async inference
        guard !Task.isCancelled else { return }

        recording.analysis = analysis
        if let storyId = recording.storyId {
            let enhancedScore = analysis.speechScore.overall
            var descriptor = FetchDescriptor<Story>(predicate: #Predicate { $0.id == storyId })
            descriptor.fetchLimit = 1
            if let story = (try? modelContext.fetch(descriptor))?.first,
               enhancedScore > story.bestScore {
                story.bestScore = enhancedScore
                story.updatedAt = Date()
            }
        }
        try? modelContext.save()

        // Auto-generate coaching insight so it's ready on the coaching tab.
        // Regenerate each time analysis is enhanced to avoid stale advice.
        guard !Task.isCancelled else { return }
        llmInsight = await llmService.generateCoachingInsight(
            from: analysis,
            transcript: transcript
        )
    }

    private func togglePlayback(_ recording: Recording) {
        guard let url = recording.resolvedAudioURL ?? recording.resolvedVideoURL else {
            playbackErrorMessage = "Audio file is no longer available. It may have been moved or deleted."
            return
        }

        // Check if file is still downloading from iCloud
        if !ICloudStorageService.shared.isFileDownloaded(at: url) {
            ICloudStorageService.shared.ensureDownloaded(at: url)
            playbackErrorMessage = "This recording is downloading from iCloud. Please try again in a moment."
            return
        }

        if audioService.isPlaying {
            audioService.pause()
        } else {
            // Check for first-time listen-back
            if let settings = userSettings.first, settings.listenBackCount == 0 {
                showingListenBackEncouragement = true
                return
            }
            Task {
                do {
                    try await audioService.play(url: url)
                } catch {
                    playbackErrorMessage = "Playback failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func proceedWithPlayback() {
        // Increment listen-back count
        if let settings = userSettings.first {
            settings.listenBackCount += 1
            try? modelContext.save()
        }
        guard case .ready(let recording) = detailScreenState,
              let url = recording.resolvedAudioURL ?? recording.resolvedVideoURL else {
            playbackErrorMessage = "Audio file is no longer available. It may have been moved or deleted."
            return
        }
        if !ICloudStorageService.shared.isFileDownloaded(at: url) {
            ICloudStorageService.shared.ensureDownloaded(at: url)
            playbackErrorMessage = "This recording is downloading from iCloud. Please try again in a moment."
            return
        }
        Task {
            do {
                try await audioService.play(url: url)
            } catch {
                playbackErrorMessage = "Playback failed: \(error.localizedDescription)"
            }
        }
    }

    private func toggleFavorite(_ recording: Recording) {
        recording.isFavorite.toggle()
        try? modelContext.save()
    }

    private func deleteRecording() {
        guard let recording else { return }

        // Stop any playback first
        audioService.stop()

        // Capture resolved file URLs before nilling out
        let audioURL = recording.resolvedAudioURL
        let videoURL = recording.resolvedVideoURL

        // Nil out local state FIRST so SwiftUI stops rendering the deleted object
        self.recording = nil

        // Dismiss before deletion to avoid accessing deleted object during animation
        dismiss()

        // Clean up files and delete from context after dismiss
        Task { @MainActor in
            if let audioURL { ICloudStorageService.shared.removeFile(at: audioURL) }
            if let videoURL { ICloudStorageService.shared.removeFile(at: videoURL) }
            modelContext.delete(recording)
            try? modelContext.save()
        }
    }

    private func hasPlayableMedia(_ recording: Recording) -> Bool {
        (recording.resolvedAudioURL ?? recording.resolvedVideoURL) != nil
    }

}

// MARK: - Detail Tab Enum

enum DetailTab: String, CaseIterable, Identifiable {
    /// Renamed from "Analysis": the tab now holds the evidence behind the
    /// score rather than being one of three peer sections.
    case breakdown = "Breakdown"
    case transcript = "Transcript"
    case coaching = "Coaching"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .breakdown: return "chart.bar.fill"
        case .transcript: return "text.alignleft"
        case .coaching: return "lightbulb.fill"
        }
    }
}


private enum AIInsightBlock {
    case heading(AttributedString)
    case paragraph(AttributedString)
    case bullet(AttributedString)
}

// MARK: - Goal Progress Badge

struct GoalProgressBadge: View {
    let goalId: UUID

    @Query private var goals: [UserGoal]

    private var goal: UserGoal? {
        goals.first { $0.id == goalId }
    }

    var body: some View {
        if let goal {
            GlassCard(tint: AppColors.primary.opacity(0.08)) {
                HStack(spacing: 12) {
                    Image(systemName: goal.type.iconName)
                        .font(.title3)
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title)
                            .font(.subheadline.weight(.medium))
                        Text("\(goal.progressPercentage)% complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    RingProgress(progress: goal.progress, color: AppColors.primary, lineWidth: 3)
                        .frame(width: 32, height: 32)
                }
            }
        }
    }
}

#Preview("Recording Detail — Mock Data") {
    struct PreviewWrapper: View {
        let recordingId: String
        let container: ModelContainer

        init() {
            let schema = Schema([
                Recording.self,
                Prompt.self,
                UserGoal.self,
                UserSettings.self,
                Achievement.self,
                CurriculumProgress.self,
                RecordingGroup.self,
                Story.self,
                StoryFolder.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: schema, configurations: [config])
            self.container = container

            let context = container.mainContext

            let prompt = Prompt(
                id: UUID().uuidString,
                text: "Tell me about a time you overcame a significant challenge and what you learned from it.",
                category: "Personal Growth",
                difficulty: .medium
            )
            context.insert(prompt)

            let mockId = UUID()
            let recording = Recording(
                id: mockId,
                date: Date().addingTimeInterval(-3600),
                prompt: prompt,
                targetDuration: 120,
                actualDuration: 87.5,
                transcriptionText: "So um I think one of the biggest challenges I faced was when I had to um present our quarterly results to the entire company. I was really nervous because um you know public speaking has always been something I've struggled with. But I prepared extensively, practiced in front of the mirror, and asked colleagues for feedback. The presentation went well and I learned that thorough preparation can really help overcome anxiety. Since then I've volunteered for more speaking opportunities and each time it gets a little easier.",
                transcriptionWords: PreviewWrapper.mockWords(),
                analysis: PreviewWrapper.mockAnalysis(),
                isProcessing: false,
                isFavorite: true
            )
            context.insert(recording)

            let settings = UserSettings()
            context.insert(settings)

            try? context.save()
            self.recordingId = mockId.uuidString
        }

        var body: some View {
            NavigationStack {
                RecordingDetailView(recordingId: recordingId)
            }
            .modelContainer(container)
            .environment(AudioService())
            .environment(SpeechService())
            .environment(LLMService())
            .preferredColorScheme(.dark)
        }

        static func mockWords() -> [TranscriptionWord] {
            let text = "So um I think one of the biggest challenges I faced was when I had to um present our quarterly results to the entire company I was really nervous because um you know public speaking has always been something I've struggled with But I prepared extensively practiced in front of the mirror and asked colleagues for feedback The presentation went well and I learned that thorough preparation can really help overcome anxiety Since then I've volunteered for more speaking opportunities and each time it gets a little easier"
            let words = text.components(separatedBy: " ")
            let fillers: Set<String> = ["um", "uh", "you", "know", "like", "So"]
            var time: TimeInterval = 0.5
            return words.map { word in
                let duration = Double.random(in: 0.15...0.45)
                let w = TranscriptionWord(
                    word: word,
                    start: time,
                    end: time + duration,
                    confidence: Double.random(in: 0.85...0.99),
                    isFiller: fillers.contains(word),
                    isVocabWord: ["extensively", "quarterly", "volunteered", "preparation", "anxiety"].contains(word),
                    isPrimarySpeaker: true
                )
                time += duration + Double.random(in: 0.05...0.25)
                return w
            }
        }

        static func mockAnalysis() -> SpeechAnalysis {
            SpeechAnalysis(
                fillerWords: [
                    FillerWord(word: "um", count: 3, timestamps: [2.1, 8.4, 22.0]),
                    FillerWord(word: "you know", count: 1, timestamps: [25.3]),
                    FillerWord(word: "so", count: 1, timestamps: [0.5])
                ],
                totalWords: 89,
                wordsPerMinute: 142.0,
                pauseCount: 7,
                averagePauseLength: 0.6,
                strategicPauseCount: 4,
                hesitationPauseCount: 3,
                clarity: 72.0,
                speechScore: SpeechScore(
                    overall: 74,
                    subscores: SpeechSubscores(
                        clarity: 78,
                        pace: 82,
                        fillerUsage: 65,
                        pauseQuality: 71,
                        vocalVariety: 68,
                        delivery: 73,
                        vocabulary: 76,
                        structure: 20,
                        relevance: 80
                    ),
                    trend: .improving
                ),
                vocabWordsUsed: [
                    VocabWordUsage(word: "extensively", count: 1),
                    VocabWordUsage(word: "quarterly", count: 1),
                    VocabWordUsage(word: "volunteered", count: 1)
                ],
                volumeMetrics: VolumeMetrics(
                    averageLevel: -18.5,
                    peakLevel: -6.2,
                    dynamicRange: 12.3,
                    monotoneScore: 62,
                    energyScore: 71
                ),
                vocabComplexity: VocabComplexity(
                    uniqueWordCount: 68,
                    uniqueWordRatio: 0.76,
                    averageWordLength: 4.8,
                    longWordCount: 12,
                    longWordRatio: 0.13,
                    complexityScore: 72
                ),
                sentenceAnalysis: SentenceAnalysis(
                    totalSentences: 6,
                    incompleteSentences: 1,
                    restartCount: 0,
                    averageSentenceLength: 14.8,
                    longestSentence: 22,
                    structureScore: 70
                ),
                promptRelevanceScore: 80,
                wpmTimeSeries: [
                    WPMDataPoint(timestamp: 10, wpm: 128, wordCount: 21),
                    WPMDataPoint(timestamp: 20, wpm: 145, wordCount: 24),
                    WPMDataPoint(timestamp: 30, wpm: 155, wordCount: 26),
                    WPMDataPoint(timestamp: 40, wpm: 138, wordCount: 23),
                    WPMDataPoint(timestamp: 50, wpm: 150, wordCount: 25),
                    WPMDataPoint(timestamp: 60, wpm: 142, wordCount: 24),
                    WPMDataPoint(timestamp: 70, wpm: 135, wordCount: 22),
                    WPMDataPoint(timestamp: 80, wpm: 148, wordCount: 25)
                ],
                pitchMetrics: PitchMetrics(
                    f0Mean: 165, f0StdDev: 28,
                    f0Min: 95, f0Max: 280,
                    f0RangeSemitones: 18.7,
                    pitchVariationScore: 68,
                    declinationRate: -0.3,
                    voicedFrameRatio: 0.62
                ),
                rateVariation: RateVariationMetrics(
                    rateCV: 0.18, articulationRate: 168,
                    rateRange: 55, rateVariationScore: 65
                ),
                emphasisMetrics: EmphasisMetrics(
                    emphasisCount: 8, emphasisPerMinute: 5.5, distributionScore: 62
                ),
                energyArc: EnergyArcMetrics(
                    openingEnergy: 0.55, bodyEnergy: 0.72,
                    closingEnergy: 0.65, hasClimax: true, arcScore: 70
                ),
                textQuality: TextQualityMetrics(
                    hedgeWordCount: 3, hedgeWordRatio: 0.034,
                    powerWordCount: 4, rhetoricalDeviceCount: 1,
                    transitionVariety: 3,
                    weakPhraseCount: 2, weakPhraseRatio: 0.022,
                    repeatedSentenceStartCount: 1,
                    rhetoricalQuestionCount: 0, callToActionCount: 0,
                    authorityScore: 65, craftScore: 68,
                    concisenessScore: 72, engagementScore: 66
                )
            )
        }
    }

    return PreviewWrapper()
}
