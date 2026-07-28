import SwiftUI
import SwiftData
import AVFoundation

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
    @State private var showingShareSheet = false
    @State private var showFillerHighlights = true
    @State private var showVocabHighlights = true
    @State private var showSpeakerTurns = true
    @State private var waveformHeights: [CGFloat] = []
    @State private var scoreCardImage: UIImage?
    @State private var selectedDetailTab: DetailTab = .breakdown
    @State private var isEditingTitle = false
    @State private var editingTitleText = ""
    @State private var showingListenBackEncouragement = false
    @State private var exportService = ExportService()
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
    /// Rolling average of recent prior sessions, used to contextualize this
    /// session's score. Nil until loaded or when this is the first scored run.
    @State private var personalAverage: Int?

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
                            scoreCardImage = ScoreCardRenderer.render(recording: recording)
                        }
                        showingShareSheet = true
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
        .onChange(of: showingShareSheet) { _, show in
            if show, case .ready(let recording) = detailScreenState {
                exportService.shareRecording(recording, scoreCardImage: scoreCardImage)
                showingShareSheet = false
            }
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

                    detailTabPicker

                    switch selectedDetailTab {
                    case .breakdown:
                        breakdownTabContent(recording, analysis: analysis)
                    case .transcript:
                        transcriptTabContent(recording)
                    case .coaching:
                        coachingTabContent(recording)
                    }
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

    /// Averages the overall score of the most recent prior sessions.
    ///
    /// Bounded to a rolling window rather than all-time: decoding every
    /// `analysis` blob would make this cost grow without limit, and a rolling
    /// baseline is the more useful comparison anyway — "better than I've been
    /// lately" beats "better than I was a year ago".
    private func loadPersonalAverageIfNeeded(excluding currentID: UUID) {
        guard personalAverage == nil else { return }
        let container = modelContext.container

        Task {
            let average = await Task.detached(priority: .utility) { () -> Int? in
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<Recording>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
                // One extra row so excluding the current session still leaves
                // a full window.
                descriptor.fetchLimit = Self.personalAverageWindow + 1

                guard let recent = try? context.fetch(descriptor) else { return nil }

                let scores = recent
                    .filter { $0.id != currentID && !$0.isDeleted }
                    .prefix(Self.personalAverageWindow)
                    .compactMap { $0.analysis?.speechScore.overall }

                guard !scores.isEmpty else { return nil }
                return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
            }.value

            await MainActor.run { personalAverage = average }
        }
    }

    /// `nonisolated` because the rolling-average fetch reads it from inside a
    /// detached task. The project defaults actor isolation to MainActor, so
    /// without this the access is a Swift 6 error.
    nonisolated private static let personalAverageWindow = 20

    @ViewBuilder
    private func analysisUnavailableCard(_ recording: Recording) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Text("Analysis Unavailable")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("This recording hasn't been analyzed yet. You can still listen back, or try analyzing again.")
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

    private func enqueueProcessingIfNeeded(_ recording: Recording, force: Bool = false) {
        if force {
            recording.isProcessing = true
            try? modelContext.save()
            if recording.analysis != nil { return }
        }
        if recording.analysis != nil {
            return
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
        let strongest = axes.max(by: { $0.value < $1.value })
        let weakest = axes.min(by: { $0.value < $1.value })
        // With one axis, strongest and weakest are the same metric — showing
        // it twice under opposing labels would be nonsense.
        let hasSpread = strongest?.id != weakest?.id

        ScoreHeroCard(
            score: analysis.speechScore.overall,
            personalAverage: personalAverage,
            axes: axes,
            strongestAxisID: hasSpread ? strongest?.id : nil,
            weakestAxisID: hasSpread ? weakest?.id : nil,
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

    /// What you were doing, in two lines and no card.
    ///
    /// This is metadata, not content — giving it a glass surface of its own
    /// made it compete with the score for the top of the page. Category, date,
    /// time, duration, and difficulty collapse into one caption line; the
    /// prompt itself stays legible because it is the only thing here the user
    /// actually re-reads.
    @ViewBuilder
    private func contextStrip(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: contextIcon(recording))
                    .font(.system(size: 10, weight: .semibold))
                Text(contextMetaLine(recording))
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)

            if let prompt = recording.prompt {
                Text(prompt.text)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    Haptics.light()
                    editingTitleText = recording.customTitle ?? ""
                    isEditingTitle = true
                } label: {
                    HStack(spacing: 6) {
                        Text(recording.customTitle?.isEmpty == false ? recording.displayTitle : "Name this session")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(recording.customTitle?.isEmpty == false ? .white : .secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func contextIcon(_ recording: Recording) -> String {
        if recording.storyId != nil { return "book.pages" }
        if let category = recording.prompt?.category {
            return PromptCategory(rawValue: category)?.iconName ?? "text.bubble"
        }
        return "waveform"
    }

    /// "Storytelling · Hard · Mar 14, 9:41 AM · 1:04"
    private func contextMetaLine(_ recording: Recording) -> String {
        var parts: [String] = []

        if recording.storyId != nil {
            parts.append(recording.storyTitle ?? "Story Practice")
        } else if let category = recording.prompt?.category {
            parts.append(PromptCategory(rawValue: category)?.shortName ?? category)
        } else {
            parts.append("Free Practice")
        }

        if let difficulty = recording.prompt?.difficulty {
            parts.append(difficulty.displayName)
        }

        parts.append(recording.date.formatted(date: .abbreviated, time: .shortened))
        parts.append(recording.formattedDuration)

        return parts.joined(separator: " · ")
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
        // Bevel-style 2x2 metric grid — each tile interprets its number with
        // a status pill so the screen reads as a verdict, not a data dump.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricTile(
                icon: "speedometer",
                label: "Pace",
                value: "\(Int(analysis.wordsPerMinute))",
                unit: "wpm",
                status: paceStatus(for: analysis.wordsPerMinute)
            )
            MetricTile(
                icon: "exclamationmark.bubble",
                label: "Fillers",
                value: "\(analysis.totalFillerCount)",
                status: fillerStatus(for: analysis.totalFillerCount)
            )
            MetricTile(
                icon: "text.word.spacing",
                label: "Words",
                value: "\(analysis.totalWords)"
            )
            MetricTile(
                icon: "pause.circle",
                label: "Pauses",
                value: "\(analysis.pauseCount)"
            )
        }
    }

    private func paceStatus(for wpm: Double) -> MetricTile.Status {
        let target = Double(userSettings.first?.targetWPM ?? 150)
        if wpm < target - 40 { return .neutral("Slow") }
        if wpm > target + 40 { return .caution("Fast") }
        return .good("On pace")
    }

    private func fillerStatus(for count: Int) -> MetricTile.Status {
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
                    targetWPM: userSettings.first?.targetWPM ?? 150,
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
        GlassCard(tint: AppColors.primary.opacity(0.1)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share your progress")
                        .font(.subheadline.weight(.medium))
                    Text("Create a shareable score card")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    scoreCardImage = ScoreCardRenderer.render(recording: recording)
                    showingShareSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.primary)
                }
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

        if recording.analysis != nil {
            shareCTASection(recording)
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
                    if case .ready(let recording) = detailScreenState {
                        enqueueProcessingIfNeeded(recording, force: true)
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
                                        .foregroundStyle(value ? .green : .orange)
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

    private func scoreWeights(from settings: UserSettings?) -> ScoreWeights {
        guard let settings else { return .defaults }
        return ScoreWeights(
            clarity: settings.clarityWeight,
            pace: settings.paceWeight,
            filler: settings.fillerWeight,
            pause: settings.pauseWeight,
            vocalVariety: settings.vocalVarietyWeight,
            delivery: settings.deliveryWeight,
            vocabulary: settings.vocabularyWeight,
            structure: settings.structureWeight,
            relevance: settings.relevanceWeight
        )
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

        let weights = scoreWeights(from: userSettings.first)

        await speechService.enhanceWithLLM(
            analysis: &analysis,
            transcript: transcript,
            llmService: llmService,
            promptText: recording.prompt?.text,
            scoreWeights: weights
        )

        // Guard against view dismissal during async inference
        guard !Task.isCancelled else { return }

        recording.analysis = analysis
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

// MARK: - Playback Drawer Container

private struct PlaybackDrawerContainer: View {
    let recording: Recording
    let waveformHeights: [CGFloat]
    let playbackViewModel: RecordingDetailPlaybackViewModel
    let onTogglePlayback: () -> Void
    let onSeek: (Double) -> Void

    // Playback ticks (30 fps display link) are observed here — not in
    // RecordingDetailView — so only this drawer re-evaluates during playback,
    // not the whole detail scroll content.
    @Environment(AudioService.self) private var audioService

    // Collapsed by default: the collapsed row already shows the waveform and a
    // play button, which is the whole job most of the time, at a third of the
    // height the transport controls cost.
    @State private var drawerState: PlaybackDrawerState = .collapsed
    @State private var dragOffset: CGFloat = 0

    // Gesture tuning. Distances in points, velocities in points/sec.
    private let drawerSpring: Animation = .spring(response: 0.26, dampingFraction: 0.90)
    private let collapseDistance: CGFloat = 50      // drag-to-close threshold
    private let expandDistance: CGFloat = 40        // drag-to-open threshold
    private let flickVelocity: CGFloat = 320        // points/sec to snap on a flick
    private let rubberBandLimit: CGFloat = 56       // resistance sets in past this
    private let rubberBandFactor: CGFloat = 0.32    // smaller = stiffer past limit

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                // Grabber — widens and brightens when the drawer is already at
                // its maximum (expanded) height so the user reads the affordance
                // as "pull down to collapse" instead of "pull up for more".
                // Wrapped in a Button so VoiceOver users can toggle the drawer
                // without needing the drag gesture.
                Button {
                    Haptics.selection()
                    withAnimation(drawerSpring) {
                        drawerState = drawerState == .expanded ? .collapsed : .expanded
                    }
                } label: {
                    // Single chevron rotated in-place so the affordance flips
                    // smoothly in sync with the drawer's spring, instead of
                    // cross-fading between two separate SF Symbols.
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(drawerState == .expanded ? 0.55 : 0.35))
                        .rotationEffect(.degrees(drawerState == .expanded ? 180 : 0))
                        .padding(.top, 3)
                        .padding(.horizontal, 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(drawerState == .expanded ? "Collapse playback drawer" : "Expand playback drawer")
                .accessibilityAddTraits(.isButton)

                if drawerState == .expanded {
                    playbackControlSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    collapsedPlaybackBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
                    .ignoresSafeArea(edges: .bottom)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .ignoresSafeArea(edges: .bottom)
        .contentShape(Rectangle())
        .animation(drawerSpring, value: drawerState)
        .offset(y: dragOffset)
        .simultaneousGesture(
            // minimumDistance 3 keeps the grabber button tappable while still
            // picking up finger travel almost immediately — prevents the
            // "drag starts 10pt in" lag the old 10pt gate produced.
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    let translation = value.translation.height
                    // Direction filter: ignore drags that are mostly horizontal
                    // so the gesture does not fight sibling scroll/list views.
                    guard abs(translation) > abs(value.translation.width) else { return }
                    switch drawerState {
                    case .expanded:
                        // Top is the natural floor in this state: strictly
                        // clamp upward (negative) pulls to 0 — the drawer
                        // never peeks above its maximum height. Downward
                        // travel tracks the finger 1:1 until `rubberBandLimit`,
                        // then resistance climbs so the drawer feels tethered.
                        if translation <= 0 {
                            dragOffset = 0
                        } else {
                            dragOffset = Self.rubberBanded(
                                translation,
                                limit: rubberBandLimit,
                                factor: rubberBandFactor
                            )
                        }
                    case .collapsed:
                        // Inverse: upward is "open", downward is already past
                        // the floor of the collapsed state so rubber-band it
                        // firmly to signal the boundary.
                        if translation >= 0 {
                            dragOffset = Self.rubberBanded(
                                translation,
                                limit: 4,
                                factor: 0.18
                            )
                        } else {
                            dragOffset = -Self.rubberBanded(
                                -translation,
                                limit: rubberBandLimit,
                                factor: rubberBandFactor
                            )
                        }
                    }
                }
                .onEnded { value in
                    let translation = value.translation.height
                    let velocity = value.velocity.height     // points/sec, iOS 17+
                    let previousState = drawerState

                    // Snap decision blends distance and velocity:
                    //   — a short swipe with a strong flick still commits,
                    //   — a long slow drag also commits,
                    //   — everything else returns to its origin.
                    // Using the same spring as the state `.animation(_:value:)`
                    // so the offset release and the state change unwind as
                    // one motion, with no visible seam at the hand-off.
                    withAnimation(drawerSpring) {
                        switch drawerState {
                        case .expanded:
                            if translation > collapseDistance || velocity > flickVelocity {
                                drawerState = .collapsed
                            }
                        case .collapsed:
                            if translation < -expandDistance || velocity < -flickVelocity {
                                drawerState = .expanded
                            }
                        }
                        dragOffset = 0
                    }

                    // Physical confirmation only when the drawer actually
                    // commits to a new state — no haptic on return-to-origin.
                    if drawerState != previousState {
                        Haptics.light()
                    }
                }
        )
        .onChange(of: audioService.currentPlaybackTime) { _, _ in
            playbackViewModel.sync(from: audioService, fallbackDuration: recording.actualDuration)
        }
        .onChange(of: audioService.playbackDuration) { _, _ in
            playbackViewModel.sync(from: audioService, fallbackDuration: recording.actualDuration)
        }
        .onChange(of: audioService.isPlaying) { _, _ in
            playbackViewModel.sync(from: audioService, fallbackDuration: recording.actualDuration)
        }
    }

    /// Progressive resistance past `limit`: finger travel still moves the
    /// drawer but each additional point contributes `factor` as much. Keeps
    /// the drag feeling alive without letting the drawer slide unbounded.
    private static func rubberBanded(_ offset: CGFloat, limit: CGFloat, factor: CGFloat) -> CGFloat {
        guard offset > limit else { return offset }
        return limit + (offset - limit) * factor
    }

    /// Seekable waveform, shared by both drawer states so the collapsed row
    /// shows exactly the audio the expanded one does.
    private func scrubber(height: CGFloat) -> some View {
        GeometryReader { geometry in
            let barWidth: CGFloat = 3
            let spacing: CGFloat = 2
            let totalBarWidth = barWidth + spacing
            let barCount = max(1, Int(geometry.size.width / totalBarWidth))
            let width = geometry.size.width

            // Progress quantized to whole bars: the bar row's inputs
            // only change when a new bar fills, so the ~100 bar views
            // re-diff once per bar instead of on every 30 fps
            // display-link tick.
            ScrubberBars(
                barCount: barCount,
                playedBars: min(barCount, Int((playbackViewModel.playbackProgress * Double(barCount)).rounded(.up))),
                heights: waveformHeights,
                barWidth: barWidth,
                spacing: spacing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture { location in
                let progress = max(0, min(1, location.x / max(1, width)))
                onSeek(progress)
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        let progress = max(0, min(1, value.location.x / max(1, width)))
                        onSeek(progress)
                    }
            )
        }
        .frame(height: height)
        .accessibilityLabel("Playback position")
    }

    @ViewBuilder
    private var playbackControlSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(formatTime(playbackViewModel.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)

                scrubber(height: 32)

                Text(formatTime(playbackViewModel.playbackDuration > 0 ? playbackViewModel.playbackDuration : recording.actualDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            HStack(spacing: 22) {
                Button {
                    seekBy(seconds: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip back 10 seconds")

                Button {
                    onTogglePlayback()
                } label: {
                    Image(systemName: playbackViewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.white.opacity(0.94)))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playbackViewModel.isPlaying ? "Pause" : "Play")

                Button {
                    seekBy(seconds: 10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip forward 10 seconds")
            }
        }
    }

    /// Play button + the actual waveform + elapsed time in one 56pt row. A
    /// waveform next to a play button does not need a "Playback" caption, and
    /// showing the audio only in the tallest state was backwards.
    @ViewBuilder
    private var collapsedPlaybackBar: some View {
        HStack(spacing: 12) {
            Button {
                onTogglePlayback()
            } label: {
                Image(systemName: playbackViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.94)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playbackViewModel.isPlaying ? "Pause" : "Play")

            scrubber(height: 28)

            Text(formatTime(playbackViewModel.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(drawerSpring) {
                drawerState = .expanded
            }
        }
    }

    private func seekBy(seconds: TimeInterval) {
        let duration = max(playbackViewModel.playbackDuration, recording.actualDuration)
        guard duration > 0 else { return }
        let targetTime = min(max(playbackViewModel.currentTime + seconds, 0), duration)
        onSeek(targetTime / duration)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// POD scrubber bar row. All inputs are plain values, so SwiftUI skips the
/// whole row while `playedBars` is unchanged between display-link ticks.
private struct ScrubberBars: View {
    let barCount: Int
    let playedBars: Int
    let heights: [CGFloat]
    let barWidth: CGFloat
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < playedBars ? AppColors.primary : Color.white.opacity(0.2))
                    .frame(width: barWidth, height: heights.isEmpty ? 16 : heights[i % heights.count])
            }
        }
    }
}

// MARK: - Transcript Content (filler/vocab highlights)

private struct TranscriptContentView: View {
    let words: [TranscriptionWord]
    let turns: [SpeakerTurn]
    let showFillerHighlights: Bool
    let showVocabHighlights: Bool
    let showSpeakerTurns: Bool
    let hasSpeakerSeparation: Bool

    var body: some View {
        if showSpeakerTurns && hasSpeakerSeparation {
            SpeakerTurnTranscriptView(
                turns: turns,
                showFillerHighlights: showFillerHighlights,
                showVocabHighlights: showVocabHighlights
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            HighlightedTranscriptView(
                words: words,
                showFillerHighlights: showFillerHighlights,
                showVocabHighlights: showVocabHighlights
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Highlighted Transcript View

struct HighlightedTranscriptView: View {
    let words: [TranscriptionWord]
    let showFillerHighlights: Bool
    let showVocabHighlights: Bool

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(words) { word in
                WordView(
                    word: word,
                    showFillerHighlight: showFillerHighlights && word.isFiller,
                    showVocabHighlight: showVocabHighlights && word.isVocabWord
                )
            }
        }
    }
}

private struct SpeakerTurn: Identifiable {
    let id: Int
    let isPrimarySpeaker: Bool
    let words: [TranscriptionWord]
}

private struct SpeakerTurnTranscriptView: View {
    let turns: [SpeakerTurn]
    let showFillerHighlights: Bool
    let showVocabHighlights: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(turns) { turn in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: turn.isPrimarySpeaker ? "person.fill.checkmark" : "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(turn.isPrimarySpeaker ? AppColors.primary : .secondary)

                        Text(turn.isPrimarySpeaker ? "You" : "Other speaker")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(turn.isPrimarySpeaker ? AppColors.primary : .secondary)
                    }

                    HighlightedTranscriptView(
                        words: turn.words,
                        showFillerHighlights: showFillerHighlights,
                        showVocabHighlights: showVocabHighlights
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(turn.isPrimarySpeaker ? AppColors.primary.opacity(0.12) : .white.opacity(0.05))
                )
            }
        }
    }
}

struct WordView: View {
    let word: TranscriptionWord
    let showFillerHighlight: Bool
    let showVocabHighlight: Bool

    private var isHighlighted: Bool { showFillerHighlight || showVocabHighlight }
    private var highlightColor: Color { showFillerHighlight ? .orange : .green }

    private var foreground: Color {
        isHighlighted ? highlightColor : .primary
    }

    var body: some View {
        Text(word.word)
            .font(.body)
            .foregroundStyle(foreground)
            .padding(.horizontal, isHighlighted ? 4 : 0)
            .padding(.vertical, isHighlighted ? 2 : 0)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(highlightColor.opacity(0.2))
                }
            }
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

private enum PlaybackDrawerState {
    case expanded
    case collapsed
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

                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: goal.progress)
                            .stroke(AppColors.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
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
