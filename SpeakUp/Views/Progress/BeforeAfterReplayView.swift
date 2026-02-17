import SwiftUI
import SwiftData

struct BeforeAfterReplayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioService.self) private var audioService
    @State private var viewModel = ProgressReplayViewModel()
    @State private var playingEarly = false
    @State private var playingLatest = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        if viewModel.isLoaded {
                            // Header
                            VStack(spacing: 8) {
                                Text("Then vs Now")
                                    .font(.title.weight(.bold))

                                if viewModel.scoreImprovement > 0 {
                                    Text("+\(viewModel.scoreImprovement) points improvement!")
                                        .font(.headline)
                                        .foregroundStyle(.green)
                                } else if viewModel.scoreImprovement < 0 {
                                    Text("Keep practicing — you've got this!")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top)

                            // Early recording card
                            recordingCard(
                                title: "Your First Session",
                                recording: viewModel.earliestRecording,
                                isPlaying: playingEarly,
                                onPlay: { playEarly() }
                            )

                            // Arrow indicator
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.teal)

                                if viewModel.scoreImprovement != 0 {
                                    Text(viewModel.scoreImprovement >= 0 ? "+\(viewModel.scoreImprovement)" : "\(viewModel.scoreImprovement)")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(viewModel.scoreImprovement >= 0 ? .green : .red)
                                }
                            }
                            .padding(.vertical, 4)

                            // Latest recording card
                            recordingCard(
                                title: "Your Latest Session",
                                recording: viewModel.latestRecording,
                                isPlaying: playingLatest,
                                onPlay: { playLatest() }
                            )

                            // Motivational message
                            if viewModel.scoreImprovement > 20 {
                                FeaturedGlassCard(gradientColors: [.green.opacity(0.15), .teal.opacity(0.08)]) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "star.fill")
                                            .font(.title)
                                            .foregroundStyle(.yellow)

                                        Text("Amazing Progress!")
                                            .font(.headline)

                                        Text("You've improved by \(viewModel.scoreImprovement) points. That's incredible growth!")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                            }
                        } else {
                            ContentUnavailableView(
                                "Not Enough Data",
                                systemImage: "chart.line.uptrend.xyaxis",
                                description: Text("You need at least 2 analyzed recordings to compare progress.")
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Your Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                viewModel.loadRecordings(context: modelContext)
            }
            .onDisappear {
                audioService.stop()
            }
        }
    }

    private func recordingCard(title: String, recording: Recording?, isPlaying: Bool, onPlay: @escaping () -> Void) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.teal)

                if let recording {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let score = recording.analysis?.speechScore.overall {
                                HStack(spacing: 4) {
                                    Text("\(score)")
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(AppColors.scoreColor(for: score))
                                    Text("/100")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Spacer()

                        Button(action: onPlay) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.teal)
                        }
                        .buttonStyle(.plain)
                    }

                    // Stats row
                    if let analysis = recording.analysis {
                        HStack(spacing: 16) {
                            statItem(label: "WPM", value: "\(Int(analysis.wordsPerMinute))")
                            statItem(label: "Fillers", value: "\(analysis.totalFillerCount)")
                            statItem(label: "Words", value: "\(analysis.totalWords)")
                        }
                    }
                }
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func playEarly() {
        guard let url = viewModel.earliestRecording?.audioURL ?? viewModel.earliestRecording?.videoURL else { return }
        audioService.stop()
        playingLatest = false
        playingEarly = true
        Task {
            try? await audioService.play(url: url)
            playingEarly = false
        }
    }

    private func playLatest() {
        guard let url = viewModel.latestRecording?.audioURL ?? viewModel.latestRecording?.videoURL else { return }
        audioService.stop()
        playingEarly = false
        playingLatest = true
        Task {
            try? await audioService.play(url: url)
            playingLatest = false
        }
    }
}
