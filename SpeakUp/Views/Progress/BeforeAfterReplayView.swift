import SwiftUI
import SwiftData

struct BeforeAfterReplayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioService.self) private var audioService
    @Query private var userSettings: [UserSettings]
    @State private var viewModel = ProgressReplayViewModel()
    /// The take that owns the player. Whether it is sounding right now is
    /// `audioService.isPlaying`: `AudioService.play` returns as soon as
    /// playback starts, so a flag reset after awaiting it flipped back at once
    /// and left no way to pause.
    @State private var activeSide: Side?

    private enum Side {
        case first, latest

        var name: String {
            switch self {
            case .first: return "first take"
            case .latest: return "latest take"
            }
        }
    }

    var body: some View {
        NavigationStack {
            PageScrollView {
                VStack(spacing: 20) {
                    if viewModel.isLoaded {
                        summaryLine

                        recordingCard(
                            title: "First take",
                            snapshot: viewModel.earliestSnapshot,
                            side: .first
                        )

                        changeMarker

                        recordingCard(
                            title: "Latest take",
                            snapshot: viewModel.latestSnapshot,
                            side: .latest
                        )

                        if let card = viewModel.progressCard {
                            shareSection(card)
                        }

                        if viewModel.scoreImprovement > 20 {
                            FeaturedGlassCard {
                                VStack(spacing: 8) {
                                    Image(systemName: "star.fill")
                                        .font(.title)
                                        .foregroundStyle(AppColors.warning)
                                        .accessibilityHidden(true)

                                    Text("Big progress")
                                        .font(.headline)

                                    Text("You've improved by \(viewModel.scoreImprovement) points since your first take.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "Not enough takes yet",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Listen back needs two analyzed takes to play side by side.")
                        )
                    }
                }
                .padding(.top, 8)
                .pageContentInsets()
            }
            .scrollIndicators(.hidden)
            .appBackground(.subtle)
            // Named like the Review tile that opens it; it used to be
            // "Your Progress" over an in-page "Then vs Now".
            .navigationTitle("Listen back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
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

    // MARK: - Summary

    private var summaryLine: some View {
        let change = viewModel.scoreImprovement

        return Text(
            change > 0 ? "Up \(change) points since your first take."
                : change < 0 ? "Down \(-change) points since your first take."
                : "Level with your first take."
        )
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(change > 0 ? AppColors.success : .secondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var changeMarker: some View {
        let change = viewModel.scoreImprovement

        return VStack(spacing: 4) {
            Image(systemName: "arrow.down")
                .font(.title2.weight(.bold))
                .foregroundStyle(.secondary)

            if change != 0 {
                Text(change > 0 ? "+\(change)" : "\(change)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    // A drop is amber, never red.
                    .foregroundStyle(change > 0 ? AppColors.success : AppColors.warning)
            }
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }

    // MARK: - Share

    /// The card carries scores, dates, and a session count - never a
    /// transcript, a prompt, or audio. Said out loud here so the user does not
    /// have to guess what they are about to post.
    private func shareSection(_ card: ProgressCardData) -> some View {
        GlassCard(tint: AppColors.glassTintPrimary) {
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Share your progress")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Scores and dates only, no transcript, prompt, or audio leaves your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                GlassButton(title: "Share card", icon: "square.and.arrow.up", style: .secondary, size: .small) {
                    Haptics.medium()
                    ProgressCardRenderer.share(card, trigger: "then_vs_now") {
                        if ReviewRequestService.shared.requestIfEligible(
                            .shareCompleted,
                            settings: userSettings.first
                        ) {
                            try? modelContext.save()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Take Card

    private func recordingCard(title: String, snapshot: ReplaySessionSnapshot?, side: Side) -> some View {
        let isPlaying = activeSide == side && audioService.isPlaying

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle(title)

                if let snapshot {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let score = snapshot.score {
                                HStack(spacing: 4) {
                                    Text("\(score)")
                                        .font(.title2.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(AppColors.scoreColor(for: score))
                                    Text("/100")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Spacer()

                        Button {
                            togglePlayback(side)
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(AppColors.primary)
                                .frame(minWidth: AppLayout.minHitTarget, minHeight: AppLayout.minHitTarget)
                                .contentShape(.rect)
                        }
                        .buttonStyle(GlassPressStyle())
                        .accessibilityLabel(isPlaying ? "Pause \(side.name)" : "Play \(side.name)")
                    }

                    HStack(spacing: 16) {
                        statItem(label: "WPM", value: "\(Int(snapshot.wpm))")
                        statItem(label: "Fillers", value: "\(snapshot.fillerCount)")
                        statItem(label: "Words", value: "\(snapshot.wordCount)")
                    }
                }
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Playback

    /// Play, pause, or resume one side. The other side stops first, so the
    /// two takes never talk over each other.
    private func togglePlayback(_ side: Side) {
        let recording = side == .first ? viewModel.earliestRecording : viewModel.latestRecording
        guard let url = recording?.resolvedAudioURL ?? recording?.resolvedVideoURL else { return }
        Haptics.light()

        if activeSide == side, audioService.isPlaying {
            audioService.pause()
            return
        }

        // Resume where this side paused (0 once it has finished); the other
        // side always starts from the top.
        let resumeAt = activeSide == side ? audioService.currentPlaybackTime : 0
        if activeSide != side {
            audioService.stop()
        }
        activeSide = side

        Task {
            try? await audioService.play(url: url, startingAt: resumeAt)
        }
    }
}
