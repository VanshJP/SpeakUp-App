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
    @State private var isEditingTitle = false
    @State private var editingTitleText = ""
    @State private var showingListenBackEncouragement = false
    @State private var exportService = ExportService()

    @Query private var userSettings: [UserSettings]

    // Services
    @Environment(AudioService.self) private var audioService
    @Environment(SpeechService.self) private var speechService

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground(style: .subtle)

            if let recording {
                ScrollView(.vertical) {
                    VStack(spacing: 16) {
                        // 1. Prompt Header
                        promptHeader(recording)

                        // 2. Score Card - Hero element
                        if let analysis = recording.analysis {
                            heroScoreSection(analysis)
                        } else if recording.isProcessing || isTranscribing {
                            processingSection
                        } else if !speechService.isModelLoaded && recording.analysis == nil {
                            modelLoadingSection
                        }

                        // 3. Stats Grid
                        if let analysis = recording.analysis {
                            statsGrid(analysis)
                        }

                        // 4. Playback Control
                        playbackControlSection(recording)

                        // 5. Transcript
                        if let words = recording.transcriptionWords, !words.isEmpty {
                            transcriptSectionWithHighlights(words)
                        } else if let text = recording.transcriptionText, !text.isEmpty {
                            transcriptSection(text)
                        }

                        // 6. Filler Words
                        if let analysis = recording.analysis, !analysis.fillerWords.isEmpty {
                            fillerWordsSection(analysis.fillerWords)
                        }

                        // 8. Detailed Scores
                        if let analysis = recording.analysis {
                            subscoresSection(analysis)
                        }

                        // Pause Breakdown
                        if let analysis = recording.analysis {
                            pauseAnalysisSection(analysis)
                        }

                        // 10. Volume & Energy
                        if let volume = recording.analysis?.volumeMetrics {
                            volumeSection(volume)
                        }

                        // 11. Vocabulary Complexity
                        if let vocab = recording.analysis?.vocabComplexity {
                            vocabComplexitySection(vocab)
                        }

                        // 12. Sentence Structure
                        if let sentence = recording.analysis?.sentenceAnalysis {
                            sentenceAnalysisSection(sentence)
                        }

                        // 13. Coaching Tips
                        if let analysis = recording.analysis {
                            CoachingTipsView(tips: CoachingTipService.generateTips(from: analysis))
                        }

                        // 9. Share CTA
                        if recording.analysis != nil {
                            shareCTASection(recording)
                        }

                        // Actions
                        actionsSection(recording)
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .contentMargins(.horizontal, 0)
                .onAppear {
                    generateWaveformHeights()
                    initializePlayback(recording)
                }
                .task {
                    // Delay score animation
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation(.easeOut(duration: 0.8)) {
                        animateScore = true
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
                    }
                }
            }
        }
        .task {
            await loadRecording()
            await transcribeIfNeeded()
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
    }

    // MARK: - Hero Score Section

    @ViewBuilder
    private func heroScoreSection(_ analysis: SpeechAnalysis) -> some View {
        GlassCard {
            VStack(spacing: 16) {
                // Header row with score and trend
                HStack(alignment: .center) {
                    // Large score
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(animateScore ? analysis.speechScore.overall : 0)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.scoreColor(for: analysis.speechScore.overall))
                            .contentTransition(.numericText())
                        
                        Text("/100")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Trend badge
                    HStack(spacing: 4) {
                        Image(systemName: analysis.speechScore.trend.iconName)
                        Text(analysis.speechScore.trend.rawValue.capitalized)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(analysis.speechScore.trend.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(analysis.speechScore.trend.color.opacity(0.15))
                    }
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        
                        Capsule()
                            .fill(AppColors.scoreColor(for: analysis.speechScore.overall))
                            .frame(width: animateScore ? geometry.size.width * CGFloat(analysis.speechScore.overall) / 100 : 0)
                            .animation(.easeOut(duration: 0.8), value: animateScore)
                    }
                }
                .frame(height: 8)
            }
        }
    }

    // MARK: - Pause Analysis Section

    @ViewBuilder
    private func pauseAnalysisSection(_ analysis: SpeechAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pause Analysis")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Strategic Pauses")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Text("\(analysis.strategicPauseCount)")
                                    .font(.title3.weight(.semibold))
                                Text("for emphasis")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Hesitations")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Text("\(analysis.hesitationPauseCount)")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(analysis.hesitationPauseCount > 3 ? .orange : .primary)
                                Text("mid-sentence")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    if analysis.averagePauseLength > 0 {
                        HStack {
                            Text("Average pause")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f seconds", analysis.averagePauseLength))
                                .font(.caption.weight(.medium))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Prompt Header

    @ViewBuilder
    private func promptHeader(_ recording: Recording) -> some View {
        GlassCard {
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

                    Text(recording.date.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        GlassCard {
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
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
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
    }

    // MARK: - Subscores Section

    @ViewBuilder
    private func subscoresSection(_ analysis: SpeechAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score Breakdown")
                .font(.headline)

            GlassCard {
                VStack(spacing: 16) {
                    // Core scores
                    SubscoreRow(title: "Clarity", score: analysis.speechScore.subscores.clarity, icon: "waveform")
                    SubscoreRow(title: "Pace", score: analysis.speechScore.subscores.pace, icon: "speedometer")
                    SubscoreRow(title: "Filler Usage", score: analysis.speechScore.subscores.fillerUsage, icon: "text.badge.minus")
                    SubscoreRow(title: "Pauses", score: analysis.speechScore.subscores.pauseQuality, icon: "pause.circle")
                    
                    // Extended scores (if available)
                    if let delivery = analysis.speechScore.subscores.delivery {
                        SubscoreRow(title: "Delivery", score: delivery, icon: "speaker.wave.3")
                    }
                    if let vocabulary = analysis.speechScore.subscores.vocabulary {
                        SubscoreRow(title: "Vocabulary", score: vocabulary, icon: "textformat.abc")
                    }
                    if let structure = analysis.speechScore.subscores.structure {
                        SubscoreRow(title: "Structure", score: structure, icon: "list.bullet.indent")
                    }
                    if let relevance = analysis.speechScore.subscores.relevance {
                        let isRelevanceScore = analysis.promptRelevanceScore != nil && recording?.prompt != nil
                        SubscoreRow(
                            title: isRelevanceScore ? "Relevance" : "Coherence",
                            score: relevance,
                            icon: isRelevanceScore ? "target" : "arrow.triangle.branch"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Processing Section

    private var processingSection: some View {
        GlassCard(tint: .blue.opacity(0.1)) {
            HStack(spacing: 12) {
                ProgressView()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Analyzing Speech...")
                        .font(.subheadline.weight(.medium))

                    Text("Transcribing and detecting filler words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var modelLoadingSection: some View {
        GlassCard(tint: .orange.opacity(0.1)) {
            HStack(spacing: 12) {
                ProgressView()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading Speech Model...")
                        .font(.subheadline.weight(.medium))

                    Text("The analysis model is loading in the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private func statsGrid(_ analysis: SpeechAnalysis) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatGridItem(
                label: "Speaking Pace",
                value: "\(Int(analysis.wordsPerMinute)) wpm",
                icon: "speedometer",
                color: .cyan
            )
            
            StatGridItem(
                label: "Total Words",
                value: "\(analysis.totalWords)",
                icon: "text.word.spacing",
                color: .white
            )
            
            StatGridItem(
                label: "Filler Words",
                value: "\(analysis.totalFillerCount)",
                icon: "exclamationmark.bubble",
                color: analysis.totalFillerCount > 5 ? .orange : .green
            )
            
            StatGridItem(
                label: "Pauses",
                value: "\(analysis.pauseCount)",
                icon: "pause.circle",
                color: .green
            )
        }
    }

    // MARK: - Filler Words Section

    @ViewBuilder
    private func fillerWordsSection(_ fillerWords: [FillerWord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filler Words Used")
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
                        showVocabHighlights: showVocabHighlights
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

    // MARK: - Volume Section

    @ViewBuilder
    private func volumeSection(_ volume: VolumeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volume & Energy")
                .font(.headline)

            GlassCard {
                VStack(spacing: 16) {
                    SubscoreRow(title: "Energy Level", score: volume.energyScore, icon: "bolt.fill")
                    SubscoreRow(title: "Vocal Variety", score: volume.monotoneScore, icon: "waveform.path.ecg")
                }
            }
        }
    }

    // MARK: - Vocab Complexity Section

    @ViewBuilder
    private func vocabComplexitySection(_ vocab: VocabComplexity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vocabulary")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    SubscoreRow(title: "Complexity", score: vocab.complexityScore, icon: "textformat.abc")

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unique words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(vocab.uniqueWordCount) (\(Int(vocab.uniqueWordRatio * 100))%)")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Avg word length")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f chars", vocab.averageWordLength))
                                .font(.subheadline.weight(.medium))
                        }
                    }

                    if !vocab.repeatedPhrases.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Repeated phrases")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(vocab.repeatedPhrases.prefix(3), id: \.phrase) { phrase in
                                HStack {
                                    Text("\"\(phrase.phrase)\"")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(phrase.count)×")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sentence Analysis Section

    @ViewBuilder
    private func sentenceAnalysisSection(_ sentence: SentenceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sentence Structure")
                .font(.headline)

            GlassCard {
                VStack(spacing: 14) {
                    SubscoreRow(title: "Structure Score", score: sentence.structureScore, icon: "text.alignleft")

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sentences")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(sentence.totalSentences)")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        VStack(alignment: .center, spacing: 2) {
                            Text("Restarts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(sentence.restartCount)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(sentence.restartCount > 3 ? .orange : .primary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Incomplete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(sentence.incompleteSentences)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(sentence.incompleteSentences > 2 ? .orange : .primary)
                        }
                    }

                    if !sentence.restartExamples.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Example restarts")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(sentence.restartExamples.prefix(2), id: \.self) { example in
                                Text("\"\(example)\"")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func generateWaveformHeights() {
        guard waveformHeights.isEmpty else { return }
        if let url = recording?.audioURL ?? recording?.videoURL {
            waveformHeights = AudioWaveformGenerator.generate(from: url, binCount: 50)
        } else {
            waveformHeights = Array(repeating: CGFloat(20), count: 50)
        }
    }

    private func initializePlayback(_ recording: Recording) {
        guard let url = recording.audioURL ?? recording.videoURL else { return }
        if let duration = audioService.getAudioDuration(at: url) {
            audioService.playbackDuration = duration
        }
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
        } catch {
            print("Error loading recording: \(error)")
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
            return
        }

        isTranscribing = true
        recording.isProcessing = true

        defer {
            isTranscribing = false
            recording.isProcessing = false
        }

        try? await Task.sleep(for: .milliseconds(300))

        do {
            let result = try await speechService.transcribe(audioURL: audioURL)

            // Fetch settings for analysis configuration
            let settingsDescriptor = FetchDescriptor<UserSettings>()
            let settings = (try? modelContext.fetch(settingsDescriptor))?.first
            let vocabWords = settings?.vocabWords ?? []

            let analysis = speechService.analyze(
                transcription: result,
                actualDuration: recording.actualDuration,
                vocabWords: vocabWords,
                audioLevelSamples: recording.audioLevelSamples ?? [],
                prompt: recording.prompt,
                targetWPM: settings?.targetWPM ?? 150,
                trackFillerWords: settings?.trackFillerWords ?? true,
                trackPauses: settings?.trackPauses ?? true
            )

            recording.transcriptionText = result.text
            recording.transcriptionWords = speechService.markVocabWordsInTranscription(
                result.words, vocabWords: vocabWords
            )
            recording.analysis = analysis

            try modelContext.save()
        } catch {
            print("Transcription error: \(error)")
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
                try? await audioService.play(url: url)
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
            try? await audioService.play(url: url)
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

struct WordView: View {
    let word: TranscriptionWord
    let showFillerHighlight: Bool
    let showVocabHighlight: Bool

    private var isHighlighted: Bool { showFillerHighlight || showVocabHighlight }
    private var highlightColor: Color { showFillerHighlight ? .orange : .green }

    var body: some View {
        Text(word.word)
            .font(.body)
            .foregroundStyle(isHighlighted ? highlightColor : .primary)
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

#Preview {
    NavigationStack {
        RecordingDetailView(recordingId: UUID().uuidString)
    }
    .modelContainer(for: [Recording.self, Prompt.self], inMemory: true)
}
