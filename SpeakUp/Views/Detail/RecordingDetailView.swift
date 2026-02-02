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

    // Services
    @State private var audioService = AudioService()
    @State private var speechService = SpeechService()
    
    var body: some View {
        ScrollView {
            if let recording {
                VStack(spacing: 20) {
                    // Media Player
                    mediaPlayerSection(recording)

                    // Score Card
                    if let analysis = recording.analysis {
                        ScoreDisplayCard(
                            score: analysis.speechScore.overall,
                            trend: analysis.speechScore.trend
                        )
                    } else if recording.isProcessing || isTranscribing {
                        processingSection
                    }

                    // Stats Grid (reordered: Words/Min, Total Words, Filler Words, Pauses)
                    if let analysis = recording.analysis {
                        statsGrid(analysis)
                    }

                    // Filler Words (moved up)
                    if let analysis = recording.analysis, !analysis.fillerWords.isEmpty {
                        fillerWordsSection(analysis.fillerWords)
                    }

                    // Transcript (moved up)
                    if let words = recording.transcriptionWords, !words.isEmpty {
                        transcriptSectionWithHighlights(words)
                    } else if let text = recording.transcriptionText, !text.isEmpty {
                        transcriptSection(text)
                    }

                    // Subscores (moved to bottom)
                    if let analysis = recording.analysis {
                        subscoresSection(analysis)
                    }

                    // Actions
                    actionsSection(recording)
                }
                .padding()
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
        .navigationTitle(recording?.date.relativeFormatted ?? "Recording")
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
    
    // MARK: - Media Player Section
    
    @ViewBuilder
    private func mediaPlayerSection(_ recording: Recording) -> some View {
        GlassCard {
            VStack(spacing: 16) {
                if recording.mediaType == .video, let videoURL = recording.videoURL {
                    VideoPlayer(player: AVPlayer(url: videoURL))
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // Audio player visualization
                    audioPlayerView(recording)
                }
                
                // Recording info
                HStack {
                    Label(recording.prompt?.category ?? "Practice Session", systemImage: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: recording.mediaType.iconName)
                        Text(recording.formattedDuration)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private func audioPlayerView(_ recording: Recording) -> some View {
        VStack(spacing: 16) {
            // Waveform placeholder
            HStack(spacing: 2) {
                ForEach(0..<40, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.teal.opacity(Double.random(in: 0.3...1.0)))
                        .frame(width: 4, height: CGFloat.random(in: 20...60))
                }
            }
            .frame(height: 80)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                    
                    Capsule()
                        .fill(Color.teal)
                        .frame(width: geometry.size.width * audioService.playbackProgress)
                }
            }
            .frame(height: 4)
            
            // Controls
            HStack {
                Text(formatTime(audioService.playbackProgress * audioService.playbackDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    togglePlayback(recording)
                } label: {
                    Image(systemName: audioService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.teal)
                }
                
                Spacer()
                
                Text(formatTime(audioService.playbackDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
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
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                title: "Words/Min",
                value: "\(Int(analysis.wordsPerMinute))",
                icon: "speedometer",
                tint: .blue
            )
            
            StatCard(
                title: "Total Words",
                value: "\(analysis.totalWords)",
                icon: "text.word.spacing",
                tint: .green
            )
            
            StatCard(
                title: "Filler Words",
                value: "\(analysis.totalFillerCount)",
                icon: "exclamationmark.bubble",
                tint: .orange
            )
            
            StatCard(
                title: "Pauses",
                value: "\(analysis.pauseCount)",
                icon: "pause.circle",
                tint: .purple
            )
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
