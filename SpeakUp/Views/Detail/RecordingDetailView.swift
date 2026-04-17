import SwiftUI
import SwiftData
import AVKit

struct RecordingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let recordingId: String

    @State private var recording: Recording?
    @State private var isLoading = true
    @State private var showingDeleteAlert = false
    @State private var showingShareSheet = false
    @State private var showFillerHighlights = true
    @State private var showVocabHighlights = true
    @State private var showSpeakerTurns = true
    @State private var waveformHeights: [CGFloat] = []
    @State private var scoreCardImage: UIImage?
    @State private var animateScore = false
    @State private var selectedDetailTab: DetailTab = .analysis
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
    @State private var dismissedFeedbackGates: Set<UUID> = []
    @State private var storiesViewModel = StoriesViewModel()
    @State private var playbackViewModel = RecordingDetailPlaybackViewModel()

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
        !dismissedFeedbackGates.contains(recording.id)
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
                        dismissedFeedbackGates.insert(recording.id)
                        if recording.analysis != nil {
                            recording.isProcessing = false
                            try? modelContext.save()
                        }
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
            if case .ready(let recording) = detailScreenState {
                prepareDetailAssets(for: recording)
                configurePlaybackState(for: recording)
                enqueueProcessingIfNeeded(recording)
            }
            populateWPMTimeSeriesIfNeeded()


            // Post-analysis: enhance coherence in background — don't block the detail view
            Task {
                await enhanceCoherenceIfNeeded()
            }
        }
        .onDisappear {
            audioService.stop()
        }
        .onChange(of: audioService.currentPlaybackTime) { _, _ in
            syncPlaybackStateIfNeeded()
        }
        .onChange(of: audioService.playbackDuration) { _, _ in
            syncPlaybackStateIfNeeded()
        }
        .onChange(of: audioService.isPlaying) { _, _ in
            syncPlaybackStateIfNeeded()
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
            VStack(spacing: 20) {
                promptHeader(recording)

                if let analysis = recording.analysis {
                    heroScoreSection(analysis)
                    statsGrid(analysis)
                }

                if recording.goalId != nil {
                    goalProgressCard(recording)
                }

                if let wpmData = recording.analysis?.wpmTimeSeries, wpmData.count >= 2 {
                    wpmChartSection(wpmData)
                }

                if recording.analysis != nil {
                    Picker("Detail", selection: $selectedDetailTab) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)
                }

                switch selectedDetailTab {
                case .analysis:
                    analysisTabContent(recording)
                case .transcript:
                    transcriptTabContent(recording)
                case .coaching:
                    coachingTabContent(recording)
                }

                actionsSection(recording)
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .contentMargins(.horizontal, 0)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasPlayableMedia(recording) {
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
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.8)) {
                animateScore = true
            }
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

    // MARK: - Hero Score Section

    @ViewBuilder
    private func heroScoreSection(_ analysis: SpeechAnalysis) -> some View {
        GlassCard(tint: AppColors.glassTintPrimary) {
            VStack(spacing: 18) {
                HStack {
                    Label("SpeakUp Score", systemImage: "waveform.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }

                HStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 10)
                            .frame(width: 112, height: 112)
                        Circle()
                            .trim(from: 0, to: animateScore ? Double(analysis.speechScore.overall) / 100 : 0)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        AppColors.scoreColor(for: analysis.speechScore.overall).opacity(0.55),
                                        AppColors.scoreColor(for: analysis.speechScore.overall)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .frame(width: 112, height: 112)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.8), value: animateScore)

                        VStack(spacing: 1) {
                            Text("\(animateScore ? analysis.speechScore.overall : 0)")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.scoreColor(for: analysis.speechScore.overall))
                                .contentTransition(.numericText())
                            Text("/100")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 10) {
                        scoreSnapshotRow(label: "Clarity", value: analysis.speechScore.subscores.clarity, color: .blue)
                        scoreSnapshotRow(label: "Pace", value: analysis.speechScore.subscores.pace, color: .green)
                        scoreSnapshotRow(label: "Fillers", value: analysis.speechScore.subscores.fillerUsage, color: .orange)
                        scoreSnapshotRow(label: "Pauses", value: analysis.speechScore.subscores.pauseQuality, color: .purple)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let textQuality = analysis.textQuality {
                    HStack(spacing: 8) {
                        scoreSignalChip(title: "Conciseness", score: textQuality.concisenessScore, icon: "scissors")
                        scoreSignalChip(title: "Engagement", score: textQuality.engagementScore, icon: "person.3.sequence")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func scoreSnapshotRow(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.6), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 90 * CGFloat(value) / 100)
            }
            .frame(width: 90, height: 7)
            Text("\(value)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, alignment: .leading)
        }
    }

    @ViewBuilder
    private func scoreSignalChip(title: String, score: Int, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text("\(title) \(score)")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AppColors.scoreColor(for: score))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(AppColors.scoreColor(for: score).opacity(0.15))
        }
    }


    // MARK: - Prompt Header

    @ViewBuilder
    private func promptHeader(_ recording: Recording) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let prompt = recording.prompt {
                        Label(prompt.category, systemImage: PromptCategory(rawValue: prompt.category)?.iconName ?? "text.bubble")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(PromptCategory(rawValue: prompt.category)?.color ?? .teal)
                    } else {
                        Label("Free Practice", systemImage: "waveform")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.teal)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(recording.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(recording.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.85))
                    }
                }

                if let prompt = recording.prompt {
                    Text(prompt.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                } else {
                    // Editable title for free practice sessions
                    Button {
                        editingTitleText = recording.customTitle ?? ""
                        isEditingTitle = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(recording.displayTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)

                            Image(systemName: "pencil.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.teal.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)

                    if recording.customTitle == nil {
                        Text("Tap to add a title or question")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(recording.formattedDuration)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let difficulty = recording.prompt?.difficulty {
                        DifficultyBadge(difficulty: difficulty)
                    }

                    if recording.storyId != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "book.pages")
                                .font(.caption2)
                            Text(recording.storyTitle ?? "Story Practice")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(.purple.opacity(0.12))
                        }
                    }
                }
            }
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

    // MARK: - Stats Grid

    @ViewBuilder
    private func statsGrid(_ analysis: SpeechAnalysis) -> some View {
        GlassCard(padding: 14) {
            HStack(spacing: 0) {
                PromptStatItem(
                    icon: "speedometer",
                    value: "\(Int(analysis.wordsPerMinute))",
                    label: "WPM",
                    color: .cyan
                )

                statsGridDivider

                PromptStatItem(
                    icon: "text.word.spacing",
                    value: "\(analysis.totalWords)",
                    label: "Words",
                    color: .white
                )

                statsGridDivider

                PromptStatItem(
                    icon: "exclamationmark.bubble",
                    value: "\(analysis.totalFillerCount)",
                    label: "Fillers",
                    color: analysis.totalFillerCount > 5 ? .orange : .green
                )

                statsGridDivider

                PromptStatItem(
                    icon: "pause.circle",
                    value: "\(analysis.pauseCount)",
                    label: "Pauses",
                    color: .green
                )
            }
        }
    }

    private var statsGridDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 40)
    }

    // MARK: - WPM Chart Section

    @ViewBuilder
    private func wpmChartSection(_ wpmData: [WPMDataPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pace Over Time", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

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
            Label("Filler Words Used", systemImage: "exclamationmark.bubble.fill")
                .font(.headline)

            GlassCard {
                VStack(spacing: 12) {
                    ForEach(fillerWords.prefix(5)) { filler in
                        HStack {
                            Text(filler.word)
                                .font(.subheadline)

                            Spacer()

                            Text("\(filler.count)×")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
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
                Label("Transcript", systemImage: "doc.text.fill")
                    .font(.headline)

                Spacer()

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
                Label("Transcript", systemImage: "doc.text.fill")
                    .font(.headline)

                Spacer()

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
                        }
                    }

                    Button {
                        showFillerHighlights.toggle()
                    } label: {
                        Image(systemName: showFillerHighlights ? "bubble.left.fill" : "bubble.left")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(showFillerHighlights ? .orange : .secondary)
                            .padding(6)
                            .background {
                                Circle()
                                    .fill(showFillerHighlights ? .orange.opacity(0.1) : .clear)
                            }
                    }

                    Button {
                        showVocabHighlights.toggle()
                    } label: {
                        Image(systemName: showVocabHighlights ? "character.book.closed.fill" : "character.book.closed")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(showVocabHighlights ? .green : .secondary)
                            .padding(6)
                            .background {
                                Circle()
                                    .fill(showVocabHighlights ? .green.opacity(0.1) : .clear)
                            }
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
                                .foregroundStyle(.green)

                            Text("Vocab:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)

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
        }
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
        GlassCard(tint: .teal.opacity(0.1)) {
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
                    .foregroundStyle(.teal)
                }
            }
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private func actionsSection(_ recording: Recording) -> some View {
        GlassButton(
            title: "Delete Recording",
            icon: "trash",
            style: .danger,
            fullWidth: true
        ) {
            showingDeleteAlert = true
        }
        .padding(.top, 12)
    }


    // MARK: - Tab Content

    @ViewBuilder
    private func analysisTabContent(_ recording: Recording) -> some View {
        DetailAnalysisTab(recording: recording, showingScoreWeights: $showingScoreWeights)
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
                                        : [.cyan, .teal],
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
                            .tint(.teal)
                        Text("Generating personalized insights...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            } else if let insight = llmInsight {
                GlassCard(tint: .purple.opacity(0.05)) {
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
        FeaturedGlassCard(gradientColors: [.teal.opacity(0.1), .cyan.opacity(0.05)]) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.message.fill")
                        .font(.title2)
                        .foregroundStyle(.teal)

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
            Label("Self-Assessment", systemImage: "checkmark.message")
                .font(.headline)

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

    private func syncPlaybackStateIfNeeded() {
        guard let recording else { return }
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
            if let loadedRecording = recording, loadedRecording.isProcessing {
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
        guard case .ready(let recording) = detailScreenState,
              var analysis = recording.analysis else { return }

        let transcript = resolvedTranscript(for: recording)
        guard !transcript.isEmpty else { return }

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

    @State private var drawerState: PlaybackDrawerState = .expanded
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 40, height: 4)
                    .padding(.top, 8)

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
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: drawerState)
        .offset(y: dragOffset)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let translation = value.translation.height
                    guard abs(translation) > abs(value.translation.width) else { return }
                    if drawerState == .expanded || drawerState == .collapsed {
                        dragOffset = max(-56, min(56, translation))
                    }
                }
                .onEnded { value in
                    let translation = value.translation.height
                    let velocity = value.predictedEndTranslation.height

                    withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                        dragOffset = 0

                        if drawerState == .expanded && (translation > 34 || velocity > 180) {
                            drawerState = .collapsed
                        } else if drawerState == .collapsed && (translation < -30 || velocity < -170) {
                            drawerState = .expanded
                        }
                    }
                }
        )
        .onAppear {
            drawerState = .expanded
            dragOffset = 0
        }
        .onChange(of: playbackViewModel.isPlaying) { _, isPlaying in
            if isPlaying {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    drawerState = .expanded
                }
            }
        }
    }

    @ViewBuilder
    private var playbackControlSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Label(
                    playbackViewModel.isPlaying ? "Now Playing" : "Playback",
                    systemImage: playbackViewModel.isPlaying ? "waveform.circle.fill" : "waveform"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

                Spacer()

                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                        drawerState = .collapsed
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Text(formatTime(playbackViewModel.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)

                GeometryReader { geometry in
                    let barWidth: CGFloat = 3
                    let spacing: CGFloat = 2
                    let totalBarWidth = barWidth + spacing
                    let barCount = max(1, Int(geometry.size.width / totalBarWidth))
                    let width = geometry.size.width

                    HStack(spacing: spacing) {
                        ForEach(0..<barCount, id: \.self) { i in
                            let progress = Double(i) / Double(barCount)
                            let isPlayed = progress < playbackViewModel.playbackProgress
                            let height: CGFloat = waveformHeights.isEmpty ? 16 : waveformHeights[i % waveformHeights.count]

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(isPlayed ? Color.teal : Color.white.opacity(0.2))
                                .frame(width: barWidth, height: height)
                        }
                    }
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
                .frame(height: 32)

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
                }
                .buttonStyle(.plain)

                Button {
                    onTogglePlayback()
                } label: {
                    Image(systemName: playbackViewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.teal))
                }
                .buttonStyle(.plain)

                Button {
                    seekBy(seconds: 10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var collapsedPlaybackBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)

            Text(playbackViewModel.isPlaying ? "Now Playing" : "Playback")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Text(formatTime(playbackViewModel.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                onTogglePlayback()
            } label: {
                Image(systemName: playbackViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.teal))
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
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

// MARK: - Subscore Row

struct SubscoreRow: View {
    let title: String
    let score: Int
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))

                    Capsule()
                        .fill(AppColors.scoreColor(for: score))
                        .frame(width: geometry.size.width * CGFloat(score) / 100)
                }
            }
            .frame(width: 60, height: 6)

            Text("\(score)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppColors.scoreColor(for: score))
                .frame(width: 30, alignment: .trailing)
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

enum DetailTab: String, CaseIterable {
    case analysis = "Analysis"
    case transcript = "Transcript"
    case coaching = "Coaching"
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
            GlassCard(tint: .teal.opacity(0.08)) {
                HStack(spacing: 12) {
                    Image(systemName: goal.type.iconName)
                        .font(.title3)
                        .foregroundStyle(.teal)
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

#Preview {
    NavigationStack {
        RecordingDetailView(recordingId: UUID().uuidString)
    }
    .modelContainer(for: [Recording.self, Prompt.self], inMemory: true)
}
