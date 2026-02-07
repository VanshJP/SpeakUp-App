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
    @State private var waveformHeights: [CGFloat] = []

    // Services
    @State private var audioService = AudioService()
    @State private var speechService = SpeechService()
    
    var body: some View {
        ZStack(alignment: .top) {
            if let recording {
                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Prompt Header
                        promptHeader(recording)

                        // 2. Score Card
                        if let analysis = recording.analysis {
                            ScoreDisplayCard(
                                score: analysis.speechScore.overall,
                                trend: analysis.speechScore.trend
                            )
                        } else if recording.isProcessing || isTranscribing {
                            processingSection
                        }

                        // 3. Stats Grid
                        if let analysis = recording.analysis {
                            statsGrid(analysis)
                        }

                        // 4. Playback Control (directly above transcript)
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

                        // Actions
                        actionsSection(recording)
                    }
                    .padding()
                }
                .onAppear {
                    generateWaveformHeights()
                    initializePlayback(recording)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    
                    if let recording {
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
    }
    
    // MARK: - Prompt Header (Scrollable)

    @ViewBuilder
    private func promptHeader(_ recording: Recording) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                // Category & Date row
                HStack {
                    if let prompt = recording.prompt {
                        Label(prompt.category, systemImage: PromptCategory(rawValue: prompt.category)?.iconName ?? "text.bubble")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.teal)
                    }

                    Spacer()

                    Text(recording.date.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Prompt text
                if let prompt = recording.prompt {
                    Text(prompt.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                } else {
                    Text("Practice Session")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }

                // Duration & difficulty
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(recording.formattedDuration)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let difficulty = recording.prompt?.difficulty {
                        Text(difficulty.displayName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                Capsule()
                                    .fill(AppColors.difficultyColor(difficulty).opacity(0.2))
                            }
                            .foregroundStyle(AppColors.difficultyColor(difficulty))
                    }
                }
            }
        }
    }

    // MARK: - Playback Control Section

    @ViewBuilder
    private func playbackControlSection(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playback")
                .font(.headline)

            GlassCard(padding: 16) {
                VStack(spacing: 16) {
                    // Waveform row: Start time - Waveform - End time
                    HStack(spacing: 8) {
                        // Start time
                        Text(formatTime(audioService.playbackProgress * audioService.playbackDuration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .leading)

                        // Waveform visualization
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
                                        .fill(isPlayed ? Color.teal : Color.teal.opacity(0.3))
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

                        // End time
                        Text(formatTime(audioService.playbackDuration > 0 ? audioService.playbackDuration : recording.actualDuration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }

                    // Play/Pause button centered
                    Button {
                        togglePlayback(recording)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.teal)
                                .frame(width: 52, height: 52)

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
            Text("Detailed Scores")
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
            Text("Filler Words")
                .font(.headline)

            GlassCard(tint: .orange.opacity(0.1)) {
                VStack(spacing: 0) {
                    ForEach(Array(fillerWords.prefix(5).enumerated()), id: \.element.id) { index, filler in
                        HStack {
                            Text("\"\(filler.word)\"")
                                .font(.subheadline.weight(.medium))

                            Spacer()

                            Text("\(filler.count)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 24, minHeight: 24)
                                .background(Circle().fill(.orange))
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
            Text("Transcript")
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
                Text("Transcript")
                    .font(.headline)

                Spacer()

                Button {
                    showFillerHighlights.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showFillerHighlights ? "eye.fill" : "eye.slash")
                        Text("Fillers")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(showFillerHighlights ? .orange : .secondary)
                }
            }

            GlassCard {
                HighlightedTranscriptView(
                    words: words,
                    showHighlights: showFillerHighlights
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
    
    // MARK: - Actions Section
    
    @ViewBuilder
    private func actionsSection(_ recording: Recording) -> some View {
        VStack(spacing: 12) {
            GlassButton(
                title: "Share Recording",
                icon: "square.and.arrow.up",
                style: .primary,
                fullWidth: true
            ) {
                showingShareSheet = true
            }
            
            GlassButton(
                title: "Delete",
                icon: "trash",
                style: .danger,
                fullWidth: true
            ) {
                showingDeleteAlert = true
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Helpers

    private func generateWaveformHeights() {
        guard waveformHeights.isEmpty else { return }
        waveformHeights = (0..<50).map { _ in CGFloat.random(in: 12...36) }
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

        // Verify the file exists and is accessible
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("Audio file does not exist at: \(audioURL.path)")
            return
        }

        isTranscribing = true
        recording.isProcessing = true

        defer {
            isTranscribing = false
            recording.isProcessing = false
        }

        // Small delay to ensure file is fully written
        try? await Task.sleep(for: .milliseconds(300))

        do {
            // Transcribe
            let result = try await speechService.transcribe(audioURL: audioURL)
            
            // Analyze
            let analysis = speechService.analyze(
                transcription: result,
                actualDuration: recording.actualDuration
            )
            
            // Update recording
            recording.transcriptionText = result.text
            recording.transcriptionWords = result.words
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
        
        // Delete files
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

// MARK: - Subscore Row (for unified card layout)

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

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(score)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.scoreColor(for: score))

                Text("/100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Compact Stat Item (horizontal row style)

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
    let showHighlights: Bool

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(words) { word in
                WordView(word: word, showHighlight: showHighlights && word.isFiller)
            }
        }
    }
}

struct WordView: View {
    let word: TranscriptionWord
    let showHighlight: Bool

    var body: some View {
        Text(word.word)
            .font(.body)
            .foregroundStyle(showHighlight ? .orange : .primary)
            .padding(.horizontal, showHighlight ? 4 : 0)
            .padding(.vertical, showHighlight ? 2 : 0)
            .background {
                if showHighlight {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(0.2))
                }
            }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
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

            // If this word doesn't fit on current line, move to next line
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
