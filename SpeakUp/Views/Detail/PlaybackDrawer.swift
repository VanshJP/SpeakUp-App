import SwiftUI


// MARK: - Playback Drawer Container

struct PlaybackDrawerContainer: View {
    let recording: Recording
    let waveformHeights: [CGFloat]
    let playbackViewModel: RecordingDetailPlaybackViewModel
    let onTogglePlayback: () -> Void
    let onSeek: (Double) -> Void

    @Environment(AudioService.self) private var audioService

    @State private var drawerState: PlaybackDrawerState = .collapsed
    @State private var dragOffset: CGFloat = 0

    private let drawerSpring: Animation = .spring(response: 0.26, dampingFraction: 0.90)
    private let collapseDistance: CGFloat = 50      // drag-to-close threshold
    private let expandDistance: CGFloat = 40        // drag-to-open threshold
    private let flickVelocity: CGFloat = 320        // points/sec to snap on a flick
    private let rubberBandLimit: CGFloat = 56       // resistance sets in past this
    private let rubberBandFactor: CGFloat = 0.32    // smaller = stiffer past limit

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    withAnimation(drawerSpring) {
                        drawerState = drawerState == .expanded ? .collapsed : .expanded
                    }
                } label: {
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
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    let translation = value.translation.height
                    guard abs(translation) > abs(value.translation.width) else { return }
                    switch drawerState {
                    case .expanded:
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
        time.minutesSeconds
    }
}

struct ScrubberBars: View {
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


enum PlaybackDrawerState {
    case expanded
    case collapsed
}
