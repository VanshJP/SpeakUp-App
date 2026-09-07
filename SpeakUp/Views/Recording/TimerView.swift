import SwiftUI

/// The one timer visual for a session — the prepare countdown *and* the running
/// recording clock.
///
/// `TimerLook` used to style only the countdown: pick Orb or Segments in
/// Settings and the prepare screen changed, then recording started and the
/// clock fell back to a plain ring nobody chose. Both screens render through
/// this now, so the look the user picks is the look they record with.
///
/// Geometry is expressed against a 150pt dial and scaled by `diameter`, so a
/// settings thumbnail and a full-screen session clock are the same drawing at
/// two sizes rather than two drawings. Session screens get their `diameter`
/// from `SessionDialSlot`, never from a literal.
struct TimerDial: View {
    let look: TimerLook
    let progress: Double
    /// Already formatted: "7" for a countdown, "1:23" for a running clock.
    let text: String
    var caption: String? = nil
    var accent: Color = AppColors.primary
    var textColor: Color = .white
    var isPulsing: Bool = false
    var diameter: CGFloat = 150
    /// Seconds between `progress` updates — the countdown ticks once a second,
    /// the recording timer runs at 10 Hz. Animating over the wrong one either
    /// stutters or lags behind the number.
    var tick: Double = 1

    private let segmentCount = 12

    /// Everything below is written for a 150pt dial and multiplied by this.
    private var s: CGFloat { diameter / 150 }

    var body: some View {
        ZStack {
            switch look {
            case .ring:
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 140 * s, height: 140 * s)
                    .scaleEffect(isPulsing ? 1.06 : 1.0)

                RingProgress(progress: progress, color: accent, lineWidth: 5 * s)
                    .frame(width: 110 * s, height: 110 * s)
                    .animation(.linear(duration: tick), value: progress)

                label(size: 40, maxWidth: 92)

            case .orb:
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.55), accent.opacity(0.02)],
                            center: .center,
                            startRadius: 6 * s,
                            endRadius: 78 * s
                        )
                    )
                    .frame(width: 150 * s, height: 150 * s)
                    // The orb itself is the progress read-out: it shrinks as
                    // the timer drains, so there is no ring to read.
                    .scaleEffect(0.72 + 0.28 * progress)
                    .animation(.linear(duration: tick), value: progress)

                label(size: 44, maxWidth: 108)

            case .segments:
                ZStack {
                    ForEach(0..<segmentCount, id: \.self) { i in
                        Capsule()
                            .fill(
                                Double(i) < progress * Double(segmentCount)
                                    ? accent
                                    : Color.white.opacity(0.12)
                            )
                            .frame(width: 3 * s, height: 14 * s)
                            .offset(y: -62 * s)
                            .rotationEffect(.degrees(Double(i) / Double(segmentCount) * 360))
                    }
                }
                .frame(width: 140 * s, height: 140 * s)

                label(size: 40, maxWidth: 104)

            case .minimal:
                VStack(spacing: 14 * s) {
                    Text(text)
                        .font(.system(size: 64 * s, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(textColor)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.3), value: text)

                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 120 * s, height: 3 * s)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(accent)
                                .frame(width: 120 * s * CGFloat(max(0, min(1, progress))), height: 3 * s)
                                .animation(.linear(duration: tick), value: progress)
                        }

                    captionText
                }
                .frame(width: 140 * s, height: 140 * s)
            }
        }
        .frame(width: diameter, height: diameter)
        // One element, not three. Left uncombined VoiceOver reads the dial as
        // "7" then "SEC" — two swipes for one reading — and re-announces the
        // clock every tick without saying what it is.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.map { "\(text) \($0)" } ?? text)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// The number and its caption, clamped to the space inside the dial so a
    /// clock reading ("12:34") shrinks instead of spilling over the ring.
    private func label(size: CGFloat, maxWidth: CGFloat) -> some View {
        VStack(spacing: 2 * s) {
            Text(text)
                .font(.system(size: size * s, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(textColor)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: text)

            captionText
        }
        // Clamped on the stack, not the number: "REMAINING" at an
        // accessibility text size is wider than the number and would
        // otherwise spill out past the ring.
        .frame(maxWidth: maxWidth * s)
    }

    @ViewBuilder
    private var captionText: some View {
        if let caption {
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1.0)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Session Dial Slot

/// Sizing rules for the dial in the middle of a session screen.
///
/// The number is derived from the space the slot actually has, never written
/// down at a call site: a fixed dial is either lost in the middle of a modern
/// phone or shoving the record button off the bottom of a small one.
nonisolated enum SessionDial {
    /// Below this the reading stops being glanceable.
    static let minDiameter: CGFloat = 170
    /// Above this the `.minimal` look's 64pt-per-150 numerals get silly.
    static let maxDiameter: CGFloat = 260
    /// Share of the slot's **width** the dial takes.
    static let widthFill: CGFloat = 0.66

    /// The rungs `SessionDialSlot` tries, largest first. The target is only a
    /// target: the slot also holds whatever the caller stacked with the dial
    /// (a framework cue, a drill metric, a phase label) and those have to fit
    /// too. The last rung is the fallback when nothing fits, so it is small
    /// enough to survive a squeezed slot rather than derived from the target.
    static func ladder(from target: CGFloat) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        (target, target * 0.85, target * 0.7, 110)
    }

    /// Target diameter for a slot of this width.
    ///
    /// Width, not `min(width, height)`. Height was the first version's
    /// mistake. The countdown's slot is ~460pt tall; the recording screen's is
    /// ~260pt, because its bottom carries a record button wrapped in up to
    /// 220pt of waveform (`.rings` is the default). A height-derived dial
    /// therefore came out at the 260 cap on the countdown and ~206 on the very
    /// next screen — a resize at exactly the hand-off the shared slot exists
    /// to smooth.
    ///
    /// Width is the one input the two screens share: both slots are the
    /// container minus the same 16pt page inset, and neither can change while
    /// a session is running. Height still has a say, but only ever to shrink —
    /// that is `SessionDialSlot`'s ladder, and it fires only when a screen
    /// genuinely cannot show the shared size.
    static func diameter(fittingWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return minDiameter }
        return min(max(width * widthFill, minDiameter), maxDiameter)
    }
}

/// The middle of a session screen: the dial, plus anything stacked with it,
/// sized to whatever the top and bottom slots left over.
///
/// This replaced `Spacer() / dial / Spacer()` around a hard-coded 200pt dial,
/// which on a waveform-less recording screen parked the dial in a ~400pt gap
/// and left ~90pt empty on either side of it. The slot claims that space and
/// spends it on the dial instead, and gives it back when the top and bottom
/// grow.
///
/// Three things the first version of this got wrong, all fixed here:
///
/// - **Height is not a shared input.** Sizing from `min(width, height)` gave
///   the countdown the 260 cap and the recording screen ~206, because their
///   bottoms cost wildly different amounts — a resize at the one hand-off this
///   slot exists to smooth. The target now comes from the slot's width, which
///   both screens share exactly. See `SessionDial.diameter(fittingWidth:)`.
/// - **The dial is not the only thing in the slot.** A framework cue, a drill
///   metric and a phase label share it, and `GeometryReader` does not clip, so
///   a diameter that ignored them pushed them out over the record button on a
///   small phone. `ViewThatFits` picks the largest rung that fits what the
///   caller actually put in — which is also how height gets its say, since a
///   slot too short for the shared size simply steps down a rung.
/// - **The slot's height must not move during a take.** It is
///   `container − topBar − bottomControls`, so anything that grows those can
///   step the dial down a rung mid-sentence. That is why the coaching cue is
///   an overlay on `bottomControls` rather than a row inside it — see
///   `RecordingView`.
struct SessionDialSlot<Content: View>: View {
    var spacing: CGFloat = 18
    /// Receives the resolved diameter — pass it straight to `TimerDial` /
    /// `TimerView` rather than picking a number.
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geo in
            let rungs = SessionDial.ladder(from: SessionDial.diameter(fittingWidth: geo.size.width))

            // Fixed arity, not a ForEach: `ViewThatFits` measures its subviews
            // individually and a ForEach would read as one.
            ViewThatFits(in: .vertical) {
                stack(rungs.0)
                stack(rungs.1)
                stack(rungs.2)
                stack(rungs.3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func stack(_ diameter: CGFloat) -> some View {
        VStack(spacing: spacing) {
            content(diameter)
        }
    }
}

/// The recording clock: a `TimerDial` fed a formatted mm:ss reading.
struct TimerView: View {
    let remainingTime: TimeInterval
    let progress: Double
    let color: Color
    let isRecording: Bool
    var isOvertime: Bool = false
    var timerLabel: String = "remaining"
    var look: TimerLook = .ring
    /// Comes from `SessionDialSlot`. The default is the old fixed size, kept
    /// for previews and thumbnails that have no slot to measure.
    var diameter: CGFloat = 200

    var body: some View {
        TimerDial(
            look: look,
            progress: progress,
            text: formattedTime,
            caption: isRecording ? timerLabel : "ready",
            accent: color,
            textColor: isOvertime ? color : .white,
            diameter: diameter,
            // 10 Hz timer upstream. Plain linear, not `.motion`: this is a
            // clock reading, not decoration, so it keeps interpolating under
            // Reduce Motion.
            tick: 0.1
        )
    }

    private var formattedTime: String {
        if isOvertime {
            return "+" + abs(remainingTime).minutesSeconds
        }
        return max(0, remainingTime).minutesSeconds
    }
}

#Preview("Timer Looks") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 24) {
            ForEach(TimerLook.allCases) { look in
                HStack(spacing: 24) {
                    TimerDial(look: look, progress: 0.65, text: "7", caption: "sec")
                        .scaleEffect(0.7)

                    TimerView(
                        remainingTime: 45,
                        progress: 0.75,
                        color: AppColors.primary,
                        isRecording: true,
                        look: look
                    )
                    .scaleEffect(0.7)
                }
            }
        }
    }
}
