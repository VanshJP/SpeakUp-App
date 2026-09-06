import SwiftUI

// MARK: - Canvas Look

/// The one catalogue of background art, shared by both menus that paint it:
/// `AppCanvas` (Settings → App Look, behind every tab) and `RecordingBackdrop`
/// (Recording Look, behind the countdown and the take).
///
/// Aurora means the same Aurora on both screens because there is exactly one
/// painter per look. The two menus used to carry private copies — an
/// `AppAuroraCanvas` and an `AuroraCanvas`, an `AppEmberCanvas` and an
/// `EmberCanvas`, an `AppHorizonCanvas` and a `VoidCanvas` — which drifted
/// apart the moment either was touched.
///
/// **Not persisted.** The two menus own the stored raw values; this is a
/// render key, so cases here can be added, renamed or reordered freely, and
/// either menu can grow into a look the other already has by adding one case.
nonisolated enum CanvasLook: CaseIterable, Hashable, Sendable {
    case classic
    case midnight
    case mist
    case aurora
    case ember
    case horizon
    case prism
    case depth
    case hyperspace
    case nebula
    case void

    /// One sentence, so a look is described the same way wherever it is offered.
    var summary: String {
        switch self {
        case .classic: return "Deep navy with soft teal and indigo light"
        case .midnight: return "Near-black field, quieter glow"
        case .mist: return "Cool fog drifting across graphite"
        case .aurora: return "Slow teal-to-violet curtains"
        case .ember: return "Warm copper well with rising sparks"
        case .horizon: return "Stars settling onto a lit horizon"
        case .prism: return "Angled light beams across navy"
        case .depth: return "Concentric wells sinking into the canvas"
        case .hyperspace: return "Warp streaks from a vanishing point"
        case .nebula: return "Colour clouds behind a dust lane"
        case .void: return "Near-black sky over a thin teal line"
        }
    }

    /// Classic and Midnight have nothing moving, so their clock never starts.
    var isAnimated: Bool {
        switch self {
        case .classic, .midnight: return false
        default: return true
        }
    }
}

// MARK: - Mood

/// How hard a look pushes. The app canvas sits behind text all day; a session
/// canvas *is* the screen. One knob, so a look never needs a second painter.
nonisolated enum CanvasMood: Sendable {
    /// Behind the tabs: dimmer light, fewer particles, slower drift.
    case ambient
    /// Behind a take: full intensity.
    case session

    var gain: Double { self == .session ? 1.0 : 0.74 }
    var density: Double { self == .session ? 1.0 : 0.6 }
    var pace: Double { self == .session ? 1.0 : 0.8 }

    /// Session canvases get the faster clock: they are what the user is
    /// looking at, and Hyperspace's streaks visibly step below 20 fps.
    var frameInterval: Double { self == .session ? 1.0 / 20.0 : 1.0 / 10.0 }
}

// MARK: - Paint

extension CanvasLook {
    /// Draws the whole look in **one `Canvas` pass**.
    ///
    /// Everything here goes through the primitives at the bottom of this file,
    /// so a background is never a stack of `RadialGradient` views flattened by
    /// `.drawingGroup`. That flattening cost an offscreen texture allocation
    /// on every screen appearance — the beat of empty canvas on a push — plus
    /// a re-rasterization every tick, once per screen still alive in the
    /// navigation stack. A `Canvas` already *is* the flattened layer Liquid
    /// Glass samples.
    ///
    /// All geometry is normalised against the view's diagonal. That makes a
    /// 76pt picker tile a true miniature of the full screen rather than a
    /// close-up crop, and makes two stacked full-screen backgrounds paint
    /// identical pixels, so a push no longer slides one composition over a
    /// different one.
    func paint(
        into g: inout GraphicsContext,
        size: CGSize,
        mood: CanvasMood,
        tone: AppBackground.Style = .primary,
        time: TimeInterval
    ) {
        guard size.width > 1, size.height > 1 else { return }
        let f = CanvasFrame(size: size, mood: mood, time: time * mood.pace)

        switch self {
        case .classic: paintClassic(&g, f, tone)
        case .midnight: paintMidnight(&g, f, tone)
        case .mist: paintMist(&g, f)
        case .aurora: paintAurora(&g, f)
        case .ember: paintEmber(&g, f)
        case .horizon: paintHorizon(&g, f)
        case .prism: paintPrism(&g, f)
        case .depth: paintDepth(&g, f)
        case .hyperspace: paintHyperspace(&g, f)
        case .nebula: paintNebula(&g, f)
        case .void: paintVoid(&g, f)
        }
    }
}

/// Everything a painter needs, resolved once: the canvas box, the mood knobs,
/// and the clock. Passing this instead of `(size, mood, time)` is what keeps
/// the painters below readable.
private struct CanvasFrame {
    let size: CGSize
    let mood: CanvasMood
    let time: TimeInterval

    /// Diagonal — the unit every radius is expressed in.
    var d: CGFloat { hypot(size.width, size.height) }

    /// Pixel scale, so a 1pt star on a 76pt tile is not a 1pt star on a phone.
    var unit: CGFloat { max(max(size.width, size.height) / 420, 0.35) }

    /// Point at a normalised position.
    func at(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: size.width * x, y: size.height * y)
    }

    /// Particle count for this mood, never below a handful.
    func count(_ full: Int) -> Int { max(6, Int(Double(full) * mood.density)) }

    /// Glow intensity for this mood.
    func gain(_ full: Double) -> Double { full * mood.gain }
}

// MARK: - Painters

// MARK: Classic

/// The default: deep navy, teal high light, indigo counterweight. Tone only
/// nudges the wash — `.subtle` sits a hair above `.primary` so a pushed detail
/// view does not pop, `.recording` drops darker and pushes the teal.
private func paintClassic(_ g: inout GraphicsContext, _ f: CanvasFrame, _ tone: AppBackground.Style) {
    let lift: Double
    let teal: Double
    switch tone {
    case .primary: lift = 0; teal = 1
    case .subtle: lift = 0.006; teal = 0.9
    case .recording: lift = -0.014; teal = 1.45
    }

    canvasWash(&g, f.size, [
        Color(red: 0.052 + lift, green: 0.070 + lift, blue: 0.158 + lift),
        Color(red: 0.030 + lift, green: 0.044 + lift, blue: 0.102 + lift),
        Color(red: 0.028 + lift, green: 0.030 + lift, blue: 0.072 + lift)
    ], from: .topLeading, to: .bottomTrailing)

    g.blendMode = .plusLighter
    canvasGlow(&g, AppColors.categoryBrandBright, at: f.at(0.88, 0.06),
               radius: f.d * 0.46, intensity: 0.30 * teal, stretch: 1.25, angle: .degrees(-18))
    canvasGlow(&g, canvasViolet, at: f.at(0.08, 0.88),
               radius: f.d * 0.42, intensity: 0.26, stretch: 1.3, angle: .degrees(14))
    canvasGlow(&g, AppColors.primary, at: f.at(0.52, 0.44),
               radius: f.d * 0.52, intensity: 0.13 * teal, stretch: 1.15)
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.30)
}

// MARK: Midnight

private func paintMidnight(_ g: inout GraphicsContext, _ f: CanvasFrame, _ tone: AppBackground.Style) {
    let lift: Double
    switch tone {
    case .primary: lift = 0
    case .subtle: lift = 0.005
    case .recording: lift = -0.006
    }

    canvasWash(&g, f.size, [
        Color(red: 0.030 + lift, green: 0.035 + lift, blue: 0.078 + lift),
        Color(red: 0.016 + lift, green: 0.020 + lift, blue: 0.048 + lift),
        Color(red: 0.008 + lift, green: 0.010 + lift, blue: 0.026 + lift)
    ])

    g.blendMode = .plusLighter
    canvasGlow(&g, AppColors.primary, at: f.at(0.80, 0.10),
               radius: f.d * 0.40, intensity: 0.16, stretch: 1.3)
    canvasGlow(&g, canvasViolet.opacity(0.9), at: f.at(0.16, 0.84),
               radius: f.d * 0.38, intensity: 0.14, stretch: 1.2)
    // Frozen: Midnight is the one look that never moves.
    canvasStars(&g, count: 26, f, time: 0, brightness: 0.35)
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.40)
}

// MARK: Mist

/// Fog banks, not blobs: every glow is stretched flat and drifts sideways, so
/// the field reads as weather crossing graphite rather than orbs orbiting.
private func paintMist(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.048, green: 0.058, blue: 0.086),
        Color(red: 0.030, green: 0.038, blue: 0.062),
        Color(red: 0.020, green: 0.026, blue: 0.044)
    ])

    g.blendMode = .plusLighter
    let banks: [(y: Double, speed: Double, span: Double, strength: Double, color: Color)] = [
        (0.20, 0.014, 0.44, 0.24, Color(red: 0.42, green: 0.60, blue: 0.72)),
        (0.46, 0.010, 0.52, 0.20, Color(red: 0.26, green: 0.44, blue: 0.62)),
        (0.72, 0.017, 0.46, 0.22, AppColors.primary),
        (0.90, 0.008, 0.38, 0.16, Color(red: 0.52, green: 0.62, blue: 0.78))
    ]
    for (i, bank) in banks.enumerated() {
        let phase = f.time * bank.speed * 2 * .pi + Double(i) * 1.7
        canvasGlow(&g, bank.color,
                   at: f.at(0.5 + 0.62 * sin(phase), bank.y + 0.03 * sin(f.time * 0.05 + Double(i))),
                   radius: f.d * bank.span,
                   intensity: f.gain(bank.strength),
                   stretch: 2.6,
                   angle: .degrees(-6 + Double(i) * 4))
    }
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.34)
}

// MARK: Aurora

/// Folded curtains over a star field. Each ribbon carries two harmonics so it
/// folds instead of waving as one rigid rope, and a lit leading edge — that
/// rim is what makes it read as sky. Replaced a `MeshGradient` under a second
/// `Canvas` of flat strokes.
private func paintAurora(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.016, green: 0.046, blue: 0.084),
        Color(red: 0.012, green: 0.028, blue: 0.062),
        Color(red: 0.028, green: 0.018, blue: 0.052)
    ])

    g.blendMode = .plusLighter
    canvasStars(&g, count: f.count(54), f, time: f.time, heightFraction: 0.52, brightness: 0.6)

    canvasGlow(&g, AppColors.primary, at: f.at(0.26, 0.26),
               radius: f.d * 0.52, intensity: f.gain(0.24), stretch: 1.5)
    canvasGlow(&g, canvasViolet, at: f.at(0.80, 0.56),
               radius: f.d * 0.48, intensity: f.gain(0.22), stretch: 1.4)
    canvasGlow(&g, AppColors.categoryBrandBright, at: f.at(0.5, 0.94),
               radius: f.d * 0.42, intensity: f.gain(0.14), stretch: 2.2)

    let curtains: [(top: Double, height: Double, speed: Double, offset: Double,
                    frequency: Double, amplitude: Double, head: Color, tail: Color, strength: Double)] = [
        (0.20, 0.44, 0.20, 0.0, 1.2, 0.055, AppColors.categoryBrandBright, AppColors.primary, 0.44),
        (0.33, 0.40, 0.15, 1.9, 1.7, 0.044, canvasViolet, canvasDeepViolet, 0.38),
        (0.48, 0.34, 0.24, 3.6, 0.9, 0.036, canvasMint, AppColors.primary, 0.30),
        (0.62, 0.28, 0.12, 5.2, 1.4, 0.026, AppColors.primary, canvasDeepTeal, 0.24)
    ]
    // Ambient drops the two quietest ribbons rather than dimming all four —
    // fewer, cleaner folds behind body text.
    let visible = f.mood == .session ? curtains : Array(curtains.prefix(2))
    for c in visible {
        canvasCurtain(&g, f.size, top: c.top, height: c.height,
                      phase: f.time * c.speed + c.offset,
                      frequency: c.frequency, amplitude: c.amplitude,
                      head: c.head, tail: c.tail, intensity: f.gain(c.strength))
    }
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.35)
}

// MARK: Ember

/// Warm on purpose — every other look lives in teal and violet, so this one is
/// the odd heat. A three-stage well at the bottom, sparks climbing out of it,
/// and a single teal counterweight so it does not read as an alert.
private func paintEmber(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.038, green: 0.022, blue: 0.030),
        Color(red: 0.062, green: 0.024, blue: 0.020),
        Color(red: 0.110, green: 0.036, blue: 0.016)
    ])

    g.blendMode = .plusLighter
    let breath = 1 + 0.07 * sin(f.time * 0.28)
    canvasGlow(&g, Color(red: 0.92, green: 0.34, blue: 0.12), at: f.at(0.5, 1.05),
               radius: f.d * 0.70 * breath, intensity: f.gain(0.52), stretch: 1.5)
    canvasGlow(&g, Color(red: 1.0, green: 0.66, blue: 0.26), at: f.at(0.5, 1.02),
               radius: f.d * 0.34 * breath, intensity: f.gain(0.42), stretch: 1.8)
    canvasGlow(&g, Color(red: 1.0, green: 0.88, blue: 0.58), at: f.at(0.5, 1.0),
               radius: f.d * 0.14 * breath, intensity: f.gain(0.30), stretch: 2.2)
    canvasGlow(&g, AppColors.primary, at: f.at(0.74, 0.12),
               radius: f.d * 0.40, intensity: f.gain(0.20), stretch: 1.2)

    canvasSparks(&g, f, count: f.count(44), rise: 0.88, speed: 0.10)
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.40, center: UnitPoint(x: 0.5, y: 0.88))
}

// MARK: Horizon

/// Sky meeting ground: a graded field, a bloom sitting on the line, and a
/// ground wash that darkens away from it so type below stays readable.
private func paintHorizon(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    let y = f.size.height * 0.72

    canvasWash(&g, f.size, [
        Color(red: 0.014, green: 0.018, blue: 0.042),
        Color(red: 0.020, green: 0.030, blue: 0.058),
        Color(red: 0.008, green: 0.012, blue: 0.026)
    ])

    g.blendMode = .plusLighter
    canvasStars(&g, count: f.count(46), f, time: f.time, heightFraction: 0.68, brightness: 0.85)
    canvasHorizonLine(&g, f, y: y, bloom: 0.30 + 0.08 * sin(f.time * 0.35), spread: 0.44)
    g.blendMode = .normal

    canvasGround(&g, f, y: y, depth: 0.55)
    canvasVignette(&g, f.size, strength: 0.30, center: UnitPoint(x: 0.5, y: 0.55))
}

// MARK: Void

/// Horizon's quiet sibling: no graded sky, a fainter line, more stars. The
/// option for anyone who wants the frame spent on the waveform, not the sky.
private func paintVoid(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    let y = f.size.height * 0.72

    canvasWash(&g, f.size, [
        Color(red: 0.014, green: 0.018, blue: 0.040),
        Color(red: 0.010, green: 0.014, blue: 0.032),
        Color(red: 0.004, green: 0.006, blue: 0.016)
    ])

    g.blendMode = .plusLighter
    // A faint band across the sky so the stars have somewhere to belong.
    canvasGlow(&g, Color(red: 0.34, green: 0.40, blue: 0.66), at: f.at(0.56, 0.30),
               radius: f.d * 0.46, intensity: f.gain(0.13), stretch: 2.4, angle: .degrees(-24))
    canvasStars(&g, count: f.count(70), f, time: f.time, heightFraction: 0.70, brightness: 1.0)
    canvasHorizonLine(&g, f, y: y, bloom: 0.34 + 0.08 * sin(f.time * 0.4), spread: 0.40)
    g.blendMode = .normal

    canvasGround(&g, f, y: y, depth: 0.60)
    canvasVignette(&g, f.size, strength: 0.34, center: UnitPoint(x: 0.5, y: 0.6))
}

// MARK: Prism

/// Angled beams. A rotated, stretched glow is soft on both axes in one fill —
/// the old build drew hard polygons and paid for a `.blur(radius: 12)` on the
/// whole layer just to hide their edges.
private func paintPrism(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.044, green: 0.056, blue: 0.130),
        Color(red: 0.028, green: 0.034, blue: 0.082),
        Color(red: 0.020, green: 0.022, blue: 0.052)
    ], from: .topLeading, to: .bottomTrailing)

    g.blendMode = .plusLighter
    let beams: [(x: Double, y: Double, angle: Double, strength: Double, color: Color)] = [
        (0.18, 0.18, -58, 0.30, AppColors.categoryBrandBright),
        (0.44, 0.36, -52, 0.24, canvasViolet),
        (0.68, 0.24, -64, 0.22, AppColors.primary),
        (0.88, 0.62, -50, 0.20, Color(red: 0.30, green: 0.52, blue: 0.86))
    ]
    for (i, beam) in beams.enumerated() {
        let slide = 0.05 * sin(f.time * 0.13 + Double(i) * 1.3)
        let breathe = 1 + 0.10 * sin(f.time * 0.19 + Double(i))
        canvasGlow(&g, beam.color,
                   at: f.at(beam.x + slide, beam.y + slide * 0.6),
                   radius: f.d * 0.30 * breathe,
                   intensity: f.gain(beam.strength),
                   stretch: 3.4,
                   angle: .degrees(beam.angle))
    }
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.34)
}

// MARK: Depth

/// Concentric wells. Rings fade outward and breathe together, so the canvas
/// has a centre without a single bright object competing with the cards.
private func paintDepth(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    let center = f.at(0.5, 0.40)
    let breathe = 1 + 0.05 * sin(f.time * 0.22)

    canvasWash(&g, f.size, [
        Color(red: 0.026, green: 0.032, blue: 0.070),
        Color(red: 0.016, green: 0.020, blue: 0.048),
        Color(red: 0.010, green: 0.012, blue: 0.030)
    ])

    g.blendMode = .plusLighter
    canvasGlow(&g, AppColors.primary, at: center, radius: f.d * 0.34, intensity: f.gain(0.26))
    canvasGlow(&g, canvasViolet, at: f.at(0.5, 0.86),
               radius: f.d * 0.40, intensity: f.gain(0.16), stretch: 1.6)

    for ring in 0..<6 {
        let r = f.d * (0.10 + Double(ring) * 0.10) * breathe
        let fade = 1 - Double(ring) / 6.5
        g.stroke(
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    AppColors.categoryBrandBright.opacity(0.30 * fade),
                    Color.white.opacity(0.10 * fade)
                ]),
                center: center, startRadius: r * 0.6, endRadius: r * 1.2
            ),
            lineWidth: 1
        )
    }
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.42, center: UnitPoint(x: 0.5, y: 0.40))
}

// MARK: Hyperspace

/// Warp streaks from a vanishing point. Depth wraps 0...1 so stars recycle
/// instead of allocating, and squaring it makes them accelerate as they leave
/// the centre — the whole point of a jump. Each streak is a gradient stroke
/// with a bright head and a tail that fades to nothing; a flat line reads as a
/// scratch on the glass.
private func paintHyperspace(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    let center = f.at(0.5, 0.42)
    let maxR = f.d * 0.62

    canvasWash(&g, f.size, [
        Color(red: 0.012, green: 0.018, blue: 0.052),
        Color(red: 0.008, green: 0.010, blue: 0.030),
        Color(red: 0.004, green: 0.006, blue: 0.020)
    ])

    g.blendMode = .plusLighter
    // A well at the vanishing point, so streaks are born out of light rather
    // than appearing from flat black.
    canvasGlow(&g, AppColors.primary, at: center, radius: maxR * 0.34, intensity: f.gain(0.34))
    canvasGlow(&g, canvasViolet, at: center, radius: maxR * 0.70, intensity: f.gain(0.12))

    for i in 0..<f.count(84) {
        let angle = canvasHash(i, 1) * .pi * 2
        let speed = 0.14 + canvasHash(i, 2) * 0.72
        let eased = pow(canvasFract(canvasHash(i, 3) + f.time * speed), 2)
        let dx = CGFloat(cos(angle))
        let dy = CGFloat(sin(angle))
        let head = CGPoint(x: center.x + dx * (maxR * 0.03 + eased * maxR),
                           y: center.y + dy * (maxR * 0.03 + eased * maxR))
        let streak = f.unit * (6 + eased * (48 + speed * 40))
        let tail = CGPoint(x: head.x - dx * streak, y: head.y - dy * streak)

        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)

        let tint = canvasHash(i, 4)
        let color: Color = tint > 0.86
            ? AppColors.categoryBrandBright
            : (tint < 0.10 ? Color(red: 0.72, green: 0.66, blue: 1.0) : .white)

        g.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [.clear, color.opacity(f.gain(0.10 + 0.85 * eased))]),
                startPoint: tail, endPoint: head
            ),
            style: StrokeStyle(lineWidth: f.unit * (0.7 + eased * 2.0), lineCap: .round)
        )
    }
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.46, center: UnitPoint(x: 0.5, y: 0.42))
}

// MARK: Nebula

/// Five additive clouds orbiting slowly, two hot cores, a dark dust lane
/// cutting across them, and star layers front and back.
///
/// The dust lane is the only *subtractive* mark on any canvas, and it is what
/// makes this read as a nebula rather than as overlapping orbs. The old build
/// had four fixed-radius orbs and no lane: at 76pt the picker tile was one
/// flat smear, and at full screen the clouds landed wherever the safe area put
/// them, so the tile and the live session showed different pictures.
private func paintNebula(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.052, green: 0.024, blue: 0.078),
        Color(red: 0.026, green: 0.016, blue: 0.058),
        Color(red: 0.010, green: 0.010, blue: 0.032)
    ], from: .topLeading, to: .bottomTrailing)

    g.blendMode = .plusLighter
    // Deep field first, so the clouds read as being in front of the stars.
    canvasStars(&g, count: f.count(40), f, time: f.time, brightness: 0.45, seed: 11)

    let clouds: [(x: Double, y: Double, speed: Double, span: Double,
                  strength: Double, angle: Double, color: Color)] = [
        (0.30, 0.30, 0.055, 0.62, 0.40, -22, Color(red: 0.58, green: 0.22, blue: 0.86)),
        (0.72, 0.26, 0.041, 0.54, 0.34, 28, AppColors.primary),
        (0.52, 0.70, 0.033, 0.70, 0.32, 12, Color(red: 0.14, green: 0.34, blue: 0.72)),
        (0.18, 0.78, 0.062, 0.46, 0.30, -36, Color(red: 0.86, green: 0.26, blue: 0.48)),
        (0.86, 0.80, 0.047, 0.40, 0.24, 44, canvasMint)
    ]
    for (i, cloud) in clouds.enumerated() {
        let phase = f.time * cloud.speed * 2 * .pi + Double(i) * 1.3
        canvasGlow(&g, cloud.color,
                   at: f.at(cloud.x + 0.05 * sin(phase), cloud.y + 0.035 * cos(phase * 0.8)),
                   radius: f.d * cloud.span,
                   intensity: f.gain(cloud.strength),
                   stretch: 1.45,
                   angle: .degrees(cloud.angle + 6 * sin(phase * 0.5)))
    }

    // Hot cores: small, bright, slow. Without them a nebula is just fog.
    canvasGlow(&g, Color(red: 1.0, green: 0.86, blue: 0.96),
               at: f.at(0.34 + 0.02 * sin(f.time * 0.07), 0.34),
               radius: f.d * 0.10, intensity: f.gain(0.34))
    canvasGlow(&g, Color(red: 0.80, green: 0.94, blue: 1.0),
               at: f.at(0.70, 0.62 + 0.02 * cos(f.time * 0.06)),
               radius: f.d * 0.07, intensity: f.gain(0.26))
    g.blendMode = .normal

    canvasGlow(&g, Color(red: 0.03, green: 0.01, blue: 0.05),
               at: f.at(0.48 + 0.02 * sin(f.time * 0.04), 0.50),
               radius: f.d * 0.44, intensity: 0.72, stretch: 1.9, angle: .degrees(-34))

    g.blendMode = .plusLighter
    canvasStars(&g, count: f.count(46), f, time: f.time, brightness: 0.9)
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.42)
}

// MARK: - Shared marks
//
// Horizon and Void differ in sky and star density, not in how the line is
// built — one function, so the two can never drift apart the way the old
// `AppHorizonCanvas` and `VoidCanvas` did.

/// Lit horizon: a bloom sitting on the line, an off-centre hotspot, and a
/// one-point stroke. Expects an additive blend mode.
private func canvasHorizonLine(
    _ g: inout GraphicsContext,
    _ f: CanvasFrame,
    y: CGFloat,
    bloom: Double,
    spread: Double
) {
    canvasGlow(&g, AppColors.primary, at: CGPoint(x: f.size.width * 0.5, y: y),
               radius: f.d * spread, intensity: f.gain(bloom), stretch: 2.3)
    canvasGlow(&g, AppColors.categoryBrandBright, at: CGPoint(x: f.size.width * 0.40, y: y),
               radius: f.d * 0.17, intensity: f.gain(bloom * 0.85), stretch: 2.8)

    var line = Path()
    line.move(to: CGPoint(x: 0, y: y))
    line.addLine(to: CGPoint(x: f.size.width, y: y))
    g.stroke(line, with: .linearGradient(
        Gradient(colors: [
            .clear,
            AppColors.categoryBrandBright.opacity(0.75),
            AppColors.primary.opacity(0.55),
            .clear
        ]),
        startPoint: CGPoint(x: 0, y: y),
        endPoint: CGPoint(x: f.size.width, y: y)
    ), lineWidth: 1)
}

/// Ground below the horizon, darkening away from the line so type stays legible.
private func canvasGround(_ g: inout GraphicsContext, _ f: CanvasFrame, y: CGFloat, depth: Double) {
    g.fill(
        Path(CGRect(x: 0, y: y, width: f.size.width, height: f.size.height - y)),
        with: .linearGradient(
            Gradient(colors: [.clear, Color.black.opacity(depth)]),
            startPoint: CGPoint(x: f.size.width / 2, y: y),
            endPoint: CGPoint(x: f.size.width / 2, y: f.size.height)
        )
    )
}

// MARK: - Shared tones
//
// Named once so two looks reaching for "the violet" get the same violet.
// Anything with a semantic meaning still comes from `AppColors`.

private let canvasViolet = Color(red: 0.46, green: 0.28, blue: 0.90)
private let canvasDeepViolet = Color(red: 0.24, green: 0.18, blue: 0.62)
private let canvasMint = Color(red: 0.30, green: 0.92, blue: 0.78)
private let canvasDeepTeal = Color(red: 0.08, green: 0.26, blue: 0.40)

// MARK: - Primitives
//
// Every painter above draws through these, so a background is ONE `Canvas`
// pass. No `GeometryReader` per orb, no `.blendMode` / `.blur` view modifier
// (each forces an offscreen compositing group), no `.drawingGroup`. Setting
// `blendMode` on a `GraphicsContext`, and transforming a *copy* of it, are
// state changes — they cost nothing and allocate nothing.

/// Full-bleed linear wash. The base layer of every look.
private func canvasWash(
    _ g: inout GraphicsContext,
    _ size: CGSize,
    _ colors: [Color],
    from: UnitPoint = .top,
    to: UnitPoint = .bottom
) {
    g.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .linearGradient(
            Gradient(colors: colors),
            startPoint: CGPoint(x: size.width * from.x, y: size.height * from.y),
            endPoint: CGPoint(x: size.width * to.x, y: size.height * to.y)
        )
    )
}

/// Soft light blob — the workhorse. `stretch` and `angle` turn it into a fog
/// bank, a beam, a horizon bloom or a dust lane without a second draw.
private func canvasGlow(
    _ g: inout GraphicsContext,
    _ color: Color,
    at center: CGPoint,
    radius: CGFloat,
    intensity: Double,
    stretch: CGFloat = 1,
    angle: Angle = .zero
) {
    guard radius > 0.5, intensity > 0.004 else { return }

    var layer = g
    layer.translateBy(x: center.x, y: center.y)
    if angle != .zero { layer.rotate(by: angle) }
    if stretch != 1 { layer.scaleBy(x: stretch, y: 1) }

    layer.fill(
        Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
        with: .radialGradient(
            Gradient(stops: [
                .init(color: color.opacity(intensity), location: 0),
                .init(color: color.opacity(intensity * 0.58), location: 0.26),
                .init(color: color.opacity(intensity * 0.22), location: 0.54),
                .init(color: color.opacity(intensity * 0.05), location: 0.80),
                .init(color: .clear, location: 1)
            ]),
            center: .zero, startRadius: 0, endRadius: radius
        )
    )
}

/// Deterministic star field. Index `i` always lands in the same place, so the
/// timeline stays stateless and stars never jump between frames or screens.
private func canvasStars(
    _ g: inout GraphicsContext,
    count: Int,
    _ f: CanvasFrame,
    time: TimeInterval,
    heightFraction: Double = 1,
    brightness: Double = 1,
    seed: Double = 0
) {
    for i in 0..<count {
        let twinkle = 0.42 + 0.58 * sin(time * (0.4 + canvasHash(i, 3 + seed) * 1.3) + Double(i))
        let alpha = brightness * (0.16 + 0.62 * canvasHash(i, 5 + seed)) * twinkle
        guard alpha > 0.012 else { continue }
        let x = canvasHash(i, 1 + seed) * f.size.width
        let y = canvasHash(i, 2 + seed) * f.size.height * heightFraction
        let r = (0.5 + canvasHash(i, 4 + seed) * 1.4) * f.unit
        g.fill(
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
            with: .color(.white.opacity(min(alpha, 1)))
        )
    }
}

/// Embers rising out of a well. Life wraps 0...1 so sparks recycle rather than
/// being allocated, and sway grows with height — a spark leaving the heat
/// wanders more than one still in it.
private func canvasSparks(
    _ g: inout GraphicsContext,
    _ f: CanvasFrame,
    count: Int,
    rise: Double,
    speed: Double
) {
    for i in 0..<count {
        let life = canvasFract(canvasHash(i, 3) + f.time * (speed + canvasHash(i, 2) * speed * 1.6))
        let fade = 1 - life
        guard fade > 0.02 else { continue }
        let sway = sin(f.time * 0.5 + Double(i) * 2.3) * life * 0.05
        let x = f.size.width * (0.18 + canvasHash(i, 1) * 0.64 + sway)
        let y = f.size.height * (1.04 - life * rise)
        let w = (1.0 + canvasHash(i, 4) * 1.4) * f.unit
        let h = w * (1.5 + life * 2.2)
        let color = canvasHash(i, 5) > 0.68
            ? Color(red: 1.0, green: 0.76, blue: 0.36)
            : Color(red: 0.95, green: 0.42, blue: 0.16)
        g.fill(
            Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)),
            with: .color(color.opacity(0.85 * fade * fade))
        )
    }
}

/// Aurora ribbon: a sine top edge with two harmonics, a body gradient falling
/// to nothing, and a bright rim on the leading edge.
private func canvasCurtain(
    _ g: inout GraphicsContext,
    _ size: CGSize,
    top: Double,
    height: Double,
    phase: Double,
    frequency: Double,
    amplitude: Double,
    head: Color,
    tail: Color,
    intensity: Double
) {
    let steps = 26
    let topY = size.height * top
    let drop = size.height * height
    let amp = size.height * amplitude

    var edge: [CGPoint] = []
    edge.reserveCapacity(steps + 1)
    for i in 0...steps {
        let t = Double(i) / Double(steps)
        let y = topY
            + CGFloat(sin(t * frequency * 2 * .pi + phase)) * amp
            + CGFloat(sin(t * frequency * 0.55 * 2 * .pi - phase * 0.7)) * amp * 0.45
        edge.append(CGPoint(x: CGFloat(t) * size.width, y: y))
    }

    var body = Path()
    body.move(to: edge[0])
    for point in edge.dropFirst() { body.addLine(to: point) }
    for point in edge.reversed() { body.addLine(to: CGPoint(x: point.x, y: point.y + drop)) }
    body.closeSubpath()

    g.fill(body, with: .linearGradient(
        Gradient(stops: [
            .init(color: head.opacity(intensity), location: 0),
            .init(color: tail.opacity(intensity * 0.5), location: 0.42),
            .init(color: .clear, location: 1)
        ]),
        startPoint: CGPoint(x: size.width / 2, y: topY - amp),
        endPoint: CGPoint(x: size.width / 2, y: topY + drop)
    ))

    var rim = Path()
    rim.move(to: edge[0])
    for point in edge.dropFirst() { rim.addLine(to: point) }
    g.stroke(rim, with: .color(head.opacity(min(intensity * 2.2, 0.9))),
             style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
}

/// Darkens the edges so glass cards keep their contrast wherever they scroll.
private func canvasVignette(
    _ g: inout GraphicsContext,
    _ size: CGSize,
    strength: Double,
    center: UnitPoint = UnitPoint(x: 0.5, y: 0.45)
) {
    guard strength > 0.01 else { return }
    g.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .radialGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Color.black.opacity(strength * 0.30), location: 0.60),
                .init(color: Color.black.opacity(strength), location: 1)
            ]),
            center: CGPoint(x: size.width * center.x, y: size.height * center.y),
            startRadius: 0,
            endRadius: hypot(size.width, size.height) * 0.74
        )
    )
}

/// Cheap hash for particle fields. Same index always yields the same 0...1, so
/// a `TimelineView` can stay stateless.
private func canvasHash(_ i: Int, _ salt: Double) -> Double {
    canvasFract(sin(Double(i) * 127.139 + salt * 311.7) * 43758.5453123)
}

private func canvasFract(_ x: Double) -> Double { x - floor(x) }
