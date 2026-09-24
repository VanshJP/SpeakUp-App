import SwiftUI

// MARK: - Take Waveform

/// A take drawn as its loudness over time - the app's one picture of your
/// voice. Wherever the app processes or plays a take, it shows *your* speech
/// instead of a spinner or a slider that could belong to any app.
///
/// Three modes, one drawing:
/// - **`.scan`**: a scan line sweeps across and loops. For waits that report
///   nothing - a scanner that restarts reads as "still looking", where stage
///   text that restarts reads as "started over".
/// - **`.estimate(startedAt:expected:)`**: the waveform *is* the progress
///   bar. Bars light left to right, easing toward 90 % over the expected wait
///   with a shimmer at the leading edge; only `isComplete` fills the rest. It
///   can run slow but never claims to be done early.
/// - **`.filled(fraction)`**: a known position - playback, a download. Played
///   bars in `tint`, the rest dim, and an optional playhead.
///
/// `levels` are 0...1 and are resampled to however many bars fit, so a
/// 56-bucket take and a 200-peak file both fill any width without repeating.
/// Scan and estimate run on a `TimelineView`; filled redraws only when the
/// fraction changes. One `Canvas` either way.
struct TakeWaveform: View {
    enum Mode: Equatable {
        case scan
        case estimate(startedAt: Date, expected: TimeInterval)
        case filled(Double)
    }

    let levels: [CGFloat]
    var mode: Mode = .scan
    /// Finished: every bar lit in success green, nothing moving.
    var isComplete = false
    var tint: Color = AppColors.primary
    /// Fixed bar pitch. Nil gives one bar per level, spread to fit.
    var barWidth: CGFloat? = nil
    var barSpacing: CGFloat = 2
    var showsPlayhead = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sweep: Double = 2.6

    var body: some View {
        Group {
            if case .filled(let fraction) = mode {
                Canvas { context, size in
                    drawFilled(in: context, size: size, fill: CGFloat(fraction))
                }
            } else {
                let paused = isComplete || (reduceMotion && mode == .scan)
                TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: paused)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        switch mode {
                        case .estimate(let startedAt, let expected):
                            let fill = isComplete
                                ? 1
                                : Self.fraction(elapsed: timeline.date.timeIntervalSince(startedAt), expected: expected)
                            drawEstimate(in: context, size: size, fill: fill, time: t)
                        default:
                            let scan = reduceMotion || isComplete ? -1 : (t / Self.sweep).truncatingRemainder(dividingBy: 1)
                            drawScan(in: context, size: size, scan: CGFloat(scan))
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Pacing

    nonisolated static func fraction(elapsed: TimeInterval, expected: TimeInterval) -> CGFloat {
        guard expected > 0 else { return 0 }
        return CGFloat(0.9 * (1 - exp(-2.2 * max(0, elapsed) / expected)))
    }

    // MARK: Levels

    /// Level samples (dB) → `count` bar levels in 0...1. Averages each bucket
    /// so a single spike cannot dominate, and floors silence so a pause still
    /// draws as a quiet stub rather than a gap.
    nonisolated static func levels(fromDecibels samples: [Float], count: Int = 56) -> [CGFloat] {
        guard samples.count >= 4 else { return [] }
        let bucket = max(1, samples.count / count)
        return stride(from: 0, to: samples.count, by: bucket).prefix(count).map { start in
            let slice = samples[start..<min(start + bucket, samples.count)]
            let mean = slice.reduce(0, +) / Float(slice.count)
            let unit = CGFloat(min(1, max(0, (mean + 55) / 50)))
            return 0.1 + 0.9 * pow(unit, 1.3)
        }
    }

    /// An even row of stubs, for a take with no level data - the bar never
    /// vanishes.
    static let flat: [CGFloat] = Array(repeating: 0.3, count: 56)

    /// Full-height bars, for a progress bar that has no take behind it (a
    /// download, a timed hold): the app's bar grammar without pretending to
    /// be a voice.
    static let track: [CGFloat] = Array(repeating: 1, count: 56)

    /// `levels` stretched or squeezed to `count` bars, taking each bucket's
    /// peak so a squeeze keeps the loud moments.
    nonisolated static func resampled(_ levels: [CGFloat], to count: Int) -> [CGFloat] {
        guard !levels.isEmpty, count > 0 else { return [] }
        guard levels.count != count else { return levels }
        return (0..<count).map { index in
            let start = index * levels.count / count
            let end = max(start + 1, (index + 1) * levels.count / count)
            return levels[start..<min(end, levels.count)].max() ?? 0
        }
    }

    // MARK: Drawing

    private struct Bar {
        let rect: CGRect
        let x: CGFloat
        let width: CGFloat
    }

    private func layout(in size: CGSize) -> [Bar] {
        let count: Int
        if let barWidth {
            count = max(1, Int(size.width / (barWidth + barSpacing)))
        } else {
            count = levels.count
        }
        let bars = Self.resampled(levels.isEmpty ? Self.flat : levels, to: count)
        let slot = size.width / CGFloat(max(1, bars.count))
        let width = barWidth ?? max(1.5, slot * 0.55)
        return bars.enumerated().map { index, level in
            let x = (CGFloat(index) + 0.5) * slot
            let height = max(3, min(1, level) * size.height)
            return Bar(
                rect: CGRect(x: x - width / 2, y: (size.height - height) / 2, width: width, height: height),
                x: x,
                width: width
            )
        }
    }

    private func fill(_ context: GraphicsContext, _ bar: Bar, _ color: Color) {
        context.fill(Path(roundedRect: bar.rect, cornerRadius: bar.width / 2), with: .color(color))
    }

    private func drawFilled(in context: GraphicsContext, size: CGSize, fill fraction: CGFloat) {
        let fillX = min(1, max(0, fraction)) * size.width
        for bar in layout(in: size) {
            let color: Color = isComplete
                ? AppColors.success.opacity(0.85)
                : (bar.x <= fillX ? tint : .white.opacity(0.2))
            fill(context, bar, color)
        }
        guard showsPlayhead else { return }
        let head = CGRect(x: fillX - 1, y: 0, width: 2, height: size.height)
        context.fill(Path(roundedRect: head, cornerRadius: 1), with: .color(.white))
    }

    private func drawEstimate(in context: GraphicsContext, size: CGSize, fill fraction: CGFloat, time: Double) {
        let fillX = fraction * size.width
        let shimmer = reduceMotion ? 1 : 0.7 + 0.3 * sin(time * 5)
        for bar in layout(in: size) {
            let color: Color
            if isComplete {
                color = AppColors.success.opacity(0.85)
            } else if bar.x <= fillX {
                color = tint.opacity(0.9)
            } else {
                // The few bars just past the edge glow, so the front of the
                // fill reads as working rather than stopped.
                let glow = max(0, 1 - (bar.x - fillX) / (size.width * 0.07))
                color = glow > 0
                    ? AppColors.categoryBrandBright.opacity(0.2 + 0.6 * glow * shimmer)
                    : .white.opacity(0.14)
            }
            fill(context, bar, color)
        }
    }

    private func drawScan(in context: GraphicsContext, size: CGSize, scan: CGFloat) {
        let scanX = scan * size.width
        for bar in layout(in: size) {
            // Lit where the line is, settled where it has been this sweep,
            // dim ahead of it.
            let glow = max(0, 1 - abs(bar.x - scanX) / (size.width * 0.12))
            let color: Color
            if isComplete {
                color = AppColors.success.opacity(0.75)
            } else if scan < 0 {
                color = tint.opacity(0.6)
            } else if glow > 0 {
                color = AppColors.categoryBrandBright.opacity(0.45 + 0.55 * Double(glow))
            } else if bar.x < scanX {
                color = tint.opacity(0.7)
            } else {
                color = .white.opacity(0.16)
            }
            fill(context, bar, color)
        }

        guard scan >= 0 else { return }
        var line = context
        line.blendMode = .plusLighter
        line.fill(
            Path(CGRect(x: scanX - 1, y: 0, width: 2, height: size.height)),
            with: .linearGradient(
                Gradient(colors: [.clear, AppColors.categoryBrandBright.opacity(0.9), .clear]),
                startPoint: CGPoint(x: scanX, y: 0),
                endPoint: CGPoint(x: scanX, y: size.height)
            )
        )
    }
}

// MARK: - Voice Loader

/// The app's indeterminate loader: a few bars breathing like a voice, in the
/// foreground style. Replaces the stock spinner - which could belong to any
/// app - wherever the app is working. Under Reduce Motion the bars hold
/// still at varied heights.
struct VoiceLoader: View {
    enum Size {
        case small, regular, large

        var height: CGFloat {
            switch self {
            case .small: 12
            case .regular: 18
            case .large: 28
            }
        }
    }

    var size: Size = .regular

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bars = 5

    var body: some View {
        let height = size.height
        let barWidth = max(2, height / 6)
        let width = CGFloat(Self.bars) * barWidth * 2 - barWidth

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.35 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvas in
                for index in 0..<Self.bars {
                    // Offset phases, with the middle bar leading, so the row
                    // reads as a voice rather than a metronome.
                    let phase = t * 5.2 - Double(abs(index - Self.bars / 2)) * 0.9
                    let level = 0.35 + 0.65 * (0.5 + 0.5 * sin(phase))
                    let barHeight = max(barWidth, canvas.height * level)
                    let rect = CGRect(
                        x: CGFloat(index) * barWidth * 2,
                        y: (canvas.height - barHeight) / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .foreground)
                }
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel("Loading")
    }
}
