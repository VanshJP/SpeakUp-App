import SwiftUI

// MARK: - SubscoreRadarChart

/// Sunburst / annular-wedge chart that visualizes a speech recording's subscores
/// on a shared 0-100 scale. Each metric occupies one colored wedge whose radial
/// length encodes its score. The composite overall score sits as plain text in
/// the central hole.
///
/// Designed for the SpeakUp glassmorphism aesthetic — translucent track wedges,
/// score-color gradient fills, subtle concentric grid rings, and an animated
/// draw-in when `animate` is toggled true. Tapping a wedge or label opens a
/// `MetricExplainerSheet` describing the metric.
struct SubscoreRadarChart: View {
    struct Axis: Identifiable, Equatable {
        let id: String
        let label: String
        let icon: String
        let value: Int

        init(id: String, label: String, icon: String, value: Int) {
            self.id = id
            self.label = label
            self.icon = icon
            self.value = max(0, min(100, value))
        }
    }

    let axes: [Axis]
    let overallScore: Int
    var animate: Bool
    /// Set false when the composite score is already displayed next to the
    /// chart — the central numeral would otherwise be a second copy of it.
    var showsCenterScore: Bool
    /// Optional best/worst callout. When either is set, the two named axes
    /// render at full opacity with a direction marker and every other label
    /// dims, so the chart carries the "strongest / weakest" story on its own.
    var emphasizedAxisIDs: (strongest: String?, weakest: String?)

    @State private var drawProgress: CGFloat
    @State private var selectedAxis: Axis?
    @State private var isAnimatingIn = false

    /// Room reserved outside the annulus for the orbiting labels. Tightened
    /// from 52 — the labels were parked far enough out that the donut shrank
    /// and the card gained a ring of dead space.
    private let labelInset: CGFloat = 42

    init(
        axes: [Axis],
        overallScore: Int,
        animate: Bool = true,
        showsCenterScore: Bool = true,
        emphasizedAxisIDs: (strongest: String?, weakest: String?) = (nil, nil)
    ) {
        self.axes = axes
        self.overallScore = overallScore
        self.animate = animate
        self.showsCenterScore = showsCenterScore
        self.emphasizedAxisIDs = emphasizedAxisIDs
        self._drawProgress = State(initialValue: animate ? 0.0 : 1.0)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = (side / 2) - labelInset
            let inner = radius * 0.38

            ZStack {
                wedgeCanvas(outerRadius: radius, innerRadius: inner)
                hitTestLayer(outerRadius: radius, innerRadius: inner)
                axisLabels(center: center, radius: radius)
                if showsCenterScore {
                    centerScore
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { if animate { animateIn() } }
        .onChange(of: animate) { _, newValue in
            if newValue {
                animateIn()
            } else {
                var resetTx = Transaction()
                resetTx.disablesAnimations = true
                withTransaction(resetTx) {
                    drawProgress = 1
                }
            }
        }
        .sheet(item: $selectedAxis) { axis in
            MetricExplainerSheet(axis: axis)
        }
    }

    private func selectAxis(_ axis: Axis) {
        Haptics.selection()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedAxis = axis
        }
    }

    // MARK: - Layers

    /// Draws every wedge in a single Canvas pass rather than one SwiftUI Shape
    /// per ring, so the view count stays flat during the draw-in animation.
    ///
    /// Radius encodes the value continuously. It used to quantize into six
    /// buckets aligned to the score bands, which meant everything from 60 to 79
    /// drew an identical shape — five different subscores rendering the same
    /// made the chart decorative rather than informative. The concentric rings
    /// survive as a *scale grid* drawn across the full annulus: they are
    /// graph paper now, not the encoding.
    private func wedgeCanvas(outerRadius: CGFloat, innerRadius: CGFloat) -> some View {
        let count = max(axes.count, 1)
        let step = 2 * Double.pi / Double(count)
        let angularGap: Double = step * 0.04
        let gridRings = 4
        let progress = drawProgress
        let selectedID = selectedAxis?.id

        // Hoist per-axis trig to one O(axes) pass per body re-evaluation
        // instead of recomputing inside the Canvas closure on every frame.
        let table: [WedgeGeometry] = axes.enumerated().map { index, axis in
            let mid = -.pi / 2 + step * Double(index)
            let start = Angle(radians: mid - step / 2 + angularGap / 2)
            let end = Angle(radians: mid + step / 2 - angularGap / 2)
            return WedgeGeometry(
                start: start,
                end: end,
                fraction: CGFloat(max(0, min(100, axis.value))) / 100,
                axisID: axis.id
            )
        }

        return Canvas(rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            for wedge in table {
                let isSelected = selectedID == wedge.axisID
                let bump: CGFloat = isSelected ? 4 : 0
                let outer = outerRadius + bump
                let fullSpan = outer - innerRadius

                // 1. Track — the wedge's full extent, so an empty axis still
                //    reads as a slot rather than as missing geometry.
                context.fill(
                    AnnularWedge.makePath(
                        center: center,
                        innerRadius: innerRadius,
                        outerRadius: outer,
                        startAngle: wedge.start,
                        endAngle: wedge.end
                    ),
                    with: .color(Color.white.opacity(isSelected ? 0.09 : 0.05))
                )

                // 2. Fill — one continuous wedge whose outer edge lands at the
                //    value. Opacity rises with the value too, so a strong axis
                //    reads brighter as well as longer.
                let filledSpan = fullSpan * wedge.fraction * progress
                guard filledSpan > 0.5 else { continue }

                let opacity = 0.40 + 0.50 * Double(wedge.fraction) + (isSelected ? 0.10 : 0)
                context.fill(
                    AnnularWedge.makePath(
                        center: center,
                        innerRadius: innerRadius,
                        outerRadius: innerRadius + filledSpan,
                        startAngle: wedge.start,
                        endAngle: wedge.end
                    ),
                    with: .color(Self.wedgeHue.opacity(min(1.0, opacity)))
                )
            }

            // 3. Scale grid — thin concentric separators across the whole
            //    annulus, drawn last so they read as graph paper over the fill
            //    instead of chunking it into buckets.
            for ring in 1..<gridRings {
                let r = innerRadius + (outerRadius - innerRadius) * CGFloat(ring) / CGFloat(gridRings)
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(Color.black.opacity(0.28)),
                    lineWidth: 1
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// One hue for every wedge. Eight score-colored wedges became a rainbow
    /// once the palette brightened; length and opacity carry the value, and
    /// the only color accents left on the chart are the strongest/weakest
    /// markers on the labels.
    private static let wedgeHue = AppColors.categoryBrandBright

    private struct WedgeGeometry {
        let start: Angle
        let end: Angle
        /// Value mapped to 0...1 of the annulus span.
        let fraction: CGFloat
        let axisID: String
    }

    /// Static, animation-independent hit targets — one shape per axis. These
    /// don't observe `drawProgress` so they don't rebuild during the
    /// draw-in animation.
    @ViewBuilder
    private func hitTestLayer(outerRadius: CGFloat, innerRadius: CGFloat) -> some View {
        let count = max(axes.count, 1)
        let step = 2 * Double.pi / Double(count)
        let angularGap: Double = step * 0.04

        ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
            let mid = -.pi / 2 + step * Double(index)
            let start = Angle(radians: mid - step / 2 + angularGap / 2)
            let end = Angle(radians: mid + step / 2 - angularGap / 2)
            let wedge = AnnularWedge(
                innerRadius: innerRadius,
                outerRadius: outerRadius + 4,
                startAngle: start,
                endAngle: end
            )
            wedge
                .fill(Color.white.opacity(0.001))
                .contentShape(wedge)
                .onTapGesture { selectAxis(axis) }
        }
    }

    @ViewBuilder
    private func axisLabels(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
            let anchorPoint = vertex(at: index, center: center, radius: radius + 21, scaled: 1.0)
            axisLabel(axis: axis)
                .contentShape(Rectangle())
                .onTapGesture { selectAxis(axis) }
                .position(x: anchorPoint.x, y: anchorPoint.y)
        }
    }

    @ViewBuilder
    private func axisLabel(axis: Axis) -> some View {
        let isStrongest = emphasizedAxisIDs.strongest != nil && axis.id == emphasizedAxisIDs.strongest
        let isWeakest = emphasizedAxisIDs.weakest != nil && axis.id == emphasizedAxisIDs.weakest
        let hasEmphasis = emphasizedAxisIDs.strongest != nil || emphasizedAxisIDs.weakest != nil

        // The value is neutral unless this axis is one of the two callouts.
        // Score-coloring all eight numbers put the rainbow back in the text
        // after it had been taken out of the wedges.
        let valueTint: Color = {
            if isStrongest { return AppColors.success }
            if isWeakest { return AppColors.warning }
            return .white
        }()

        VStack(spacing: 1) {
            Text("\(axis.value)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(valueTint)
            HStack(spacing: 2) {
                if isStrongest {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(AppColors.success)
                } else if isWeakest {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(AppColors.warning)
                }
                Text(axis.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .tracking(0.3)
                    .lineLimit(1)
            }
        }
        // The two callouts stay at full strength and everything else recedes,
        // which is what lets the marker read without a legend.
        .opacity(hasEmphasis && !isStrongest && !isWeakest ? 0.55 : 1)
        .fixedSize()
    }

    private var centerScore: some View {
        let color = AppColors.scoreColor(for: overallScore)
        // Clamp + round so the count-up lands exactly on `overallScore`
        // instead of one below (e.g. Int(66 * 0.9994) == 65 truncates).
        let clamped = min(1.0, max(0.0, drawProgress))
        let displayed = Int((Double(overallScore) * Double(clamped)).rounded())
        return VStack(spacing: 0) {
            Text("\(displayed)")
                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text("/ 100")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Geometry

    private func axisAngle(for index: Int) -> Double {
        let step = (2 * Double.pi) / Double(max(axes.count, 1))
        return -.pi / 2 + step * Double(index)
    }

    private func vertex(at index: Int, center: CGPoint, radius: CGFloat, scaled: CGFloat) -> CGPoint {
        let theta = axisAngle(for: index)
        let r = radius * scaled
        return CGPoint(
            x: center.x + r * CGFloat(cos(theta)),
            y: center.y + r * CGFloat(sin(theta))
        )
    }

    private func animateIn() {
        guard !isAnimatingIn else { return }
        isAnimatingIn = true
        // Reset must run outside any inherited animation transaction (e.g.
        // RecordingDetailView wraps `animate = true` in a 0.8s easeOut), or
        // the reset itself animates 1→0 and races the draw-in 0→1.
        var resetTx = Transaction()
        resetTx.disablesAnimations = true
        withTransaction(resetTx) {
            drawProgress = 0
        }
        withAnimation(.easeOut(duration: 0.9)) {
            drawProgress = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(950))
            isAnimatingIn = false
        }
    }
}

// MARK: - AnnularWedge Shape

struct AnnularWedge: Shape {
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        AnnularWedge.makePath(
            center: CGPoint(x: rect.midX, y: rect.midY),
            innerRadius: innerRadius,
            outerRadius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle
        )
    }

    /// Shared path builder reused by both `Shape.path(in:)` and the
    /// `Canvas`-based wedge renderer in `SubscoreRadarChart`.
    static func makePath(
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startAngle: Angle,
        endAngle: Angle
    ) -> Path {
        var path = Path()
        guard outerRadius > innerRadius else { return path }

        // Thin rings: skip corner rounding to avoid degenerate quad-curves
        // and roughly halve path-build cost. Fires when the chart is small
        // or during the first frames of the draw-in animation.
        let ringThickness = outerRadius - innerRadius
        if ringThickness < 6 {
            var simple = Path()
            simple.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            simple.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
            simple.closeSubpath()
            return simple
        }

        let r: CGFloat = min(3.5, ringThickness * 0.25)

        let oStart = point(center: center, radius: outerRadius, angle: startAngle)
        let oEnd   = point(center: center, radius: outerRadius, angle: endAngle)
        let iEnd   = point(center: center, radius: innerRadius, angle: endAngle)
        let iStart = point(center: center, radius: innerRadius, angle: startAngle)

        let oStartInset = point(center: center, radius: outerRadius - r, angle: startAngle)
        let oEndInset   = point(center: center, radius: outerRadius - r, angle: endAngle)
        let iEndInset   = point(center: center, radius: innerRadius + r, angle: endAngle)

        path.move(to: oStartInset)
        path.addQuadCurve(to: nudge(oStart, toward: oEnd, by: r), control: oStart)
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle + insetAngle(r, outerRadius), endAngle: endAngle - insetAngle(r, outerRadius), clockwise: false)
        path.addQuadCurve(to: oEndInset, control: oEnd)
        path.addLine(to: iEndInset)
        path.addQuadCurve(to: nudge(iEnd, toward: iStart, by: r), control: iEnd)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle - insetAngle(r, innerRadius), endAngle: startAngle + insetAngle(r, innerRadius), clockwise: true)
        path.addQuadCurve(to: oStartInset, control: iStart)
        path.closeSubpath()
        return path
    }

    private static func point(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(cos(angle.radians)),
            y: center.y + radius * CGFloat(sin(angle.radians))
        )
    }

    private static func nudge(_ from: CGPoint, toward to: CGPoint, by d: CGFloat) -> CGPoint {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len > 0 else { return from }
        return CGPoint(x: from.x + dx / len * d, y: from.y + dy / len * d)
    }

    private static func insetAngle(_ r: CGFloat, _ radius: CGFloat) -> Angle {
        guard radius > 0 else { return .zero }
        return Angle(radians: Double(r / radius))
    }
}

// MARK: - Convenience Builder

extension SubscoreRadarChart.Axis {
    static func from(subscores: SpeechSubscores, isPromptRelevance: Bool) -> [SubscoreRadarChart.Axis] {
        var axes: [SubscoreRadarChart.Axis] = [
            .init(id: "clarity", label: "Clarity", icon: "waveform", value: subscores.clarity),
            .init(id: "pace", label: "Pace", icon: "speedometer", value: subscores.pace),
            .init(id: "fillers", label: "Fillers", icon: "text.badge.minus", value: subscores.fillerUsage),
            .init(id: "pauses", label: "Pauses", icon: "pause.circle", value: subscores.pauseQuality)
        ]
        if let v = subscores.vocalVariety {
            axes.append(.init(id: "vocal", label: "Vocal", icon: "waveform.path.ecg", value: v))
        }
        if let v = subscores.delivery {
            axes.append(.init(id: "delivery", label: "Delivery", icon: "speaker.wave.3", value: v))
        }
        if let v = subscores.vocabulary {
            axes.append(.init(id: "vocab", label: "Vocab", icon: "textformat.abc", value: v))
        }
        if let v = subscores.structure {
            axes.append(.init(id: "structure", label: "Structure", icon: "list.bullet.indent", value: v))
        }
        if let v = subscores.relevance {
            axes.append(.init(
                id: "relevance",
                label: isPromptRelevance ? "Relevance" : "Coherence",
                icon: isPromptRelevance ? "target" : "arrow.triangle.branch",
                value: v
            ))
        }
        return axes
    }
}
