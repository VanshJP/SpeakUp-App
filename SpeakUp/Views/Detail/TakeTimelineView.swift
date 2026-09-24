import SwiftUI

// MARK: - Take Timeline

/// A take drawn as a hypnogram: every moment between the first word and the
/// last sits in exactly one lane - speaking, pausing, or a filler - so the
/// shape of the take reads at a glance. The stats grid above says *how many*
/// pauses and fillers; this says *where*.
///
/// Pure and `nonisolated` so it builds from cached words and tests without a
/// container. Gaps between words shorter than `pauseGap` fold into the
/// surrounding run, which keeps the lanes contiguous.
nonisolated struct TakeTimeline: Equatable {
    enum Lane: CaseIterable, Equatable {
        case speaking, pause, filler

        var title: String {
            switch self {
            case .speaking: "Speaking"
            case .pause: "Pause"
            case .filler: "Filler"
            }
        }
    }

    enum Kind: Equatable {
        case speaking, pause, longPause, filler

        var lane: Lane {
            switch self {
            case .speaking: .speaking
            case .pause, .longPause: .pause
            case .filler: .filler
            }
        }
    }

    struct Segment: Equatable {
        let kind: Kind
        let start: TimeInterval
        var end: TimeInterval
    }

    // ponytail: mirrors the inline pause detection in `SpeechService.analyze`
    // so the picture agrees with the Pauses count. Lift both into one constant
    // if either threshold ever moves.
    static let pauseGap: TimeInterval = 0.4
    static let hesitationGap: TimeInterval = 1.2

    let segments: [Segment]
    let duration: TimeInterval
    let lanes: [Lane]

    init(
        words: [TranscriptionWord],
        duration: TimeInterval,
        showsPauses: Bool = true,
        showsFillers: Bool = true
    ) {
        var segments: [Segment] = []
        var previous: TranscriptionWord?

        for word in words.sorted(by: { $0.start < $1.start }) {
            // Another speaker's words are neither this take's speech nor its
            // silence: leave the time blank and do not call the gap a pause.
            guard word.isPrimarySpeaker, word.start.isFinite, word.end.isFinite else {
                previous = nil
                continue
            }
            let kind: Kind = showsFillers && word.isFiller ? .filler : .speaking

            if let previous {
                let gap = word.start - previous.end
                if gap > Self.pauseGap {
                    if showsPauses {
                        let midSentence = !Self.endsThought(previous.word)
                        segments.append(Segment(
                            kind: midSentence && gap > Self.hesitationGap ? .longPause : .pause,
                            start: previous.end,
                            end: word.start
                        ))
                    }
                } else if !segments.isEmpty {
                    segments[segments.count - 1].end = max(segments[segments.count - 1].end, word.start)
                }
            }

            if let last = segments.last, last.kind == kind, last.end >= word.start {
                segments[segments.count - 1].end = max(last.end, word.end)
            } else {
                segments.append(Segment(kind: kind, start: word.start, end: max(word.start, word.end)))
            }
            previous = word
        }

        self.segments = segments
        self.duration = max(duration, segments.last?.end ?? 0)
        self.lanes = Lane.allCases.filter {
            switch $0 {
            case .speaking: true
            case .pause: showsPauses
            case .filler: showsFillers
            }
        }
    }

    /// Same rule `SpeechService` uses to call a pause a transition.
    static func endsThought(_ word: String) -> Bool {
        word.hasSuffix(".") || word.hasSuffix("?") || word.hasSuffix("!")
    }

    // MARK: Reading

    /// Where a tap at `time` should start playback: a beat before the moment
    /// it landed on, so the listener hears the lead-in, not the middle of it.
    func seekTime(at time: TimeInterval) -> TimeInterval {
        let anchor = segments.first { $0.start <= time && time <= $0.end }?.start ?? time
        return max(0, anchor - 0.5)
    }

    var longPauseCount: Int { segments.filter { $0.kind == .longPause }.count }

    /// Share of the take spent talking, fillers included.
    var talkShare: Double {
        guard duration > 0 else { return 0 }
        let talking = segments
            .filter { $0.kind.lane != .pause }
            .reduce(0) { $0 + ($1.end - $1.start) }
        return min(1, talking / duration)
    }

    /// The moments worth jumping to from VoiceOver: fillers and long pauses.
    var landmarks: [Segment] {
        Array(segments.filter { $0.kind == .filler || $0.kind == .longPause }.prefix(10))
    }
}

// MARK: - View

/// Lanes on the left, the take in one `Canvas`, a playhead that follows the
/// drawer's playback, and a tap anywhere to listen from there. Seeks route
/// through the host's `playFrom` so the first-listen gate still applies.
struct TakeTimelineView: View {
    let timeline: TakeTimeline
    let playback: RecordingDetailPlaybackViewModel
    let onSeek: (TimeInterval) -> Void

    @ScaledMetric(relativeTo: .caption2) private var laneHeight: CGFloat = 26
    @State private var canvasWidth: CGFloat = 0

    var body: some View {
        let playhead: TimeInterval? = playback.isPlaying || playback.currentTime > 0
            ? playback.currentTime
            : nil

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(timeline.lanes, id: \.self) { lane in
                        Text(lane.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(height: laneHeight)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(spacing: 6) {
                    Canvas { context, size in
                        draw(in: &context, size: size, playhead: playhead)
                    }
                    .frame(height: laneHeight * CGFloat(timeline.lanes.count))
                    .contentShape(Rectangle())
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { canvasWidth = $0 }
                    .onTapGesture { location in
                        guard canvasWidth > 0 else { return }
                        onSeek(timeline.seekTime(at: Double(location.x / canvasWidth) * timeline.duration))
                    }

                    HStack {
                        Text("0:00")
                        Spacer()
                        Text(Duration.seconds(timeline.duration).formatted(.time(pattern: .minuteSecond)))
                    }
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    longPauseKey
                    Spacer(minLength: 12)
                    tapHint
                }
                VStack(alignment: .leading, spacing: 4) {
                    longPauseKey
                    tapHint
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Take timeline")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Plays the take from the start")
        .accessibilityAction { onSeek(0) }
        .accessibilityActions {
            ForEach(Array(timeline.landmarks.enumerated()), id: \.offset) { index, segment in
                Button(segment.kind == .filler ? "Play filler \(index + 1)" : "Play long pause \(index + 1)") {
                    onSeek(timeline.seekTime(at: segment.start))
                }
            }
        }
    }

    @ViewBuilder
    private var longPauseKey: some View {
        if timeline.longPauseCount > 0 {
            HStack(spacing: 6) {
                Circle()
                    .fill(color(for: .longPause))
                    .frame(width: 6, height: 6)
                Text("Long pause mid-sentence")
            }
        }
    }

    private var tapHint: some View {
        Text("Tap to listen")
            .foregroundStyle(.tertiary)
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, playhead: TimeInterval?) {
        let lanes = timeline.lanes
        guard timeline.duration > 0, !lanes.isEmpty else { return }

        func x(_ time: TimeInterval) -> CGFloat {
            CGFloat(time / timeline.duration) * size.width
        }
        func midY(_ lane: TakeTimeline.Lane) -> CGFloat {
            (CGFloat(lanes.firstIndex(of: lane) ?? 0) + 0.5) * laneHeight
        }

        for lane in lanes {
            context.fill(
                Path(CGRect(x: 0, y: midY(lane) - 0.5, width: size.width, height: 1)),
                with: .color(AppColors.meterTrack)
            )
        }

        // Risers where the take steps from one lane to another - the thin
        // verticals that make a hypnogram read as one line, not three rows.
        for (previous, segment) in zip(timeline.segments, timeline.segments.dropFirst())
        where previous.kind.lane != segment.kind.lane && segment.start - previous.end < 0.001 {
            var riser = Path()
            riser.move(to: CGPoint(x: x(segment.start), y: midY(previous.kind.lane)))
            riser.addLine(to: CGPoint(x: x(segment.start), y: midY(segment.kind.lane)))
            context.stroke(riser, with: .color(.white.opacity(0.14)), lineWidth: 1)
        }

        let barHeight = laneHeight * 0.46
        for segment in timeline.segments {
            let minX = x(segment.start)
            let width = max(3, x(segment.end) - minX)
            let rect = CGRect(x: minX, y: midY(segment.kind.lane) - barHeight / 2, width: width, height: barHeight)
            context.fill(
                Path(roundedRect: rect, cornerRadius: min(3, width / 2), style: .continuous),
                with: .color(color(for: segment.kind))
            )
        }

        if let playhead {
            let px = min(max(x(playhead), 0.75), size.width - 0.75)
            context.fill(
                Path(CGRect(x: px - 0.75, y: 0, width: 1.5, height: size.height)),
                with: .color(.white.opacity(0.9))
            )
        }
    }

    private func color(for kind: TakeTimeline.Kind) -> Color {
        switch kind {
        case .speaking: AppColors.primary
        case .pause: AppColors.info
        case .longPause: AppColors.categoryCopper
        case .filler: AppColors.warning
        }
    }

    private var accessibilitySummary: String {
        var parts = ["Speaking for \(Int((timeline.talkShare * 100).rounded())) percent of the take"]
        let longPauses = timeline.longPauseCount
        if longPauses > 0 {
            parts.append("\(longPauses) long \(longPauses == 1 ? "pause" : "pauses") mid-sentence")
        }
        return parts.joined(separator: ". ")
    }
}

#Preview {
    let script: [(String, Double, Bool)] = [
        ("So", 0.3, false), ("we", 0.25, false), ("um", 0.35, true), ("shipped", 0.3, false), ("it.", 0.9, false),
        ("Then", 0.25, false), ("the", 1.8, false), ("like", 0.3, true), ("team", 0.25, false), ("asked", 0.25, false),
        ("why.", 1.0, false), ("And", 0.25, false), ("uh", 0.3, true), ("honestly", 0.3, false), ("we", 0.25, false),
        ("waited", 2.2, false), ("too", 0.25, false), ("long.", 0.8, false), ("Next", 0.25, false), ("time", 0.25, false),
        ("we", 0.25, false), ("ship", 0.3, false), ("early.", 0.2, false),
    ]
    var clock = 0.6
    let words = script.map { text, gapAfter, filler in
        defer { clock += 0.3 + gapAfter }
        return TranscriptionWord(word: text, start: clock, end: clock + 0.3, isFiller: filler)
    }
    let playback = RecordingDetailPlaybackViewModel()
    playback.currentTime = 6.2

    return GlassCard {
        TakeTimelineView(timeline: TakeTimeline(words: words, duration: clock + 0.5), playback: playback) { _ in }
    }
    .padding(16)
    .appBackground(.subtle)
}
