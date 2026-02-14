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

    // Services
    @Environment(AudioService.self) private var audioService
    @Environment(SpeechService.self) private var speechService

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground(style: .subtle)

            if let recording {
                ScrollView {
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

                        // 7. Detailed Scores
                        if let analysis = recording.analysis {
                            subscoresSection(analysis)
                        }

                        // 8. Coaching Tips
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
                .onAppear {
                    generateWaveformHeights()
                    initializePlayback(recording)
                    // Delay score animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if let recording {
                            scoreCardImage = ScoreCardRenderer.render(recording: recording)
                        }
                        showingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

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
                let exportService = ExportService()
                exportService.shareRecording(recording, scoreCardImage: scoreCardImage)
                showingShareSheet = false
            }
        }
    }

    // MARK: - Hero Score Section

    @ViewBuilder
    private func heroScoreSection(_ analysis: SpeechAnalysis) -> some View {
        FeaturedGlassCard(
            gradientColors: [
                AppColors.scoreColor(for: analysis.speechScore.overall).opacity(0.12),
                AppColors.scoreColor(for: analysis.speechScore.overall).opacity(0.04)
            ],
            cornerRadius: 24
        ) {
            VStack(spacing: 16) {
                // Score label + trend
                HStack {
                    Text("Speech Score")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: analysis.speechScore.trend.iconName)
                        Text(analysis.speechScore.trend.rawValue.capitalized)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(analysis.speechScore.trend.color)
                }

                // Large animated score
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(animateScore ? analysis.speechScore.overall : 0)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.scoreColor(for: analysis.speechScore.overall))
                        .contentTransition(.numericText())

                    Text("/100")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                // Score bar with gradient
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.15))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppColors.scoreColor(for: analysis.speechScore.overall).opacity(0.7),
                                        AppColors.scoreColor(for: analysis.speechScore.overall)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: animateScore ? geometry.size.width * CGFloat(analysis.speechScore.overall) / 100 : 0)
                            .animation(.easeOut(duration: 1.0), value: animateScore)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())

                // Quick subscore summary
                HStack(spacing: 0) {
                    MiniSubscore(
                        label: "Clarity",
                        score: analysis.speechScore.subscores.clarity,
                        icon: "waveform"
                    )
                    MiniSubscore(
                        label: "Pace",
                        score: analysis.speechScore.subscores.pace,
                        icon: "speedometer"
                    )
                    MiniSubscore(
                        label: "Fillers",
                        score: analysis.speechScore.subscores.fillerUsage,
                        icon: "text.badge.minus"
                    )
                    MiniSubscore(
                        label: "Pauses",
                        score: analysis.speechScore.subscores.pauseQuality,
                        icon: "pause.circle"
                    )
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
        VStack(alignment: .leading, spacing: 8) {
            Label("Playback", systemImage: "play.circle.fill")
                .font(.headline)

            GlassCard(padding: 16) {
                VStack(spacing: 16) {
                    // Waveform
                    HStack(spacing: 8) {
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
                                    let height: CGFloat = waveformHeights.isEmpty ? 20 : waveformHeights[i % waveformHeights.count]

                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(isPlayed ? Color.teal : Color.teal.opacity(0.25))
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
                        .frame(height: 36)

                        Text(formatTime(audioService.playbackDuration > 0 ? audioService.playbackDuration : recording.actualDuration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }

                    // Play button
                    Button {
                        togglePlayback(recording)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.teal.opacity(0.9), .teal],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                                .shadow(color: .teal.opacity(0.3), radius: 8, y: 2)

                            Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Subscores Section

    @ViewBuilder
    private func subscoresSection(_ analysis: SpeechAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Detailed Scores", systemImage: "chart.bar.fill")
                .font(.headline)

            GlassCard {
                VStack(spacing: 0) {
                    SubscoreRow(
                        title: "Clarity",
                        score: analysis.speechScore.subscores.clarity,
                        icon: "waveform"
                    )

                    Divider()
                        .padding(.vertical, 8)

                    SubscoreRow(
                        title: "Pace",
                        score: analysis.speechScore.subscores.pace,
                        icon: "speedometer"
                    )

                    Divider()
                        .padding(.vertical, 8)

                    SubscoreRow(
                        title: "Filler Usage",
                        score: analysis.speechScore.subscores.fillerUsage,
                        icon: "text.badge.minus"
                    )

                    Divider()
                        .padding(.vertical, 8)

                    SubscoreRow(
                        title: "Pauses",
                        score: analysis.speechScore.subscores.pauseQuality,
                        icon: "pause.circle"
                    )
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
        GlassCard(padding: 12) {
            HStack(spacing: 0) {
                CompactStatItem(
                    icon: "speedometer",
                    value: "\(Int(analysis.wordsPerMinute))",
                    label: "WPM",
                    color: .blue
                )

                Divider().frame(height: 36)

                CompactStatItem(
                    icon: "text.word.spacing",
                    value: "\(analysis.totalWords)",
                    label: "Words",
                    color: .green
                )

                Divider().frame(height: 36)

                CompactStatItem(
                    icon: "exclamationmark.bubble",
                    value: "\(analysis.totalFillerCount)",
                    label: "Fillers",
                    color: .orange
                )

                Divider().frame(height: 36)

                CompactStatItem(
                    icon: "pause.circle",
                    value: "\(analysis.pauseCount)",
                    label: "Pauses",
                    color: .purple
                )
            }
        }
    }

    // MARK: - Filler Words Section

    @ViewBuilder
    private func fillerWordsSection(_ fillerWords: [FillerWord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Filler Words", systemImage: "exclamationmark.bubble.fill")
                .font(.headline)

            GlassCard(tint: .orange.opacity(0.05)) {
                VStack(spacing: 0) {
                    ForEach(Array(fillerWords.prefix(5).enumerated()), id: \.element.id) { index, filler in
                        HStack {
                            Text("\"\(filler.word)\"")
                                .font(.subheadline.weight(.medium))

                            Spacer()

                            Text("\(filler.count)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 28, minHeight: 28)
                                .background {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.orange, .orange.opacity(0.8)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                        }
                        .padding(.vertical, 8)

                        if index < fillerWords.prefix(5).count - 1 {
                            Divider()
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
        FeaturedGlassCard(
            gradientColors: [.teal.opacity(0.1), .cyan.opacity(0.05)]
        ) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share Your Score")
                        .font(.subheadline.weight(.semibold))

                    Text("Show friends your speaking progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    scoreCardImage = ScoreCardRenderer.render(recording: recording)
                    showingShareSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                        Text("Share")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.teal.opacity(0.9), .teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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

            // Fetch vocab words from settings
            let settingsDescriptor = FetchDescriptor<UserSettings>()
            let vocabWords = (try? modelContext.fetch(settingsDescriptor))?.first?.vocabWords ?? []

            let analysis = speechService.analyze(
                transcription: result,
                actualDuration: recording.actualDuration,
                vocabWords: vocabWords
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
            Task {
                try? await audioService.play(url: url)
            }
        }
    }

    private func toggleFavorite(_ recording: Recording) {
        recording.isFavorite.toggle()
        try? modelContext.save()
    }

    private func deleteRecording() {
        guard let recording else { return }

        if let audioURL = recording.audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        if let videoURL = recording.videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }

        modelContext.delete(recording)
        try? modelContext.save()

        dismiss()
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Mini Subscore (for hero card)

private struct MiniSubscore: View {
    let label: String
    let score: Int
    let icon: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(AppColors.scoreColor(for: score))

            Text("\(score)")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.scoreColor(for: score))

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Subscore Card

struct SubscoreCard: View {
    let title: String
    let score: Int
    let icon: String

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(AppColors.scoreColor(for: score))

                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("\(score)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColors.scoreColor(for: score))

                    Text("/100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppColors.scoreColor(for: score))
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            // Mini progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.15))

                    Capsule()
                        .fill(AppColors.scoreColor(for: score).opacity(0.8))
                        .frame(width: geometry.size.width * CGFloat(score) / 100)
                }
            }
            .frame(width: 60, height: 4)
            .clipShape(Capsule())

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(score)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.scoreColor(for: score))

                Text("/100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 65, alignment: .trailing)
        }
    }
}

// MARK: - Compact Stat Item

struct CompactStatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
