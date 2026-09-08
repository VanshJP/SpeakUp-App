import SwiftUI

/// Shared dial for prepare countdown and recording clock. Geometry is against a
/// 150pt dial scaled by `diameter` — settings thumbnails and session clocks share
/// one drawing. Session screens get diameter from `SessionDialSlot`, never a literal.
struct TimerDial: View {
    let look: TimerLook
    let progress: Double
    let text: String
    var caption: String? = nil
    var accent: Color = AppColors.primary
    var textColor: Color = .white
    var isPulsing: Bool = false
    var diameter: CGFloat = 150
    var tick: Double = 1

    private let segmentCount = 12
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
                    // Orb is the progress read-out — shrinks as timer drains.
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
        // Combined a11y: uncombined VoiceOver reads "7" then "SEC" as two swipes
        // and re-announces every tick without saying what the dial is.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.map { "\(text) \($0)" } ?? text)
        .accessibilityAddTraits(.updatesFrequently)
    }

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
        // Clamp the stack, not the number — caption at a11y size can be wider.
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

/// Session dial sizing. Target from slot **width**, never height — countdown
/// slots are ~460pt tall, recording ~260pt (waveform). Height-derived diameter
/// resized at the prepare→record hand-off. Height only shrinks via the ladder.
nonisolated enum SessionDial {
    static let minDiameter: CGFloat = 170
    static let maxDiameter: CGFloat = 260
    static let widthFill: CGFloat = 0.66

    /// Largest-first rungs for `ViewThatFits`. Last rung is a squeezed fallback.
    static func ladder(from target: CGFloat) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        (target, target * 0.85, target * 0.7, 110)
    }

    static func diameter(fittingWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return minDiameter }
        return min(max(width * widthFill, minDiameter), maxDiameter)
    }
}

/// Middle of a session screen: dial + stacked cues, sized to leftover space.
/// Slot height must not move mid-take (`container − topBar − bottomControls`) —
/// coaching cue overlays `bottomControls` rather than growing it (see RecordingView).
struct SessionDialSlot<Content: View>: View {
    var spacing: CGFloat = 18
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geo in
            let rungs = SessionDial.ladder(from: SessionDial.diameter(fittingWidth: geo.size.width))

            // Fixed arity, not ForEach — ViewThatFits measures subviews individually.
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

struct TimerView: View {
    let remainingTime: TimeInterval
    let progress: Double
    let color: Color
    let isRecording: Bool
    var isOvertime: Bool = false
    var timerLabel: String = "remaining"
    var look: TimerLook = .ring
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
            // 10 Hz upstream. Plain linear (not `.motion`) so clock keeps
            // interpolating under Reduce Motion.
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
