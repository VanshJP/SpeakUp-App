import SwiftUI

/// Custom path art for a curriculum lesson. Prefer this over SF Symbols on the Learn path.
struct LessonGlyphView: View {
    let identity: LessonIdentity
    var state: LessonNodeState = .available
    var showsCheckBadge: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Canvas { context, size in
                let ink = inkColor
                LessonGlyphArt.draw(identity.motif, in: context, size: size, ink: ink)
            }
            .opacity(state == .locked ? 0.45 : 1)

            if showsCheckBadge {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.success)
                    .background(Circle().fill(Color.black.opacity(0.55)).padding(-2))
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }

    private var inkColor: Color {
        switch state {
        case .completed: return AppColors.success
        case .current: return identity.accent
        case .available: return identity.accent.opacity(0.92)
        case .locked: return .white.opacity(0.45)
        }
    }
}

/// Dense draw helpers — one Canvas pass per glyph.
enum LessonGlyphArt {
    static func draw(_ motif: LessonMotif, in context: GraphicsContext, size: CGSize, ink: Color) {
        let s = min(size.width, size.height)
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        var ctx = context
        ctx.translateBy(x: mid.x, y: mid.y)
        ctx.scaleBy(x: s / 24, y: s / 24)

        switch motif {
        case .baseline: drawBaseline(&ctx, ink: ink)
        case .fillers: drawFillers(&ctx, ink: ink)
        case .pace: drawPace(&ctx, ink: ink)
        case .score: drawScore(&ctx, ink: ink)
        case .breath: drawBreath(&ctx, ink: ink)
        case .cleanSpeech: drawCleanSpeech(&ctx, ink: ink)
        case .warmUp: drawWarmUp(&ctx, ink: ink)
        case .prep: drawPrep(&ctx, ink: ink)
        case .star: drawStar(&ctx, ink: ink)
        case .pause: drawPause(&ctx, ink: ink)
        case .sentences: drawSentences(&ctx, ink: ink)
        case .nerves: drawNerves(&ctx, ink: ink)
        case .impromptu: drawImpromptu(&ctx, ink: ink)
        case .stamina: drawStamina(&ctx, ink: ink)
        case .celebrate: drawCelebrate(&ctx, ink: ink)
        case .vocal: drawVocal(&ctx, ink: ink)
        case .volume: drawVolume(&ctx, ink: ink)
        case .articulation: drawArticulation(&ctx, ink: ink)
        case .emphasis: drawEmphasis(&ctx, ink: ink)
        case .ruleOfThree: drawRuleOfThree(&ctx, ink: ink)
        case .problemSolution: drawProblemSolution(&ctx, ink: ink)
        case .whatSoWhat: drawWhatSoWhat(&ctx, ink: ink)
        case .bridge: drawBridge(&ctx, ink: ink)
        case .storyArc: drawStoryArc(&ctx, ink: ink)
        case .hook: drawHook(&ctx, ink: ink)
        case .emotion: drawEmotion(&ctx, ink: ink)
        case .closing: drawClosing(&ctx, ink: ink)
        case .qa: drawQA(&ctx, ink: ink)
        case .elevator: drawElevator(&ctx, ink: ink)
        case .talk: drawTalk(&ctx, ink: ink)
        case .graduate: drawGraduate(&ctx, ink: ink)
        case .opener: drawOpener(&ctx, ink: ink)
        case .keepGoing: drawKeepGoing(&ctx, ink: ink)
        case .room: drawRoom(&ctx, ink: ink)
        case .conversation: drawConversation(&ctx, ink: ink)
        }
    }

    // MARK: - Motifs (−12…12 space)

    private static func drawBaseline(_ c: inout GraphicsContext, ink: Color) {
        var line = Path()
        line.move(to: CGPoint(x: -8, y: 5))
        line.addLine(to: CGPoint(x: -3, y: 2))
        line.addLine(to: CGPoint(x: 1, y: 4))
        line.addLine(to: CGPoint(x: 4, y: -2))
        line.addLine(to: CGPoint(x: 8, y: -6))
        c.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        c.fill(Circle().path(in: CGRect(x: 6.5, y: -7.5, width: 3, height: 3)), with: .color(ink))
        // mic stem
        var mic = Path()
        mic.addRoundedRect(in: CGRect(x: -2, y: -8, width: 4, height: 6), cornerSize: CGSize(width: 2, height: 2))
        c.stroke(mic, with: .color(ink.opacity(0.85)), lineWidth: 1.2)
    }

    private static func drawFillers(_ c: inout GraphicsContext, ink: Color) {
        let bubble = RoundedRectangle(cornerRadius: 3, style: .continuous)
            .path(in: CGRect(x: -8, y: -6, width: 12, height: 9))
        c.stroke(bubble, with: .color(ink), lineWidth: 1.5)
        var tail = Path()
        tail.move(to: CGPoint(x: -4, y: 3))
        tail.addLine(to: CGPoint(x: -6, y: 7))
        tail.addLine(to: CGPoint(x: -1, y: 3))
        c.fill(tail, with: .color(ink.opacity(0.7)))
        // strike
        var strike = Path()
        strike.move(to: CGPoint(x: -5, y: -1))
        strike.addLine(to: CGPoint(x: 2, y: -1))
        c.stroke(strike, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    private static func drawPace(_ c: inout GraphicsContext, ink: Color) {
        var arc = Path()
        arc.addArc(center: .zero, radius: 8, startAngle: .degrees(140), endAngle: .degrees(40), clockwise: false)
        c.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        var needle = Path()
        needle.move(to: .zero)
        needle.addLine(to: CGPoint(x: 5, y: -5))
        c.stroke(needle, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        c.fill(Circle().path(in: CGRect(x: -1.4, y: -1.4, width: 2.8, height: 2.8)), with: .color(ink))
    }

    private static func drawScore(_ c: inout GraphicsContext, ink: Color) {
        let heights: [CGFloat] = [4, 7, 5, 9]
        for (i, h) in heights.enumerated() {
            let x = CGFloat(i) * 4 - 7
            c.fill(
                RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: x, y: 5 - h, width: 2.6, height: h)),
                with: .color(ink.opacity(0.55 + Double(i) * 0.12))
            )
        }
    }

    private static func drawBreath(_ c: inout GraphicsContext, ink: Color) {
        for (i, r) in [3.5, 6.0, 8.5].enumerated() {
            var ring = Path()
            ring.addEllipse(in: CGRect(x: -r, y: -r * 0.7, width: r * 2, height: r * 1.4))
            c.stroke(ring, with: .color(ink.opacity(0.35 + Double(i) * 0.22)), lineWidth: 1.3)
        }
    }

    private static func drawCleanSpeech(_ c: inout GraphicsContext, ink: Color) {
        var check = Path()
        check.move(to: CGPoint(x: -6, y: 0))
        check.addLine(to: CGPoint(x: -2, y: 5))
        check.addLine(to: CGPoint(x: 7, y: -6))
        c.stroke(check, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private static func drawWarmUp(_ c: inout GraphicsContext, ink: Color) {
        var wave = Path()
        wave.move(to: CGPoint(x: -9, y: 0))
        for i in 0..<8 {
            let x = CGFloat(i) * 2.4 - 9
            let y = (i % 2 == 0 ? -5.5 : 5.5) * (i == 0 || i == 7 ? 0.35 : 1)
            wave.addLine(to: CGPoint(x: x, y: y))
        }
        c.stroke(wave, with: .color(ink), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
    }

    private static func drawPrep(_ c: inout GraphicsContext, ink: Color) {
        for i in 0..<4 {
            let y = CGFloat(i) * 4.2 - 7
            c.fill(
                RoundedRectangle(cornerRadius: 1.2).path(in: CGRect(x: -7, y: y, width: 14, height: 2.8)),
                with: .color(ink.opacity(0.45 + Double(i) * 0.12))
            )
            c.fill(Circle().path(in: CGRect(x: -6.2, y: y + 0.5, width: 1.8, height: 1.8)), with: .color(ink))
        }
    }

    private static func drawStar(_ c: inout GraphicsContext, ink: Color) {
        var path = Path()
        for i in 0..<5 {
            let angle = Double(i) * (2 * .pi / 5) - .pi / 2
            let p = CGPoint(x: cos(angle) * 8, y: sin(angle) * 8)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            let angle2 = angle + .pi / 5
            path.addLine(to: CGPoint(x: cos(angle2) * 3.4, y: sin(angle2) * 3.4))
        }
        path.closeSubpath()
        c.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
    }

    private static func drawPause(_ c: inout GraphicsContext, ink: Color) {
        c.fill(RoundedRectangle(cornerRadius: 1.2).path(in: CGRect(x: -5, y: -7, width: 3.2, height: 14)), with: .color(ink))
        c.fill(RoundedRectangle(cornerRadius: 1.2).path(in: CGRect(x: 1.8, y: -7, width: 3.2, height: 14)), with: .color(ink.opacity(0.75)))
    }

    private static func drawSentences(_ c: inout GraphicsContext, ink: Color) {
        for (i, w) in [14.0, 11.0, 8.0].enumerated() {
            let y = CGFloat(i) * 5 - 6
            c.fill(
                RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: -7, y: y, width: w, height: 2.2)),
                with: .color(ink.opacity(0.9 - Double(i) * 0.2))
            )
        }
        c.fill(Circle().path(in: CGRect(x: 4, y: 5, width: 2.5, height: 2.5)), with: .color(ink))
    }

    private static func drawNerves(_ c: inout GraphicsContext, ink: Color) {
        var pulse = Path()
        pulse.move(to: CGPoint(x: -9, y: 1))
        pulse.addLine(to: CGPoint(x: -4, y: 1))
        pulse.addLine(to: CGPoint(x: -2, y: -6))
        pulse.addLine(to: CGPoint(x: 1, y: 7))
        pulse.addLine(to: CGPoint(x: 3, y: -2))
        pulse.addLine(to: CGPoint(x: 5, y: 1))
        pulse.addLine(to: CGPoint(x: 9, y: 1))
        c.stroke(pulse, with: .color(ink), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
    }

    private static func drawImpromptu(_ c: inout GraphicsContext, ink: Color) {
        var bolt = Path()
        bolt.move(to: CGPoint(x: 2, y: -9))
        bolt.addLine(to: CGPoint(x: -4, y: 0))
        bolt.addLine(to: CGPoint(x: 1, y: 0))
        bolt.addLine(to: CGPoint(x: -2, y: 9))
        bolt.addLine(to: CGPoint(x: 5, y: -1))
        bolt.addLine(to: CGPoint(x: 0, y: -1))
        bolt.closeSubpath()
        c.fill(bolt, with: .color(ink.opacity(0.85)))
    }

    private static func drawStamina(_ c: inout GraphicsContext, ink: Color) {
        c.stroke(
            RoundedRectangle(cornerRadius: 3).path(in: CGRect(x: -9, y: -3, width: 18, height: 6)),
            with: .color(ink),
            lineWidth: 1.4
        )
        c.fill(
            RoundedRectangle(cornerRadius: 2).path(in: CGRect(x: -7.5, y: -1.6, width: 12, height: 3.2)),
            with: .color(ink.opacity(0.8))
        )
    }

    private static func drawCelebrate(_ c: inout GraphicsContext, ink: Color) {
        c.fill(
            RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: -5, y: -2, width: 10, height: 7)),
            with: .color(ink.opacity(0.85))
        )
        var cup = Path()
        cup.move(to: CGPoint(x: -5, y: -2))
        cup.addQuadCurve(to: CGPoint(x: 5, y: -2), control: CGPoint(x: 0, y: -9))
        c.stroke(cup, with: .color(ink), lineWidth: 1.5)
        c.fill(RoundedRectangle(cornerRadius: 0.8).path(in: CGRect(x: -2, y: 5, width: 4, height: 2.5)), with: .color(ink))
    }

    private static func drawVocal(_ c: inout GraphicsContext, ink: Color) {
        for (i, r) in [3.0, 5.5, 8.0].enumerated() {
            var arc = Path()
            arc.addArc(center: CGPoint(x: -3, y: 0), radius: r, startAngle: .degrees(-55), endAngle: .degrees(55), clockwise: false)
            c.stroke(arc, with: .color(ink.opacity(0.4 + Double(i) * 0.2)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        c.fill(Circle().path(in: CGRect(x: -6, y: -2.5, width: 5, height: 5)), with: .color(ink))
    }

    private static func drawVolume(_ c: inout GraphicsContext, ink: Color) {
        var cone = Path()
        cone.move(to: CGPoint(x: -6, y: -3))
        cone.addLine(to: CGPoint(x: -1, y: -7))
        cone.addLine(to: CGPoint(x: -1, y: 7))
        cone.addLine(to: CGPoint(x: -6, y: 3))
        cone.closeSubpath()
        c.fill(cone, with: .color(ink.opacity(0.85)))
        for r in [4.0, 7.0] {
            var arc = Path()
            arc.addArc(center: CGPoint(x: -1, y: 0), radius: r, startAngle: .degrees(-40), endAngle: .degrees(40), clockwise: false)
            c.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
    }

    private static func drawArticulation(_ c: inout GraphicsContext, ink: Color) {
        var mouth = Path()
        mouth.addEllipse(in: CGRect(x: -8, y: -5, width: 16, height: 10))
        c.stroke(mouth, with: .color(ink), lineWidth: 1.5)
        var teeth = Path()
        teeth.move(to: CGPoint(x: -5, y: 0))
        teeth.addLine(to: CGPoint(x: 5, y: 0))
        c.stroke(teeth, with: .color(ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 1.2]))
    }

    private static func drawEmphasis(_ c: inout GraphicsContext, ink: Color) {
        c.fill(
            RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: -8, y: -4, width: 16, height: 3)),
            with: .color(ink.opacity(0.55))
        )
        c.fill(
            RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: -5, y: 2, width: 10, height: 2.5)),
            with: .color(ink)
        )
        var mark = Path()
        mark.move(to: CGPoint(x: 6, y: -7))
        mark.addLine(to: CGPoint(x: 9, y: -2))
        c.stroke(mark, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    private static func drawRuleOfThree(_ c: inout GraphicsContext, ink: Color) {
        for i in 0..<3 {
            let x = CGFloat(i) * 7 - 7
            c.fill(Circle().path(in: CGRect(x: x - 2.4, y: -2.4, width: 4.8, height: 4.8)), with: .color(ink.opacity(0.55 + Double(i) * 0.15)))
        }
    }

    private static func drawProblemSolution(_ c: inout GraphicsContext, ink: Color) {
        c.stroke(
            RoundedRectangle(cornerRadius: 2).path(in: CGRect(x: -8, y: -7, width: 7, height: 7)),
            with: .color(ink),
            lineWidth: 1.4
        )
        var arrow = Path()
        arrow.move(to: CGPoint(x: -0.5, y: -3.5))
        arrow.addLine(to: CGPoint(x: 4, y: -3.5))
        arrow.addLine(to: CGPoint(x: 4, y: 2))
        c.stroke(arrow, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        c.fill(
            RoundedRectangle(cornerRadius: 2).path(in: CGRect(x: 1, y: 2, width: 7, height: 6)),
            with: .color(ink.opacity(0.8))
        )
    }

    private static func drawWhatSoWhat(_ c: inout GraphicsContext, ink: Color) {
        for i in 0..<3 {
            let w = 14.0 - Double(i) * 2.5
            let y = CGFloat(i) * 5 - 7
            c.fill(
                RoundedRectangle(cornerRadius: 1.5).path(in: CGRect(x: -w / 2, y: y, width: w, height: 3.5)),
                with: .color(ink.opacity(0.45 + Double(i) * 0.18))
            )
        }
    }

    private static func drawBridge(_ c: inout GraphicsContext, ink: Color) {
        var arch = Path()
        arch.move(to: CGPoint(x: -9, y: 6))
        arch.addQuadCurve(to: CGPoint(x: 9, y: 6), control: CGPoint(x: 0, y: -10))
        c.stroke(arch, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        c.stroke(
            Path { p in
                p.move(to: CGPoint(x: -9, y: 6))
                p.addLine(to: CGPoint(x: 9, y: 6))
            },
            with: .color(ink.opacity(0.5)),
            lineWidth: 1.2
        )
    }

    private static func drawStoryArc(_ c: inout GraphicsContext, ink: Color) {
        var arc = Path()
        arc.move(to: CGPoint(x: -9, y: 5))
        arc.addCurve(
            to: CGPoint(x: 9, y: 5),
            control1: CGPoint(x: -3, y: -8),
            control2: CGPoint(x: 4, y: -2)
        )
        c.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        c.fill(Circle().path(in: CGRect(x: -10, y: 3.5, width: 3, height: 3)), with: .color(ink))
        c.fill(Circle().path(in: CGRect(x: 7, y: 3.5, width: 3, height: 3)), with: .color(ink))
    }

    private static func drawHook(_ c: inout GraphicsContext, ink: Color) {
        var hook = Path()
        hook.move(to: CGPoint(x: 2, y: -8))
        hook.addLine(to: CGPoint(x: 2, y: 2))
        hook.addArc(center: CGPoint(x: -1, y: 2), radius: 3.5, startAngle: .degrees(0), endAngle: .degrees(200), clockwise: false)
        c.stroke(hook, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        c.fill(Circle().path(in: CGRect(x: 0.5, y: -9.5, width: 3, height: 3)), with: .color(ink))
    }

    private static func drawEmotion(_ c: inout GraphicsContext, ink: Color) {
        var heart = Path()
        heart.move(to: CGPoint(x: 0, y: 7))
        heart.addCurve(to: CGPoint(x: -8, y: -2), control1: CGPoint(x: -7, y: 3), control2: CGPoint(x: -8, y: 0))
        heart.addCurve(to: CGPoint(x: 0, y: -6), control1: CGPoint(x: -8, y: -6), control2: CGPoint(x: -3, y: -8))
        heart.addCurve(to: CGPoint(x: 8, y: -2), control1: CGPoint(x: 3, y: -8), control2: CGPoint(x: 8, y: -6))
        heart.addCurve(to: CGPoint(x: 0, y: 7), control1: CGPoint(x: 8, y: 0), control2: CGPoint(x: 7, y: 3))
        c.stroke(heart, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    private static func drawClosing(_ c: inout GraphicsContext, ink: Color) {
        var flag = Path()
        flag.move(to: CGPoint(x: -6, y: -8))
        flag.addLine(to: CGPoint(x: -6, y: 8))
        c.stroke(flag, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        var cloth = Path()
        cloth.move(to: CGPoint(x: -6, y: -8))
        cloth.addLine(to: CGPoint(x: 7, y: -5))
        cloth.addLine(to: CGPoint(x: -6, y: -1))
        cloth.closeSubpath()
        c.fill(cloth, with: .color(ink.opacity(0.85)))
    }

    private static func drawQA(_ c: inout GraphicsContext, ink: Color) {
        var q = Path()
        q.addArc(center: CGPoint(x: 0, y: -2), radius: 5.5, startAngle: .degrees(40), endAngle: .degrees(320), clockwise: false)
        c.stroke(q, with: .color(ink), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        c.fill(Circle().path(in: CGRect(x: -1.2, y: 5, width: 2.4, height: 2.4)), with: .color(ink))
        var stem = Path()
        stem.move(to: CGPoint(x: 0, y: 2))
        stem.addLine(to: CGPoint(x: 0, y: 4.2))
        c.stroke(stem, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    private static func drawElevator(_ c: inout GraphicsContext, ink: Color) {
        c.stroke(
            RoundedRectangle(cornerRadius: 2).path(in: CGRect(x: -6, y: -8, width: 12, height: 16)),
            with: .color(ink),
            lineWidth: 1.4
        )
        var up = Path()
        up.move(to: CGPoint(x: 0, y: 4))
        up.addLine(to: CGPoint(x: 0, y: -4))
        up.move(to: CGPoint(x: -3, y: -1))
        up.addLine(to: CGPoint(x: 0, y: -4))
        up.addLine(to: CGPoint(x: 3, y: -1))
        c.stroke(up, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    private static func drawTalk(_ c: inout GraphicsContext, ink: Color) {
        c.fill(
            RoundedRectangle(cornerRadius: 1.5).path(in: CGRect(x: -8, y: 4, width: 16, height: 2.5)),
            with: .color(ink.opacity(0.55))
        )
        var person = Path()
        person.addEllipse(in: CGRect(x: -2.5, y: -8, width: 5, height: 5))
        person.move(to: CGPoint(x: 0, y: -2.5))
        person.addLine(to: CGPoint(x: 0, y: 3))
        c.stroke(person, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    private static func drawGraduate(_ c: inout GraphicsContext, ink: Color) {
        var cap = Path()
        cap.move(to: CGPoint(x: 0, y: -7))
        cap.addLine(to: CGPoint(x: 8, y: -3))
        cap.addLine(to: CGPoint(x: 0, y: 1))
        cap.addLine(to: CGPoint(x: -8, y: -3))
        cap.closeSubpath()
        c.fill(cap, with: .color(ink.opacity(0.85)))
        var tassel = Path()
        tassel.move(to: CGPoint(x: 8, y: -3))
        tassel.addLine(to: CGPoint(x: 8, y: 5))
        c.stroke(tassel, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        c.fill(Circle().path(in: CGRect(x: 6.8, y: 4.5, width: 2.4, height: 2.4)), with: .color(ink))
    }

    private static func drawOpener(_ c: inout GraphicsContext, ink: Color) {
        var wave = Path()
        wave.move(to: CGPoint(x: -8, y: 2))
        wave.addQuadCurve(to: CGPoint(x: -2, y: 2), control: CGPoint(x: -5, y: -4))
        wave.addQuadCurve(to: CGPoint(x: 4, y: 2), control: CGPoint(x: 1, y: 7))
        wave.addQuadCurve(to: CGPoint(x: 9, y: 0), control: CGPoint(x: 7, y: -3))
        c.stroke(wave, with: .color(ink), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        c.fill(Circle().path(in: CGRect(x: -9.5, y: -1, width: 3, height: 3)), with: .color(ink))
    }

    private static func drawKeepGoing(_ c: inout GraphicsContext, ink: Color) {
        for i in 0..<3 {
            let x = CGFloat(i) * 6 - 6
            c.stroke(
                RoundedRectangle(cornerRadius: 2).path(in: CGRect(x: x - 2.5, y: -3, width: 5, height: 6)),
                with: .color(ink.opacity(0.55 + Double(i) * 0.15)),
                lineWidth: 1.3
            )
        }
    }

    private static func drawRoom(_ c: inout GraphicsContext, ink: Color) {
        let spots: [(CGFloat, CGFloat)] = [(-6, -4), (0, -6), (6, -4), (-4, 4), (4, 4)]
        for (i, spot) in spots.enumerated() {
            c.fill(
                Circle().path(in: CGRect(x: spot.0 - 2, y: spot.1 - 2, width: 4, height: 4)),
                with: .color(ink.opacity(i == 2 ? 1 : 0.55))
            )
        }
    }

    private static func drawConversation(_ c: inout GraphicsContext, ink: Color) {
        c.stroke(
            RoundedRectangle(cornerRadius: 3).path(in: CGRect(x: -9, y: -7, width: 10, height: 7)),
            with: .color(ink),
            lineWidth: 1.4
        )
        c.fill(
            RoundedRectangle(cornerRadius: 3).path(in: CGRect(x: -1, y: 0, width: 10, height: 7)),
            with: .color(ink.opacity(0.75))
        )
    }
}
