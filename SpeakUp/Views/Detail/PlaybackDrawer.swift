import SwiftUI

// Extracted from RecordingDetailView, which had grown to 2302 lines by
// carrying results presentation, drag physics, transcript rendering, and
// markdown parsing in one file. These types were already independent —
// only their `private` scope tied them to that file.

// MARK: - Playback Drawer Container

struct PlaybackDrawerContainer: View {
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
