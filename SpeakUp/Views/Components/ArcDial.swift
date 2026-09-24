import SwiftUI

// MARK: - Arc Dial

/// The crown of a wheel far bigger than the screen. Its centre sits well below
/// the fold, so only the top arc shows and it runs off both edges: the stops
/// either side of the marker lean in, and the rest are out of frame the way a
/// physical dial's would be. Lay it out full-bleed (negative horizontal
/// padding equal to the page inset) or the effect is lost.
///
/// Two shapes, one control:
/// - **A scale** (`wraps: false`, `fillsToMarker: true`): the self-check's
///   Rough...Great. Ticks from the first stop up to the marker take each
///   stop's tint, and dragging past either end rubber-bands.
/// - **A set** (`wraps: true`): the prompt wheel's categories. The stops
///   repeat forever in both directions, and every stop's ticks carry its own
///   tint so the rim reads as bands.
///
/// The dial owns the gesture and nothing else. `position` is continuous, in
/// stops (2.0 = stop 2 under the marker); the host keeps it. A drag reports
/// every change through `onScrub`, unanimated. Lifting reports where the
/// wheel would coast to (the drag's predicted end), or the stop tapped, and
/// the host decides what that means: the scale snaps and clamps, the prompt
/// wheel turns it into a spin. Animate `position` from the host with
/// `withAnimation` - the dial is `Animatable`, so the Canvas redraws on every
/// interpolated frame (gotcha §28), and the selection haptic ticks at each
/// stop the marker passes, through a drag or a spin alike.
struct ArcDial<Glyph: View, Hub: View>: View, Animatable {
    let count: Int
    var position: Double
    var wraps = false
    var fillsToMarker = false
    /// Degrees of wheel between two stops. Wider for longer labels.
    var step: Double = 26
    /// Drag distance per stop. Nil tracks the finger 1:1 at the rim, which
    /// is what makes it feel like a wheel under the hand; a flick coasts on
    /// through the drag's predicted end.
    var pointsPerStop: CGFloat? = nil
    var label: ((Int) -> String)? = nil
    /// False for a dial that only shows a value (the score reveal): no
    /// gesture, so taps fall through to whatever hosts it.
    var isInteractive = true
    /// The selection tick at each stop. Off where the host plays its own
    /// (the reveal's count-up already ticks every ten).
    var playsDetents = true
    /// The control's height; the crown and the bowl's readout sit at the top.
    var height: CGFloat = 300
    let tint: (Int) -> Color
    @ViewBuilder let glyph: (Int) -> Glyph
    /// Drawn in the bowl under the crown - the dial's readout.
    @ViewBuilder let hub: () -> Hub
    var onScrub: (Double) -> Void = { _ in }
    var onRelease: (Double) -> Void = { _ in }

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    @State private var dragStart: Double?
    /// The marker's nod at each stop, signed by the direction of travel.
    @State private var kick: Double = 8

    /// Where the rim crests, from the top of the control.
    private static var crown: CGFloat { 40 }
    private static var ticksPerStep: Int { 6 }

    private var hasGlyphs: Bool { Glyph.self != EmptyView.self }

    /// How far below the crown the readout starts: under whatever the rim
    /// carries, and clear of the side stops, which drop as the arc falls.
    private var hubDepth: CGFloat {
        switch (hasGlyphs, label != nil) {
        case (true, true): 116
        case (false, true): 92
        default: 110
        }
    }

    /// The stop under the marker, unwrapped: it changes at every crossing,
    /// which is what the haptic keys on.
    private var passing: Int { Int(position.rounded()) }

    /// The stop under the marker, as an index into the host's data.
    static func index(at position: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let raw = Int(position.rounded())
        return ((raw % count) + count) % count
    }

    var body: some View {
        GeometryReader { geo in
            let radius = geo.size.width * 0.78
            let center = CGPoint(x: geo.size.width / 2, y: Self.crown + radius)

            ZStack(alignment: .top) {
                wheel(radius: radius, center: center)

                // The fixed marker the wheel turns under. It nods as each
                // stop passes, like a pawl on a ratchet.
                Capsule()
                    .fill(Color.white)
                    .frame(width: 4, height: 46)
                    .shadow(color: .black.opacity(0.4), radius: 4)
                    .keyframeAnimator(initialValue: 0.0, trigger: passing) { marker, angle in
                        marker.rotationEffect(.degrees(angle), anchor: .top)
                    } keyframes: { _ in
                        CubicKeyframe(kick, duration: 0.05)
                        SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                    }
                    .offset(y: Self.crown - 12)

                hub()
                    .frame(width: geo.size.width * (label == nil ? 0.5 : 0.62))
                    .offset(y: Self.crown + hubDepth)
            }
            .frame(width: geo.size.width, height: height, alignment: .top)
            .contentShape(Rectangle())
            .gesture(drag(center: center, radius: radius), isEnabled: isInteractive)
        }
        .frame(height: height)
        // The sides dim as the wheel curves away from you.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.25), location: 0),
                    .init(color: .black, location: 0.3),
                    .init(color: .black, location: 0.7),
                    .init(color: .black.opacity(0.25), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .clipped()
        .sensoryFeedback(.selection, trigger: passing) { _, _ in playsDetents }
        .onChange(of: passing) { old, new in
            kick = new > old ? -8 : 8
        }
    }

    // MARK: Drawing

    private func wheel(radius: CGFloat, center: CGPoint) -> some View {
        Canvas { context, _ in
            let span = 62 / step
            let lowest = wraps ? -Double.infinity : -1.5
            let highest = wraps ? Double.infinity : Double(count - 1) + 1.5
            let tps = Double(Self.ticksPerStep)
            let outer = radius - 4

            // The wheel's body: a disc with a lit rim and an inner groove, so
            // the ticks sit on an object instead of floating.
            let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                              width: radius * 2, height: radius * 2))
            context.fill(
                disc,
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0), .white.opacity(0.015), .white.opacity(0.07)]),
                    center: center,
                    startRadius: radius * 0.7,
                    endRadius: radius
                )
            )
            context.stroke(disc, with: .color(.white.opacity(0.16)), lineWidth: 1)
            let grooveRadius = outer - 46
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - grooveRadius, y: center.y - grooveRadius,
                                       width: grooveRadius * 2, height: grooveRadius * 2)),
                with: .color(.white.opacity(0.05)),
                lineWidth: 1
            )

            // Ticks.
            let first = Int(((max(position - span, lowest)) * tps).rounded(.down))
            let last = Int(((min(position + span, highest)) * tps).rounded(.up))
            if first <= last {
                for tick in first...last {
                    let at = Double(tick) / tps
                    let inRange = wraps || (0...Double(count - 1)).contains(at)
                    let isMajor = tick % Self.ticksPerStep == 0 && inRange
                    let stop = Self.index(at: at, count: count)

                    let color: Color
                    if !inRange {
                        let past = at < 0 ? -at : at - Double(count - 1)
                        color = .white.opacity(0.14 * max(0, 1 - past / 1.5))
                    } else if fillsToMarker {
                        color = at <= position + 0.001
                            ? tint(stop)
                            : .white.opacity(isMajor ? 0.5 : 0.18)
                    } else {
                        let near = abs(at - position) < 0.5
                        color = tint(stop).opacity(near ? 1 : (isMajor ? 0.6 : 0.3))
                    }

                    var tickContext = context
                    tickContext.translateBy(x: center.x, y: center.y)
                    tickContext.rotate(by: .degrees((at - position) * step))
                    let length: CGFloat = isMajor ? 34 : 16
                    let width: CGFloat = isMajor ? 4 : 2
                    tickContext.fill(
                        Path(roundedRect: CGRect(x: -width / 2, y: -outer, width: width, height: length),
                             cornerRadius: width / 2),
                        with: .color(color)
                    )
                }
            }

            // Glyphs and labels, brightest under the marker.
            let firstStop = Int(max(position - span, wraps ? -.infinity : 0).rounded(.down))
            let lastStop = Int(min(position + span, wraps ? .infinity : Double(count - 1)).rounded(.up))
            guard firstStop <= lastStop else { return }
            for stop in firstStop...lastStop {
                guard wraps || (0..<count).contains(stop) else { continue }
                let index = Self.index(at: Double(stop), count: count)
                var stopContext = context
                stopContext.translateBy(x: center.x, y: center.y)
                stopContext.rotate(by: .degrees((Double(stop) - position) * step))
                stopContext.opacity = 1 - 0.6 * min(1, abs(Double(stop) - position))

                if let symbol = stopContext.resolveSymbol(id: index) {
                    stopContext.draw(symbol, at: CGPoint(x: 0, y: -outer + 64))
                }
                if let label {
                    stopContext.draw(
                        Text(label(index))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white),
                        at: CGPoint(x: 0, y: -outer + (hasGlyphs ? 98 : 62))
                    )
                }
            }
        } symbols: {
            ForEach(0..<count, id: \.self) { index in
                glyph(index).tag(index)
            }
        }
    }

    // MARK: Gesture

    private func drag(center: CGPoint, radius: CGFloat) -> some Gesture {
        let pointsPerStop = pointsPerStop ?? radius * CGFloat(step * .pi / 180)
        return DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let start = dragStart ?? position
                dragStart = start
                onScrub(resisted(start - drag.translation.width / pointsPerStop))
            }
            .onEnded { drag in
                let start = dragStart ?? position
                dragStart = nil
                if hypot(drag.translation.width, drag.translation.height) < 6 {
                    // A tap: the stop under the finger.
                    let degrees = atan2(drag.location.y - center.y, drag.location.x - center.x) * 180 / .pi + 90
                    onRelease((position + degrees / step).rounded())
                } else {
                    onRelease(start - drag.predictedEndTranslation.width / pointsPerStop)
                }
            }
    }

    /// Past either end of a scale the wheel gives, but only a third as much.
    private func resisted(_ value: Double) -> Double {
        guard !wraps else { return value }
        let top = Double(count - 1)
        if value < 0 { return value * 0.3 }
        if value > top { return top + (value - top) * 0.3 }
        return value
    }
}
