import SwiftUI
import SwiftData
import AVKit

struct RecordingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let recordingId: String

    @State private var recording: Recording?
    @State private var isLoading = true
    @State private var isTranscribing = false
    @State private var showingDeleteAlert = false
    @State private var showingShareSheet = false
    @State private var showFillerHighlights = true
    @State private var showVocabHighlights = true
    @State private var waveformHeights: [CGFloat] = []
    @State private var scoreCardImage: UIImage?
    @State private var showingScoreCardPreview = false
    @State private var animateScore = false
    @State private var selectedDetailTab: DetailTab = .analysis
    @State private var isEditingTitle = false
    @State private var editingTitleText = ""
    @State private var showingListenBackEncouragement = false
    @State private var exportService = ExportService()
    @State private var pendingFeedback = false
    @State private var showingScoreWeights = false
    @State private var settingsViewModel = SettingsViewModel()
    @State private var showingFeedbackSheet = false
    @State private var llmInsight: String?
    @State private var isEnhancingCoherence = false
    @State private var transcriptionFailed = false
    @State private var playbackDrawerState: PlaybackDrawerState = .expanded
    @State private var playbackDrawerDragOffset: CGFloat = 0
    @State private var activePlaybackWordID: UUID?
    @State private var orderedTranscriptWords: [TranscriptionWord] = []
    @State private var orderedTranscriptRanges: [ClosedRange<TimeInterval>] = []
    @State private var playbackWordCursor = 0

    @Query private var userSettings: [UserSettings]

    // Services
    @Environment(AudioService.self) private var audioService
    @Environment(SpeechService.self) private var speechService
    @Environment(LLMService.self) private var llmService

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground(style: .subtle)

            if let recording {
                if recording.isProcessing || isTranscribing || (!speechService.isModelLoaded && recording.analysis == nil) || pendingFeedback {
                    if transcriptionFailed {
                        // Transcription failed — show retry instead of infinite spinner
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundStyle(AppColors.warning)
                            Text("Analysis Unavailable")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                            Text("Transcription could not be completed.\nThe speech model may still be loading.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                            GlassButton(title: "Retry Analysis", icon: "arrow.clockwise", style: .primary) {
                                retryTranscription()
                            }
                            GlassButton(title: "Go Back", icon: "chevron.left", style: .secondary) {
                                dismiss()
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 40)
                    } else {
                        // Full-page analyzing experience
                        AnalyzingView(
                            recording: recording,
                            isModelLoading: !speechService.isModelLoaded,
                            feedbackEnabled: userSettings.first?.sessionFeedbackEnabled ?? false,
                            feedbackQuestions: feedbackQuestionsForAnalyzing,
                            existingFeedback: recording.sessionFeedback,
                            onFeedbackSubmitted: { feedback in
                                recording.sessionFeedback = feedback
                                try? modelContext.save()
                            },
                            onFeedbackCompleted: {
                                withAnimation(.spring(response: 0.3)) {
                                    pendingFeedback = false
                                }
                            },
                            analysisReady: recording.analysis != nil
                        )
                    }
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 20) {
                            // Always visible: Prompt + Score + Stats
                            promptHeader(recording)

                            if let analysis = recording.analysis {
                                heroScoreSection(analysis)
                                statsGrid(analysis)
                            }

                            // Goal progress (if recording has goalId)
                            if recording.goalId != nil {
                                goalProgressCard(recording)
                            }

                            if let wpmData = recording.analysis?.wpmTimeSeries, wpmData.count >= 2 {
                                wpmChartSection(wpmData)
                            }

                            // Segmented tab picker
                            if recording.analysis != nil {
                                Picker("Detail", selection: $selectedDetailTab) {
                                    ForEach(DetailTab.allCases, id: \.self) { tab in
                                        Text(tab.rawValue).tag(tab)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 4)
                            }

                            // Tab content
                            switch selectedDetailTab {
                            case .analysis:
                                analysisTabContent(recording)
                            case .transcript:
                                transcriptTabContent(recording)
                            case .coaching:
                                coachingTabContent(recording)
                            }

                            // Actions (always at bottom)
                            actionsSection(recording)
                        }
                        .padding()
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .contentMargins(.horizontal, 0)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if hasPlayableMedia(recording) {
                            playbackDrawer(recording)
                        }
                    }
                    .onAppear {
                        prepareDetailAssets(for: recording)
                        playbackDrawerState = .expanded
                        playbackDrawerDragOffset = 0
                        updateActivePlaybackWord()
                    }
                    .onChange(of: audioService.playbackProgress) { _, _ in
                        updateActivePlaybackWord()
                    }
                    .onChange(of: audioService.isPlaying) { _, isPlaying in
                        if !isPlaying {
                            activePlaybackWordID = nil
                        } else {
                            updateActivePlaybackWord()
                        }
                    }
                    .task {
                        // Delay score animation
                        try? await Task.sleep(for: .milliseconds(300))
                        withAnimation(.easeOut(duration: 0.8)) {
                            animateScore = true
                        }
                    }
                }
            } else if isLoading {
                ProgressView("Loading...")
                    .padding(.top, 100)
            } else {
                ContentUnavailableView(
                    "Recording Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This recording may have been deleted.")
                )
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
                        if let recording {
                            scoreCardImage = ScoreCardRenderer.render(recording: recording)
                        }
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                            .frame(width: 28, height: 28)
                    }

                    Menu {
                        if let recording {
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
            populateWPMTimeSeriesIfNeeded()
            await transcribeIfNeeded()

            // Post-analysis: enhance coherence with LLM if available
            await enhanceCoherenceIfNeeded()
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
        .sheet(isPresented: $showingScoreWeights) {
            NavigationStack {
                ScoreWeightsView(viewModel: settingsViewModel)
            }
        }
        .onChange(of: showingShareSheet) { _, show in
            if show, let recording {
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
    .sheet(isPresented: $showingFeedbackSheet) {
        NavigationStack {
            SessionFeedbackSheet(
                questions: feedbackQuestionsForAnalyzing,
                onSubmit: { feedback in
                    recording?.sessionFeedback = feedback
                    try? modelContext.save()
                    showingFeedbackSheet = false
                }
            )
        }
    }
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

    // MARK: - Playback Control Section

    @ViewBuilder
    private func playbackControlSection(_ recording: Recording) -> some View {
        VStack(spacing: 14) {
            // Waveform with timestamps
            HStack(spacing: 10) {
                Text(formatTime(audioService.playbackProgress * audioService.playbackDuration))
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
                            let isPlayed = progress < audioService.playbackProgress
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
                        audioService.seek(to: progress)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                // Only seek on predominantly horizontal drags
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                let progress = max(0, min(1, value.location.x / max(1, width)))
                                audioService.seek(to: progress)
                            }
                    )
                }
                .frame(height: 32)

                Text(formatTime(audioService.playbackDuration > 0 ? audioService.playbackDuration : recording.actualDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            // Play button
            Button {
                togglePlayback(recording)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                    Text(audioService.isPlaying ? "Pause" : "Listen Back")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(Color.teal)
                }
            }
            .buttonStyle(.plain)
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
            Label("Transcript", systemImage: "doc.text.fill")
                .font(.headline)

            GlassCard {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func transcriptSectionWithHighlights(_ words: [TranscriptionWord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Transcript", systemImage: "doc.text.fill")
                    .font(.headline)

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        showFillerHighlights.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showFillerHighlights ? "eye.fill" : "eye.slash")
                            Text("Fillers")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(showFillerHighlights ? .orange : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(showFillerHighlights ? .orange.opacity(0.1) : .clear)
                        }
                    }

                    Button {
                        showVocabHighlights.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showVocabHighlights ? "eye.fill" : "eye.slash")
                            Text("Vocab")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(showVocabHighlights ? .green : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(showVocabHighlights ? .green.opacity(0.1) : .clear)
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 0) {
                    HighlightedTranscriptView(
                        words: words,
                        showFillerHighlights: showFillerHighlights,
                        showVocabHighlights: showVocabHighlights,
                        activePlaybackWordID: activePlaybackWordID
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    if let analysis = recording?.analysis, !analysis.vocabWordsUsed.isEmpty {
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
            transcriptSectionWithHighlights(words)
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

                Text(isAppleIntelligence ? "AI" : LocalLLMService.modelDisplayName)
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
                    VStack(alignment: .leading, spacing: 8) {
                        if let markdown = formattedAIInsight(insight) {
                            Text(markdown)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(insight)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                GlassButton(title: "Generate AI Coaching", icon: "sparkles", style: .secondary, fullWidth: true) {
                    Haptics.medium()
                    Task {
                        guard let analysis = recording.analysis else { return }
                        let transcript = recording.transcriptionText ?? ""
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
                    showingFeedbackSheet = true
                }
            }
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

    private func formattedAIInsight(_ insight: String) -> AttributedString? {
        let trimmed = insight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            return try AttributedString(
                markdown: trimmed,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            )
        } catch {
            return nil
        }
    }

    private func prepareDetailAssets(for recording: Recording) {
        prepareTranscriptPlaybackWords(from: recording)

        guard waveformHeights.isEmpty || audioService.playbackDuration <= 0 else { return }
        let mediaURL = recording.audioURL ?? recording.videoURL
        let needsWaveform = waveformHeights.isEmpty
        let existingHeights = waveformHeights

        Task(priority: .utility) {
            let prepared = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let generatedHeights: [CGFloat]
                    if needsWaveform, let mediaURL {
                        generatedHeights = AudioWaveformGenerator.generate(from: mediaURL, binCount: 50)
                    } else {
                        generatedHeights = existingHeights
                    }

                    continuation.resume(returning: generatedHeights)
                }
            }

            guard !Task.isCancelled else { return }
            if waveformHeights.isEmpty {
                waveformHeights = prepared
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
            updateActivePlaybackWord()
        }
    }

    private func prepareTranscriptPlaybackWords(from recording: Recording) {
        let words = (recording.transcriptionWords ?? [])
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        orderedTranscriptWords = words
        orderedTranscriptRanges = words.map { $0.start...$0.end }
        playbackWordCursor = 0
        activePlaybackWordID = nil
    }

    private func updateActivePlaybackWord() {
        guard !orderedTranscriptWords.isEmpty else {
            activePlaybackWordID = nil
            return
        }

        if audioService.playbackDuration <= 0 {
            activePlaybackWordID = nil
            return
        }

        let currentTime = max(0, audioService.playbackProgress) * audioService.playbackDuration
        guard let matchedIndex = wordIndexForPlaybackTime(currentTime) else {
            activePlaybackWordID = nil
            return
        }
        playbackWordCursor = matchedIndex
        activePlaybackWordID = orderedTranscriptWords[matchedIndex].id
    }

    private func wordIndexForPlaybackTime(_ time: TimeInterval) -> Int? {
        guard !orderedTranscriptRanges.isEmpty else { return nil }
        let toleranceBefore: TimeInterval = 0.08
        let toleranceAfter: TimeInterval = 0.14

        var low = 0
        var high = orderedTranscriptRanges.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let range = orderedTranscriptRanges[mid]

            if time < range.lowerBound - toleranceBefore {
                high = mid - 1
            } else if time > range.upperBound + toleranceAfter {
                low = mid + 1
            } else {
                return mid
            }
        }

        // During brief pauses between words, keep highlighting the latest spoken word.
        let fallback = min(max(low - 1, 0), orderedTranscriptRanges.count - 1)
        return orderedTranscriptRanges.indices.contains(fallback) ? fallback : nil
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
            // transcribeIfNeeded() will re-process if analysis is still nil.
            if let recording, recording.isProcessing {
                recording.isProcessing = false
                try? modelContext.save()
            }
        } catch {
            print("Error loading recording: \(error)")
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

    private func transcribeIfNeeded() async {
        guard let recording,
              recording.transcriptionText == nil,
              recording.analysis == nil,
              let audioURL = recording.audioURL ?? recording.videoURL else {
            return
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            transcriptionFailed = true
            return
        }

        isTranscribing = true
        recording.isProcessing = true

        // Activate pending feedback if enabled and not already submitted
        let feedbackEnabled = userSettings.first?.sessionFeedbackEnabled ?? false
        if feedbackEnabled && recording.sessionFeedback == nil {
            pendingFeedback = true
        }

        defer {
            isTranscribing = false
            recording.isProcessing = false
        }

        do {
            // Fetch settings for analysis configuration
            let settingsDescriptor = FetchDescriptor<UserSettings>()
            let settings = (try? modelContext.fetch(settingsDescriptor))?.first
            let vocabWords = settings?.vocabWords ?? []
            let preferredTerms = vocabWords

            // Build filler config from user settings
            let fillerConfig = FillerWordConfig(
                customFillers: Set(settings?.customFillerWords ?? []),
                customContextFillers: Set(settings?.customContextFillerWords ?? []),
                removedDefaults: Set(settings?.removedDefaultFillers ?? [])
            )

            let result = try await speechService.transcribe(
                audioURL: audioURL,
                fillerConfig: fillerConfig,
                preferredTerms: preferredTerms
            )

            // Build score weights from user settings
            var weights = ScoreWeights.defaults
            if let s = settings {
                weights.clarity = s.clarityWeight
                weights.pace = s.paceWeight
                weights.filler = s.fillerWeight
                weights.pause = s.pauseWeight
                weights.vocalVariety = s.vocalVarietyWeight
                weights.delivery = s.deliveryWeight
                weights.vocabulary = s.vocabularyWeight
                weights.structure = s.structureWeight
                weights.relevance = s.relevanceWeight
            }

            let resultSnapshot = result
            let actualDuration = recording.actualDuration
            let audioLevelSamples = recording.audioLevelSamples ?? []
            let promptText = recording.prompt?.text
            let targetWPM = settings?.targetWPM ?? 150
            let trackFillerWords = settings?.trackFillerWords ?? true
            let trackPauses = settings?.trackPauses ?? true
            let vocabWordsSnapshot = vocabWords
            let weightSnapshot = weights

            let computed = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let analyzer = SpeechService()
                    let analysis = analyzer.analyze(
                        transcription: resultSnapshot,
                        actualDuration: actualDuration,
                        vocabWords: vocabWordsSnapshot,
                        audioLevelSamples: audioLevelSamples,
                        audioURL: audioURL,
                        promptText: promptText,
                        targetWPM: targetWPM,
                        trackFillerWords: trackFillerWords,
                        trackPauses: trackPauses,
                        scoreWeights: weightSnapshot
                    )
                    let markedWords = analyzer.markVocabWordsInTranscription(
                        resultSnapshot.words,
                        vocabWords: vocabWordsSnapshot
                    )
                    continuation.resume(returning: (analysis, markedWords))
                }
            }

            recording.transcriptionText = result.text
            recording.transcriptionWords = computed.1
            recording.analysis = computed.0
            prepareTranscriptPlaybackWords(from: recording)

            try modelContext.save()
        } catch {
            print("Transcription error: \(error)")
            transcriptionFailed = true
        }
    }

    private func retryTranscription() {
        transcriptionFailed = false
        Task {
            await transcribeIfNeeded()
            await enhanceCoherenceIfNeeded()
        }
    }

    private func enhanceCoherenceIfNeeded() async {
        guard let recording,
              var analysis = recording.analysis,
              let transcript = recording.transcriptionText else { return }

        // If model is downloaded but not loaded, kick off loading in background
        // but don't block this task waiting for it
        if !llmService.isAvailable && llmService.localLLM.isModelDownloaded {
            Task {
                await llmService.loadLocalModelIfNeeded()
            }
            return
        }

        guard llmService.isAvailable else { return }

        isEnhancingCoherence = true
        defer { isEnhancingCoherence = false }

        // Build score weights from user settings
        var weights = ScoreWeights.defaults
        if let s = userSettings.first {
            weights.clarity = s.clarityWeight
            weights.pace = s.paceWeight
            weights.filler = s.fillerWeight
            weights.pause = s.pauseWeight
            weights.vocalVariety = s.vocalVarietyWeight
            weights.delivery = s.deliveryWeight
            weights.vocabulary = s.vocabularyWeight
            weights.structure = s.structureWeight
            weights.relevance = s.relevanceWeight
        }

        // Pass prompt text for prompt-aware coherence scoring
        let promptText = recording.prompt?.text

        await speechService.enhanceWithLLM(
            analysis: &analysis,
            transcript: transcript,
            llmService: llmService,
            promptText: promptText,
            scoreWeights: weights
        )

        // Guard against view dismissal during async inference
        guard !Task.isCancelled else { return }

        recording.analysis = analysis
        try? modelContext.save()

        // Auto-generate coaching insight so it's ready on the coaching tab
        guard !Task.isCancelled else { return }
        if llmInsight == nil {
            llmInsight = await llmService.generateCoachingInsight(
                from: analysis,
                transcript: transcript
            )
        }
    }

    private func togglePlayback(_ recording: Recording) {
        guard let url = recording.audioURL ?? recording.videoURL else { return }
        if audioService.isPlaying {
            audioService.pause()
        } else {
            // Check for first-time listen-back
            if let settings = userSettings.first, settings.listenBackCount == 0 {
                showingListenBackEncouragement = true
                return
            }
            Task {
                playbackDrawerState = .expanded
                try? await audioService.play(url: url)
                updateActivePlaybackWord()
            }
        }
    }

    private func proceedWithPlayback() {
        // Increment listen-back count
        if let settings = userSettings.first {
            settings.listenBackCount += 1
            try? modelContext.save()
        }
        guard let recording, let url = recording.audioURL ?? recording.videoURL else { return }
        Task {
            playbackDrawerState = .expanded
            try? await audioService.play(url: url)
            updateActivePlaybackWord()
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

        // Capture file URLs before nilling out
        let audioURL = recording.audioURL
        let videoURL = recording.videoURL

        // Nil out local state FIRST so SwiftUI stops rendering the deleted object
        self.recording = nil

        // Dismiss before deletion to avoid accessing deleted object during animation
        dismiss()

        // Clean up files and delete from context after dismiss
        Task { @MainActor in
            if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
            if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
            modelContext.delete(recording)
            try? modelContext.save()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func hasPlayableMedia(_ recording: Recording) -> Bool {
        (recording.audioURL ?? recording.videoURL) != nil
    }

    @ViewBuilder
    private func playbackDrawer(_ recording: Recording) -> some View {
        VStack(spacing: 0) {
            if playbackDrawerState != .hidden {
                VStack(spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 40, height: 4)
                        .padding(.top, 8)

                    if playbackDrawerState == .expanded {
                        playbackControlSection(recording)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if playbackDrawerState == .collapsed {
                        collapsedPlaybackBar(recording)
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
            } else {
                // Hidden: show a small pull-up tab to restore the drawer
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        playbackDrawerState = .collapsed
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.bold))
                        Image(systemName: "waveform")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: playbackDrawerState)
        .offset(y: playbackDrawerDragOffset)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let translation = value.translation.height
                    // Only handle predominantly vertical drags
                    guard abs(translation) > abs(value.translation.width) else { return }
                    if playbackDrawerState == .expanded || playbackDrawerState == .collapsed {
                        playbackDrawerDragOffset = max(-56, min(56, translation))
                    }
                }
                .onEnded { value in
                    let translation = value.translation.height
                    let velocity = value.predictedEndTranslation.height

                    withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                        playbackDrawerDragOffset = 0

                        if playbackDrawerState == .expanded && (translation > 34 || velocity > 180) {
                            // Moderate swipe down from expanded — collapse
                            playbackDrawerState = .collapsed
                        } else if playbackDrawerState == .collapsed && (translation < -30 || velocity < -170) {
                            // Swipe up from collapsed — expand
                            playbackDrawerState = .expanded
                        }
                    }
                }
        )
    }

    @ViewBuilder
    private func collapsedPlaybackBar(_ recording: Recording) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)

            Text(audioService.isPlaying ? "Now Playing" : "Playback")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Text(formatTime(audioService.playbackProgress * max(audioService.playbackDuration, recording.actualDuration)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                togglePlayback(recording)
            } label: {
                Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
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
                playbackDrawerState = .expanded
            }
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

// MARK: - Stat Grid Item

struct StatGridItem: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(value)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Highlighted Transcript View

struct HighlightedTranscriptView: View {
    let words: [TranscriptionWord]
    let showFillerHighlights: Bool
    let showVocabHighlights: Bool
    let activePlaybackWordID: UUID?

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(words) { word in
                WordView(
                    word: word,
                    showFillerHighlight: showFillerHighlights && word.isFiller,
                    showVocabHighlight: showVocabHighlights && word.isVocabWord,
                    isActivePlaybackWord: activePlaybackWordID == word.id
                )
            }
        }
    }
}

struct WordView: View {
    let word: TranscriptionWord
    let showFillerHighlight: Bool
    let showVocabHighlight: Bool
    let isActivePlaybackWord: Bool

    private var isHighlighted: Bool { isActivePlaybackWord || showFillerHighlight || showVocabHighlight }
    private var highlightColor: Color { showFillerHighlight ? .orange : .green }

    var body: some View {
        Text(word.word)
            .font(.body)
            .foregroundStyle(isActivePlaybackWord ? .teal : (isHighlighted ? highlightColor : .primary))
            .padding(.horizontal, isHighlighted ? 4 : 0)
            .padding(.vertical, isHighlighted ? 2 : 0)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 4)
                        .fill((isActivePlaybackWord ? Color.teal : highlightColor).opacity(0.2))
                }
            }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    struct CacheData {
        var size: CGSize
        var positions: [CGPoint]
    }

    func makeCache(subviews: Subviews) -> CacheData {
        CacheData(size: .zero, positions: [])
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        cache = CacheData(size: result.size, positions: result.positions)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        for (index, position) in cache.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: totalWidth, height: totalHeight), positions)
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
    case hidden
}

// MARK: - Session Feedback Sheet

struct SessionFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let questions: [FeedbackQuestion]
    let onSubmit: (SessionFeedback) -> Void

    @State private var scaleAnswers: [UUID: Int] = [:]
    @State private var boolAnswers: [UUID: Bool] = [:]

    private var allQuestionsAnswered: Bool {
        questions.allSatisfy { q in
            q.type == .scale ? scaleAnswers[q.id] != nil : boolAnswers[q.id] != nil
        }
    }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.message.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.teal)

                        Text("Quick Self-Check")
                            .font(.title3.weight(.bold))

                        Text("How did you feel about this session?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(question.text)
                                    .font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)

                                if question.type == .scale {
                                    sheetScaleInput(questionId: question.id)
                                } else {
                                    sheetYesNoInput(questionId: question.id)
                                }
                            }
                        }
                    }

                    if allQuestionsAnswered {
                        GlassButton(title: "Submit", icon: "checkmark.circle", style: .primary, fullWidth: true) {
                            submitFeedback()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Self-Assessment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func sheetScaleInput(questionId: UUID) -> some View {
        let selected = scaleAnswers[questionId]
        let labels = ["Very Poor", "Poor", "Okay", "Good", "Excellent"]
        let icons = ["face.dashed", "face.smiling.inverse", "face.smiling", "hand.thumbsup", "star.fill"]

        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { value in
                let isSelected = selected == value
                let scoreColor = AppColors.scoreColor(for: value * 20)

                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        scaleAnswers[questionId] = value
                    }
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(isSelected ? scoreColor.opacity(0.2) : Color.white.opacity(0.06))
                                .overlay {
                                    Circle()
                                        .strokeBorder(
                                            isSelected ? scoreColor.opacity(0.6) : Color.white.opacity(0.1),
                                            lineWidth: isSelected ? 2 : 1
                                        )
                                }

                            Image(systemName: icons[value - 1])
                                .font(.system(size: isSelected ? 20 : 16))
                                .foregroundStyle(isSelected ? scoreColor : .white.opacity(0.4))
                        }
                        .frame(width: 48, height: 48)
                        .scaleEffect(isSelected ? 1.1 : 1.0)

                        Text(labels[value - 1])
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
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
    }

    @ViewBuilder
    private func sheetYesNoInput(questionId: UUID) -> some View {
        let selected = boolAnswers[questionId]

        HStack(spacing: 12) {
            yesNoOption(label: "Yes", icon: "hand.thumbsup.fill", value: true, tint: AppColors.success, isSelected: selected == true, questionId: questionId)
            yesNoOption(label: "No", icon: "hand.thumbsdown.fill", value: false, tint: AppColors.warning, isSelected: selected == false, questionId: questionId)
        }
    }

    private func yesNoOption(label: String, icon: String, value: Bool, tint: Color, isSelected: Bool, questionId: UUID) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                boolAnswers[questionId] = value
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? tint : .white.opacity(0.3))

                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
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

    private func submitFeedback() {
        let answers: [FeedbackAnswer] = questions.map { question in
            FeedbackAnswer(
                questionId: question.id,
                questionText: question.text,
                type: question.type,
                scaleValue: question.type == .scale ? scaleAnswers[question.id] : nil,
                boolValue: question.type == .yesNo ? boolAnswers[question.id] : nil
            )
        }
        Haptics.success()
        onSubmit(SessionFeedback(answers: answers))
    }
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
