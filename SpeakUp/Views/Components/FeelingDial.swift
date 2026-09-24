import SwiftUI

// MARK: - Feeling Dial

/// A feeling, on an `ArcDial` scale. The rim carries the words; the readout
/// in the bowl is one face, bending from its low mood to a grin as the wheel
/// turns, over the word and its line.
///
/// Used by the post-take self-check ("How did that go") and onboarding's
/// level step ("How do you feel about speaking today?"), so the first dial a
/// user turns is the one they meet after every take.
///
/// The value under the finger is local and commits through `onSelect` once
/// per release. Hosts never move on by themselves after an answer: one swipe
/// rarely lands on the far end, and a page that left on release took the
/// second swipe away. Each host pairs the dial with an explicit Next.
struct FeelingDial: View {
    struct Option {
        let label: String
        let line: String
    }

    let question: String
    let options: [Option]
    /// Index of the committed answer; nil until one is given.
    let selected: Int?
    /// Degrees of wheel between two stops. Wider for longer labels.
    var step: Double = 26
    /// Tint for a stop once touched. Nil runs the score ramp across the
    /// scale - right for "how did it go", wrong where no answer is worse
    /// than another.
    var tint: ((Int) -> Color)? = nil
    /// The face at the low end: -1 is a frown, 0 flat.
    var lowestMood: Double = -1
    let onSelect: (Int) -> Void

    /// Where the wheel sits once touched; nil until the first touch.
    @State private var scrub: Double?

    private var lastIndex: Int { options.count - 1 }
    private var middle: Int { lastIndex / 2 }
    private var position: Double { scrub ?? Double(selected ?? middle) }
    private var isTouched: Bool { scrub != nil || selected != nil }

    /// The stop under the marker, once there is an answer to show.
    private var shown: Int? {
        isTouched ? min(lastIndex, max(0, Int(position.rounded()))) : nil
    }

    private func color(_ index: Int) -> Color {
        tint?(index) ?? AppColors.scoreColor(for: (index + 1) * 100 / options.count)
    }

    /// `lowestMood` ... 1 (grin) for a position along the scale.
    private func mood(_ position: Double) -> Double {
        guard lastIndex > 0 else { return 1 }
        return min(1, max(lowestMood, lowestMood + (1 - lowestMood) * position / Double(lastIndex)))
    }

    var body: some View {
        ArcDial(
            count: options.count,
            position: position,
            fillsToMarker: isTouched,
            step: step,
            label: { options[$0].label },
            tint: { isTouched ? color($0) : .white },
            // Words only on the rim; the one face lives in the readout.
            glyph: { _ in EmptyView() },
            hub: { readout },
            onScrub: { scrub = $0 },
            onRelease: { projected in
                let value = min(Double(lastIndex), max(0, projected.rounded()))
                // A soft landing, so a flick reads as the wheel coasting to
                // rest rather than jumping.
                withAnimation(.spring(duration: 0.5, bounce: 0.18)) { scrub = value }
                onSelect(Int(value))
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(question)
        .accessibilityValue(shown.map { options[$0].label } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            let next: Int
            switch direction {
            case .increment: next = selected.map { min(lastIndex, $0 + 1) } ?? middle
            case .decrement: next = selected.map { max(0, $0 - 1) } ?? middle
            @unknown default: return
            }
            withAnimation(AppMotion.snap) { scrub = Double(next) }
            onSelect(next)
        }
    }

    private var readout: some View {
        let tint = shown.map(color) ?? .white.opacity(0.5)
        return VStack(spacing: 6) {
            MoodFace(mood: mood(position), lineWidth: 3)
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)

            Text(shown.map { options[$0].label } ?? "Turn the wheel")
                .font(shown == nil
                      ? .title3.weight(.semibold)
                      : .system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(shown == nil ? .white.opacity(0.7) : tint)
                .contentTransition(.interpolate)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(shown.map { options[$0].line } ?? "Swipe sideways, or tap a word")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .motion(AppMotion.snap, value: shown)
    }
}

// MARK: - Mood Face

/// A line-drawn face whose mouth runs from a frown (-1) through flat (0) to a
/// grin (1). The mouth is an animatable shape, so a snap bends it instead of
/// cutting. Draws in the foreground style.
private struct MoodFace: View {
    var mood: Double
    var lineWidth: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let eye = side * 0.1
            ZStack {
                Circle()
                    .strokeBorder(lineWidth: lineWidth)
                Circle()
                    .frame(width: eye, height: eye)
                    .position(x: side * 0.35, y: side * 0.4)
                Circle()
                    .frame(width: eye, height: eye)
                    .position(x: side * 0.65, y: side * 0.4)
                MoodMouth(mood: mood)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct MoodMouth: Shape {
    var mood: Double

    var animatableData: Double {
        get { mood }
        set { mood = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let mid = rect.height * 0.66
        let corners = mid - CGFloat(mood) * rect.height * 0.05
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.3, y: corners))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.7, y: corners),
            control: CGPoint(x: rect.width * 0.5, y: mid + CGFloat(mood) * rect.height * 0.2)
        )
        return path
    }
}
