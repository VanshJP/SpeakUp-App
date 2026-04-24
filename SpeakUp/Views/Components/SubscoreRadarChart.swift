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
    var animate: Bool = true

    @State private var drawProgress: CGFloat = 0
    @State private var selectedAxis: Axis?

    private let labelInset: CGFloat = 52

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = (side / 2) - labelInset

            ZStack {
                wedgeLayer(center: center, outerRadius: radius, innerRadius: radius * 0.38)
                axisLabels(center: center, radius: radius)
                centerScore
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { if animate { animateIn() } }
        .onChange(of: animate) { _, newValue in
            if newValue { animateIn() } else { drawProgress = 0 }
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

    @ViewBuilder
    private func wedgeLayer(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> some View {
        let count = max(axes.count, 1)
        let step = 2 * Double.pi / Double(count)
        let angularGap: Double = step * 0.04
        let ringCount = 6
        let radialGap: CGFloat = 2.5

        ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
            let mid = axisAngle(for: index)
            let start = Angle(radians: mid - step / 2 + angularGap / 2)
            let end = Angle(radians: mid + step / 2 - angularGap / 2)
            let isSelected = selectedAxis?.id == axis.id
            let color = AppColors.scoreColor(for: axis.value)
            let filledRings: Int = {
                let v = axis.value
                if v == 0 { return 0 }
                if v < 40 { return v < 20 ? 1 : 2 }
                if v < 60 { return 3 }
                if v < 80 { return 4 }
                return v < 90 ? 5 : 6
            }()
            let bump: CGFloat = isSelected ? 4 : 0
            let span = ((outerRadius + bump) - innerRadius) * drawProgress

            ForEach(0..<ringCount, id: \.self) { ring in
                let ringInner = innerRadius + span * CGFloat(ring) / CGFloat(ringCount) + radialGap / 2
                let ringOuter = innerRadius + span * CGFloat(ring + 1) / CGFloat(ringCount) - radialGap / 2
                let isFilled = ring < filledRings
                let ringFraction = Double(ring) / Double(max(ringCount - 1, 1))
                let filledOpacity = isSelected
                    ? 0.55 + 0.45 * ringFraction
                    : 0.45 + 0.47 * ringFraction
                let fillColor: Color = isFilled
                    ? color.opacity(filledOpacity)
                    : Color.white.opacity(isSelected ? 0.09 : 0.055)

                AnnularWedge(
                    innerRadius: ringInner,
                    outerRadius: ringOuter,
                    startAngle: start,
                    endAngle: end
                )
                .fill(fillColor)
                .allowsHitTesting(false)
            }

            AnnularWedge(
                innerRadius: innerRadius,
                outerRadius: outerRadius + bump,
                startAngle: start,
                endAngle: end
            )
            .fill(Color.white.opacity(0.001))
            .contentShape(AnnularWedge(
                innerRadius: innerRadius,
                outerRadius: outerRadius + bump,
                startAngle: start,
                endAngle: end
            ))
            .onTapGesture { selectAxis(axis) }
        }
    }

    @ViewBuilder
    private func axisLabels(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
            let anchorPoint = vertex(at: index, center: center, radius: radius + 26, scaled: 1.0)
            axisLabel(axis: axis)
                .contentShape(Rectangle())
                .onTapGesture { selectAxis(axis) }
                .position(x: anchorPoint.x, y: anchorPoint.y)
        }
    }

    @ViewBuilder
    private func axisLabel(axis: Axis) -> some View {
        VStack(spacing: 1) {
            Text("\(axis.value)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppColors.scoreColor(for: axis.value))
            Text(axis.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .tracking(0.3)
                .lineLimit(1)
        }
        .fixedSize()
    }

    private var centerScore: some View {
        let color = AppColors.scoreColor(for: overallScore)
        return VStack(spacing: 0) {
            Text("\(Int(Double(overallScore) * Double(drawProgress)))")
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
        drawProgress = 0
        withAnimation(.easeOut(duration: 0.9)) {
            drawProgress = 1
        }
    }
}

// MARK: - AnnularWedge Shape

struct AnnularWedge: Shape {
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var startAngle: Angle
    var endAngle: Angle

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(innerRadius, outerRadius) }
        set {
            innerRadius = newValue.first
            outerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard outerRadius > innerRadius else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r: CGFloat = min(3.5, (outerRadius - innerRadius) * 0.25)

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

    private func point(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(cos(angle.radians)),
            y: center.y + radius * CGFloat(sin(angle.radians))
        )
    }

    private func nudge(_ from: CGPoint, toward to: CGPoint, by d: CGFloat) -> CGPoint {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len > 0 else { return from }
        return CGPoint(x: from.x + dx / len * d, y: from.y + dy / len * d)
    }

    private func insetAngle(_ r: CGFloat, _ radius: CGFloat) -> Angle {
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
