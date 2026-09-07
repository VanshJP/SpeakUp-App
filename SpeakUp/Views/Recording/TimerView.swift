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
/// phone or shoving the record button off the bottom of a small one, and the
/// countdown and the recording screen have to agree on it either way.
nonisolated enum SessionDial {
    /// Below this the reading stops being glanceable — but never at the cost
    /// of overflowing a slot that is genuinely smaller (see `diameter`).
    static let minDiameter: CGFloat = 170
    /// Above this the `.minimal` look's 64pt-per-150 numerals get silly.
    static let maxDiameter: CGFloat = 260
    /// Share of the slot's short side the dial takes, leaving the rest as
    /// breathing room above and below.
    static let slotFill: CGFloat = 0.8

    static func diameter(fitting size: CGSize) -> CGFloat {
        let side = min(size.width, size.height)
        guard side > 0 else { return minDiameter }
        // The floor is itself clamped to the slot, so a squeezed slot (large
        // accessibility text, a small phone) shrinks the dial instead of
        // pushing the controls under the home indicator.
        return min(max(side * slotFill, min(side, minDiameter)), maxDiameter)
    }
}

/// The middle of a session screen: the dial, plus anything stacked with it,
/// sized to whatever the top and bottom slots left over.
///
/// This replaced `Spacer() / dial / Spacer()` around a hard-coded 200pt dial.
/// On a 6.3" phone that arrangement parked the dial in a ~380pt gap and left
/// the ~90pt on either side of it empty, on the one screen that has nothing
/// else to show. The slot claims that space and spends it on the dial instead,
/// and gives it back when the top and bottom grow.
struct SessionDialSlot<Content: View>: View {
    var spacing: CGFloat = 18
    /// Receives the resolved diameter — pass it straight to `TimerDial` /
    /// `TimerView` rather than picking a number.
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: spacing) {
                content(SessionDial.diameter(fitting: geo.size))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
