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
///
/// Every look is a still. Motion behind every tab was burning frames for
/// wallpaper the eye stops noticing after a day, and a tab switch restarted
/// the clock. Intensity still differs by mood (`.ambient` vs `.session`).
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
    case tide
    case dusk
    case signal
    case noir

    /// One sentence, so a look is described the same way wherever it is offered.
    var summary: String {
        switch self {
        case .classic: return "Deep navy with soft teal light"
        case .midnight: return "Near-black field, quieter glow"
        case .mist: return "Cool fog banks across graphite"
        case .aurora: return "Polar curtains of teal and violet light"
        case .ember: return "Warm copper well with sparks"
        case .horizon: return "Stars above a lit horizon"
        case .prism: return "Angled light beams across navy"
        case .depth: return "Concentric wells sinking into the canvas"
        case .hyperspace: return "Warp streaks from a vanishing point"
        case .nebula: return "Colour clouds behind a dust lane"
        case .void: return "Near-black sky over a thin teal line"
        case .tide: return "Layered teal bands rising from below"
        case .dusk: return "Warm amber meeting cool teal"
        case .signal: return "Soft waveform ribbons across navy"
        case .noir: return "Near-black with one teal slash"
        }
    }

    /// Kept for menu / test callers. Every look is a still now — motion behind
    /// tabs cost frames and restarted on every switch.
    var isAnimated: Bool { false }
}

// MARK: - Mood

/// How hard a look pushes. The app canvas sits behind text all day; a session
/// canvas *is* the screen. One knob, so a look never needs a second painter.
nonisolated enum CanvasMood: Sendable {
    /// Behind the tabs: dimmer light, fewer particles.
    case ambient
    /// Behind a take: full intensity.
    case session

    var gain: Double { self == .session ? 1.0 : 0.74 }
    var density: Double { self == .session ? 1.0 : 0.6 }
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
        tone: AppBackground.Style = .primary
    ) {
        guard size.width > 1, size.height > 1 else { return }
        let f = CanvasFrame(size: size, mood: mood)

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
        case .tide: paintTide(&g, f)
        case .dusk: paintDusk(&g, f)
        case .signal: paintSignal(&g, f)
        case .noir: paintNoir(&g, f)
        }
    }
}

/// Everything a painter needs, resolved once: the canvas box and the mood
/// knobs. Passing this instead of `(size, mood)` keeps the painters below
/// readable.
private struct CanvasFrame {
    let size: CGSize
    let mood: CanvasMood

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

/// The default: deep navy, teal high light, quiet blue counterweight. Tone
/// only nudges the wash — `.subtle` sits a hair above `.primary` so a pushed
/// detail view does not pop, `.recording` drops darker and pushes the teal.
/// Keep this composition stable; other looks are free to experiment.
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
    // Quiet navy-blue counterweight — not the bright violet that used to sit here.
    canvasGlow(&g, canvasQuietBlue, at: f.at(0.08, 0.88),
               radius: f.d * 0.42, intensity: 0.14, stretch: 1.3, angle: .degrees(14))
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
    canvasGlow(&g, canvasQuietBlue, at: f.at(0.16, 0.84),
               radius: f.d * 0.38, intensity: 0.10, stretch: 1.2)
    canvasStars(&g, count: 26, f, brightness: 0.35)
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.40)
}

// MARK: Mist

/// Fog banks, not blobs: every glow is stretched flat so the field reads as
/// weather across graphite rather than orbs.
private func paintMist(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.042, green: 0.054, blue: 0.082),
        Color(red: 0.028, green: 0.036, blue: 0.058),
        Color(red: 0.016, green: 0.022, blue: 0.038)
    ])

    g.blendMode = .plusLighter
    canvasStars(&g, count: f.count(18), f, brightness: 0.22)
    let banks: [(x: Double, y: Double, span: Double, strength: Double, angle: Double, color: Color)] = [
        (0.18, 0.18, 0.52, 0.22, -10, Color(red: 0.50, green: 0.66, blue: 0.78)),
        (0.62, 0.28, 0.58, 0.20, 8, Color(red: 0.32, green: 0.50, blue: 0.68)),
        (0.38, 0.52, 0.64, 0.24, -4, AppColors.primary),
        (0.82, 0.66, 0.48, 0.18, 14, Color(red: 0.42, green: 0.58, blue: 0.76)),
        (0.28, 0.86, 0.50, 0.20, -6, canvasMint)
    ]
    for bank in banks {
        canvasGlow(&g, bank.color,
                   at: f.at(bank.x, bank.y),
                   radius: f.d * bank.span,
                   intensity: f.gain(bank.strength),
                   stretch: 2.9,
                   angle: .degrees(bank.angle))
    }
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.36)
}

// MARK: Aurora

/// Polar sky: a dark wash, a glowing oval on the horizon, then vertical
/// shafts of light leaning a few degrees off true — the photograph, not a
/// cartoon sine ribbon with a hard rim.
private func paintAurora(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.010, green: 0.028, blue: 0.062),
        Color(red: 0.008, green: 0.018, blue: 0.044),
        Color(red: 0.018, green: 0.012, blue: 0.040)
    ])

    g.blendMode = .plusLighter
    canvasStars(&g, count: f.count(70), f, heightFraction: 0.78, brightness: 0.72)

    // Horizon oval — the glow the shafts are born from.
    canvasGlow(&g, auroraGreen, at: f.at(0.48, 0.62),
               radius: f.d * 0.58, intensity: f.gain(0.22), stretch: 2.4)
    canvasGlow(&g, canvasViolet, at: f.at(0.68, 0.58),
               radius: f.d * 0.46, intensity: f.gain(0.18), stretch: 2.0, angle: .degrees(8))
    canvasGlow(&g, AppColors.primary, at: f.at(0.32, 0.60),
               radius: f.d * 0.42, intensity: f.gain(0.16), stretch: 2.1, angle: .degrees(-10))
    canvasGlow(&g, auroraMagenta, at: f.at(0.58, 0.70),
               radius: f.d * 0.28, intensity: f.gain(0.12), stretch: 1.8)

    canvasGlow(&g, auroraGreen, at: f.at(0.40, 0.42),
               radius: f.d * 0.40, intensity: f.gain(0.14), stretch: 3.2, angle: .degrees(78))
    canvasGlow(&g, canvasViolet, at: f.at(0.62, 0.38),
               radius: f.d * 0.36, intensity: f.gain(0.12), stretch: 3.0, angle: .degrees(102))

    let shafts: [(x: Double, y: Double, lean: Double, length: Double, width: Double, strength: Double, color: Color)] = [
        (0.16, 0.46, -14, 0.62, 5.4, 0.22, auroraGreen),
        (0.24, 0.40, -8, 0.70, 6.2, 0.28, canvasMint),
        (0.32, 0.44, -4, 0.58, 5.0, 0.20, AppColors.categoryBrandBright),
        (0.42, 0.36, 3, 0.76, 6.8, 0.34, auroraGreen),
        (0.50, 0.40, 6, 0.64, 5.6, 0.24, canvasViolet),
        (0.58, 0.34, 10, 0.80, 7.0, 0.32, auroraMagenta),
        (0.68, 0.42, 7, 0.66, 5.8, 0.26, AppColors.primary),
        (0.78, 0.38, 14, 0.72, 6.4, 0.30, canvasMint),
        (0.86, 0.48, 18, 0.52, 4.8, 0.18, canvasViolet)
    ]
    let visible = f.mood == .session ? shafts : Array(shafts.enumerated().compactMap { $0.offset % 2 == 0 ? $0.element : nil })
    for shaft in visible {
        canvasAuroraShaft(&g, f, shaft)
        // Hot core at the base of the brighter columns.
        if shaft.strength > 0.26 {
            canvasGlow(&g, Color.white.opacity(0.9),
                       at: f.at(shaft.x, min(shaft.y + 0.22, 0.72)),
                       radius: f.d * 0.045, intensity: f.gain(0.22))
        }
    }
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.38, center: UnitPoint(x: 0.5, y: 0.42))
}

// MARK: Ember

/// Warm on purpose — every other look lives in teal and cool tones, so this
/// one is the odd heat. A three-stage well at the bottom, sparks above it,
/// and a single teal counterweight so it does not read as an alert.
private func paintEmber(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.038, green: 0.022, blue: 0.030),
        Color(red: 0.062, green: 0.024, blue: 0.020),
        Color(red: 0.110, green: 0.036, blue: 0.016)
    ])

    g.blendMode = .plusLighter
    canvasGlow(&g, Color(red: 0.92, green: 0.34, blue: 0.12), at: f.at(0.5, 1.05),
               radius: f.d * 0.70, intensity: f.gain(0.52), stretch: 1.5)
    canvasGlow(&g, Color(red: 1.0, green: 0.66, blue: 0.26), at: f.at(0.5, 1.02),
               radius: f.d * 0.34, intensity: f.gain(0.42), stretch: 1.8)
    canvasGlow(&g, Color(red: 1.0, green: 0.88, blue: 0.58), at: f.at(0.5, 1.0),
               radius: f.d * 0.14, intensity: f.gain(0.30), stretch: 2.2)
    canvasGlow(&g, AppColors.primary, at: f.at(0.74, 0.12),
               radius: f.d * 0.40, intensity: f.gain(0.20), stretch: 1.2)

    canvasSparks(&g, f, count: f.count(44), rise: 0.88)
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.40, center: UnitPoint(x: 0.5, y: 0.88))
}

// MARK: Horizon

/// Sky meeting ground: a graded field, a bloom sitting on the line, and a
/// ground wash that darkens away from it so type below stays readable.
private func paintHorizon(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    let y = f.size.height * 0.72

    canvasWash(&g, f.size, [
        Color(red: 0.012, green: 0.022, blue: 0.052),
        Color(red: 0.022, green: 0.038, blue: 0.072),
        Color(red: 0.008, green: 0.012, blue: 0.026)
    ])

    g.blendMode = .plusLighter
    canvasGlow(&g, canvasQuietBlue, at: f.at(0.50, 0.22),
               radius: f.d * 0.42, intensity: f.gain(0.12), stretch: 1.8)
    canvasStars(&g, count: f.count(46), f, heightFraction: 0.68, brightness: 0.85)
    canvasHorizonLine(&g, f, y: y, bloom: 0.34, spread: 0.44)
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
    canvasGlow(&g, Color(red: 0.34, green: 0.40, blue: 0.66), at: f.at(0.56, 0.30),
               radius: f.d * 0.46, intensity: f.gain(0.13), stretch: 2.4, angle: .degrees(-24))
    canvasStars(&g, count: f.count(70), f, heightFraction: 0.70, brightness: 1.0)
    canvasHorizonLine(&g, f, y: y, bloom: 0.38, spread: 0.40)
    g.blendMode = .normal

    canvasGround(&g, f, y: y, depth: 0.60)
    canvasVignette(&g, f.size, strength: 0.34, center: UnitPoint(x: 0.5, y: 0.6))
}

// MARK: Prism

/// Angled beams. A rotated, stretched glow is soft on both axes in one fill —
/// no hard polygons, no `.blur` view modifier.
private func paintPrism(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.044, green: 0.056, blue: 0.130),
        Color(red: 0.028, green: 0.034, blue: 0.082),
        Color(red: 0.020, green: 0.022, blue: 0.052)
    ], from: .topLeading, to: .bottomTrailing)

    g.blendMode = .plusLighter
    let beams: [(x: Double, y: Double, angle: Double, strength: Double, span: Double, color: Color)] = [
        (0.16, 0.16, -58, 0.34, 0.34, AppColors.categoryBrandBright),
        (0.40, 0.32, -52, 0.28, 0.32, canvasViolet),
        (0.62, 0.20, -64, 0.26, 0.30, AppColors.primary),
        (0.84, 0.48, -48, 0.24, 0.28, Color(red: 0.30, green: 0.52, blue: 0.86)),
        (0.28, 0.68, -44, 0.18, 0.24, canvasMint),
        (0.72, 0.78, -56, 0.16, 0.22, auroraGreen)
    ]
    for beam in beams {
        canvasGlow(&g, beam.color,
                   at: f.at(beam.x, beam.y),
                   radius: f.d * beam.span,
                   intensity: f.gain(beam.strength),
                   stretch: 3.8,
                   angle: .degrees(beam.angle))
        canvasGlow(&g, Color.white,
                   at: f.at(beam.x, beam.y),
                   radius: f.d * 0.05,
                   intensity: f.gain(beam.strength * 0.45))
    }
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.34)
}

// MARK: Depth

/// Concentric wells. Rings fade outward so the canvas has a centre without a
/// single bright object competing with the cards.
private func paintDepth(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    let center = f.at(0.5, 0.40)

    canvasWash(&g, f.size, [
        Color(red: 0.026, green: 0.032, blue: 0.070),
        Color(red: 0.016, green: 0.020, blue: 0.048),
        Color(red: 0.010, green: 0.012, blue: 0.030)
    ])

    g.blendMode = .plusLighter
    canvasGlow(&g, AppColors.primary, at: center, radius: f.d * 0.38, intensity: f.gain(0.30))
    canvasGlow(&g, canvasMint, at: center, radius: f.d * 0.14, intensity: f.gain(0.18))
    canvasGlow(&g, canvasQuietBlue, at: f.at(0.5, 0.86),
               radius: f.d * 0.40, intensity: f.gain(0.14), stretch: 1.6)

    // Nested wells, not 1pt ellipse strokes — those read as a target graphic.
    for ring in 0..<5 {
        let span = 0.16 + Double(ring) * 0.11
        let fade = 1 - Double(ring) / 5.4
        canvasGlow(&g, AppColors.categoryBrandBright, at: center,
                   radius: f.d * span, intensity: f.gain(0.10 * fade), stretch: 1.05)
    }
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.42, center: UnitPoint(x: 0.5, y: 0.40))
}

// MARK: Hyperspace

/// Warp streaks from a vanishing point. Depth is hashed per streak so the
/// field stays a still — no clock, no recycle.
private func paintHyperspace(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    let center = f.at(0.5, 0.42)
    let maxR = f.d * 0.62

    canvasWash(&g, f.size, [
        Color(red: 0.012, green: 0.018, blue: 0.052),
        Color(red: 0.008, green: 0.010, blue: 0.030),
        Color(red: 0.004, green: 0.006, blue: 0.020)
    ])

    g.blendMode = .plusLighter
    canvasGlow(&g, AppColors.primary, at: center, radius: maxR * 0.34, intensity: f.gain(0.34))
    canvasGlow(&g, canvasQuietBlue, at: center, radius: maxR * 0.70, intensity: f.gain(0.12))

    for i in 0..<f.count(84) {
        let angle = canvasHash(i, 1) * .pi * 2
        let depth = 0.08 + canvasHash(i, 2) * 0.92
        let eased = depth * depth
        let dx = CGFloat(cos(angle))
        let dy = CGFloat(sin(angle))
        let head = CGPoint(x: center.x + dx * (maxR * 0.03 + eased * maxR),
                           y: center.y + dy * (maxR * 0.03 + eased * maxR))
        let streak = f.unit * (6 + eased * 72)
        let tail = CGPoint(x: head.x - dx * streak, y: head.y - dy * streak)

        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)

        let tint = canvasHash(i, 4)
        let color: Color = tint > 0.86
            ? AppColors.categoryBrandBright
            : (tint < 0.10 ? Color(red: 0.72, green: 0.78, blue: 1.0) : .white)

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

/// Soft colour clouds, two hot cores, a dark dust lane cutting across them,
/// and star layers front and back. The dust lane is the only *subtractive*
/// mark on any canvas — without it this reads as overlapping orbs.
private func paintNebula(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.052, green: 0.024, blue: 0.078),
        Color(red: 0.026, green: 0.016, blue: 0.058),
        Color(red: 0.010, green: 0.010, blue: 0.032)
    ], from: .topLeading, to: .bottomTrailing)

    g.blendMode = .plusLighter
    canvasStars(&g, count: f.count(40), f, brightness: 0.45, seed: 11)

    let clouds: [(x: Double, y: Double, span: Double, strength: Double, angle: Double, color: Color)] = [
        (0.30, 0.30, 0.62, 0.40, -22, Color(red: 0.58, green: 0.22, blue: 0.86)),
        (0.72, 0.26, 0.54, 0.34, 28, AppColors.primary),
        (0.52, 0.70, 0.70, 0.32, 12, Color(red: 0.14, green: 0.34, blue: 0.72)),
        (0.18, 0.78, 0.46, 0.30, -36, Color(red: 0.86, green: 0.26, blue: 0.48)),
        (0.86, 0.80, 0.40, 0.24, 44, canvasMint)
    ]
    for cloud in clouds {
        canvasGlow(&g, cloud.color,
                   at: f.at(cloud.x, cloud.y),
                   radius: f.d * cloud.span,
                   intensity: f.gain(cloud.strength),
                   stretch: 1.45,
                   angle: .degrees(cloud.angle))
    }

    canvasGlow(&g, Color(red: 1.0, green: 0.86, blue: 0.96),
               at: f.at(0.34, 0.34),
               radius: f.d * 0.10, intensity: f.gain(0.34))
    canvasGlow(&g, Color(red: 0.80, green: 0.94, blue: 1.0),
               at: f.at(0.70, 0.62),
               radius: f.d * 0.07, intensity: f.gain(0.26))
    g.blendMode = .normal

    canvasGlow(&g, Color(red: 0.03, green: 0.01, blue: 0.05),
               at: f.at(0.48, 0.50),
               radius: f.d * 0.44, intensity: 0.72, stretch: 1.9, angle: .degrees(-34))

    g.blendMode = .plusLighter
    canvasStars(&g, count: f.count(46), f, brightness: 0.9)
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.42)
}

// MARK: Tide

/// Layered teal bands stacked from the bottom — water reading as depth, not
/// as motion. Distinct from Depth's rings and Horizon's single line.
private func paintTide(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.018, green: 0.036, blue: 0.070),
        Color(red: 0.012, green: 0.028, blue: 0.054),
        Color(red: 0.008, green: 0.040, blue: 0.060)
    ], from: .top, to: .bottom)

    g.blendMode = .plusLighter
    canvasGlow(&g, AppColors.primary, at: f.at(0.72, 0.12),
               radius: f.d * 0.36, intensity: f.gain(0.16), stretch: 1.4)

    let bands: [(y: Double, strength: Double, span: Double, color: Color)] = [
        (0.42, 0.14, 0.55, canvasDeepTeal),
        (0.56, 0.20, 0.62, AppColors.primary),
        (0.70, 0.26, 0.70, canvasMint),
        (0.84, 0.32, 0.78, AppColors.categoryBrandBright),
        (0.96, 0.28, 0.85, Color(red: 0.20, green: 0.70, blue: 0.78))
    ]
    for band in bands {
        canvasGlow(&g, band.color,
                   at: f.at(0.5, band.y),
                   radius: f.d * band.span,
                   intensity: f.gain(band.strength),
                   stretch: 3.4,
                   angle: .degrees(-2))
    }

    // Foam is a brighter strip on the upper bands, not a stroked sine.
    canvasGlow(&g, canvasMint, at: f.at(0.42, 0.62),
               radius: f.d * 0.22, intensity: f.gain(0.16), stretch: 3.6)
    canvasGlow(&g, Color.white, at: f.at(0.58, 0.78),
               radius: f.d * 0.14, intensity: f.gain(0.10), stretch: 3.8)
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.36, center: UnitPoint(x: 0.5, y: 0.62))
}

// MARK: Dusk

/// Warm amber in the upper third meeting cool teal below — a sunset split
/// that stays readable under glass cards. Not Ember's bottom well.
private func paintDusk(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.090, green: 0.040, blue: 0.055),
        Color(red: 0.040, green: 0.030, blue: 0.070),
        Color(red: 0.012, green: 0.036, blue: 0.068)
    ], from: .topLeading, to: .bottomTrailing)

    g.blendMode = .plusLighter
    canvasGlow(&g, Color(red: 1.0, green: 0.55, blue: 0.28), at: f.at(0.18, 0.12),
               radius: f.d * 0.54, intensity: f.gain(0.40), stretch: 1.4, angle: .degrees(-20))
    canvasGlow(&g, Color(red: 1.0, green: 0.72, blue: 0.38), at: f.at(0.28, 0.18),
               radius: f.d * 0.22, intensity: f.gain(0.26))
    canvasGlow(&g, Color(red: 0.95, green: 0.32, blue: 0.38), at: f.at(0.42, 0.28),
               radius: f.d * 0.40, intensity: f.gain(0.24), stretch: 1.5, angle: .degrees(12))
    canvasGlow(&g, AppColors.primary, at: f.at(0.78, 0.78),
               radius: f.d * 0.54, intensity: f.gain(0.32), stretch: 1.4)
    canvasGlow(&g, canvasMint, at: f.at(0.55, 0.92),
               radius: f.d * 0.38, intensity: f.gain(0.18), stretch: 2.0)

    let seamY = f.size.height * 0.48
    canvasGlow(&g, Color(red: 1.0, green: 0.78, blue: 0.48),
               at: CGPoint(x: f.size.width * 0.35, y: seamY),
               radius: f.d * 0.32, intensity: f.gain(0.24), stretch: 2.8)
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.38, center: UnitPoint(x: 0.4, y: 0.4))
}

// MARK: Signal

/// Soft waveform ribbons — on-brand for a speech app without competing with
/// real meters on the recording screen.
private func paintSignal(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.022, green: 0.032, blue: 0.078),
        Color(red: 0.014, green: 0.022, blue: 0.052),
        Color(red: 0.010, green: 0.016, blue: 0.036)
    ])

    g.blendMode = .plusLighter
    canvasGlow(&g, AppColors.primary, at: f.at(0.5, 0.48),
               radius: f.d * 0.46, intensity: f.gain(0.16))
    canvasGlow(&g, canvasQuietBlue, at: f.at(0.22, 0.28),
               radius: f.d * 0.28, intensity: f.gain(0.10), stretch: 1.4)

    let ribbons: [(y: Double, amp: Double, freq: Double, phase: Double, strength: Double, color: Color)] = [
        (0.28, 0.04, 1.4, 0.2, 0.34, AppColors.categoryBrandBright),
        (0.42, 0.055, 1.1, 1.4, 0.40, AppColors.primary),
        (0.56, 0.035, 1.8, 2.6, 0.28, canvasMint),
        (0.70, 0.048, 1.3, 0.9, 0.32, Color(red: 0.40, green: 0.62, blue: 0.92))
    ]
    let visible = f.mood == .session ? ribbons : Array(ribbons.prefix(3))
    for ribbon in visible {
        canvasWaveRibbon(
            &g, f,
            y: ribbon.y,
            amplitude: ribbon.amp,
            frequency: ribbon.freq,
            phase: ribbon.phase,
            color: ribbon.color,
            intensity: f.gain(ribbon.strength)
        )
    }
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.36)
}

// MARK: Noir

/// Near-black with one decisive teal slash. Maximum calm, maximum contrast
/// for glass — the anti-nebula.
private func paintNoir(_ g: inout GraphicsContext, _ f: CanvasFrame) {
    canvasWash(&g, f.size, [
        Color(red: 0.012, green: 0.014, blue: 0.028),
        Color(red: 0.008, green: 0.010, blue: 0.020),
        Color(red: 0.004, green: 0.005, blue: 0.012)
    ])

    g.blendMode = .plusLighter
    canvasGlow(&g, AppColors.primary, at: f.at(0.62, 0.28),
               radius: f.d * 0.58, intensity: f.gain(0.24), stretch: 4.0, angle: .degrees(-38))
    canvasGlow(&g, AppColors.categoryBrandBright, at: f.at(0.58, 0.30),
               radius: f.d * 0.20, intensity: f.gain(0.32), stretch: 4.4, angle: .degrees(-38))
    canvasGlow(&g, Color.white, at: f.at(0.56, 0.31),
               radius: f.d * 0.05, intensity: f.gain(0.18), stretch: 3.6, angle: .degrees(-38))
    canvasGlow(&g, canvasQuietBlue, at: f.at(0.18, 0.82),
               radius: f.d * 0.32, intensity: f.gain(0.08), stretch: 1.3)
    canvasStars(&g, count: f.count(18), f, brightness: 0.28)
    g.blendMode = .normal

    canvasVignette(&g, f.size, strength: 0.48)
}

// MARK: - Shared marks

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

/// Soft sine ribbon used by Signal. One fat glow-stroke, no white hairline —
/// that inner stroke made it look like a chart overlay.
private func canvasWaveRibbon(
    _ g: inout GraphicsContext,
    _ f: CanvasFrame,
    y: Double,
    amplitude: Double,
    frequency: Double,
    phase: Double,
    color: Color,
    intensity: Double
) {
    let midY = f.size.height * y
    let amp = f.size.height * amplitude
    let steps = 36

    var path = Path()
    for s in 0...steps {
        let t = Double(s) / Double(steps)
        let wave = sin(t * frequency * 2 * .pi + phase) * amp
            + sin(t * frequency * 0.5 * 2 * .pi - phase * 0.6) * amp * 0.35
        let point = CGPoint(x: CGFloat(t) * f.size.width, y: midY + wave)
        if s == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }

    g.stroke(
        path,
        with: .linearGradient(
            Gradient(colors: [
                .clear,
                color.opacity(intensity * 0.45),
                color.opacity(intensity),
                color.opacity(intensity * 0.45),
                .clear
            ]),
            startPoint: CGPoint(x: 0, y: midY),
            endPoint: CGPoint(x: f.size.width, y: midY)
        ),
        style: StrokeStyle(lineWidth: f.unit * 5.5, lineCap: .round, lineJoin: .round)
    )
}

// MARK: - Shared tones

private let canvasViolet = Color(red: 0.46, green: 0.28, blue: 0.90)
private let canvasMint = Color(red: 0.30, green: 0.92, blue: 0.78)
private let canvasDeepTeal = Color(red: 0.08, green: 0.26, blue: 0.40)
/// Quiet navy-blue counterweight for Classic / Midnight — deliberately not purple.
private let canvasQuietBlue = Color(red: 0.20, green: 0.28, blue: 0.52)
private let auroraGreen = Color(red: 0.38, green: 0.96, blue: 0.62)
private let auroraMagenta = Color(red: 0.78, green: 0.34, blue: 0.94)

// MARK: - Primitives

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

/// Deterministic star field. Index `i` always lands in the same place.
private func canvasStars(
    _ g: inout GraphicsContext,
    count: Int,
    _ f: CanvasFrame,
    heightFraction: Double = 1,
    brightness: Double = 1,
    seed: Double = 0
) {
    for i in 0..<count {
        let twinkle = 0.42 + 0.58 * canvasHash(i, 3 + seed)
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

/// Embers frozen above a well. Life is hashed, not timed — same scatter every
/// paint.
private func canvasSparks(
    _ g: inout GraphicsContext,
    _ f: CanvasFrame,
    count: Int,
    rise: Double
) {
    for i in 0..<count {
        let life = canvasHash(i, 3)
        let fade = 1 - life * 0.55
        guard fade > 0.08 else { continue }
        let sway = (canvasHash(i, 6) - 0.5) * life * 0.08
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

/// Vertical aurora column. Rotate a wide glow onto its side so the shaft is
/// soft on every edge — no polygon, no rim stroke.
private func canvasAuroraShaft(
    _ g: inout GraphicsContext,
    _ f: CanvasFrame,
    _ shaft: (x: Double, y: Double, lean: Double, length: Double, width: Double, strength: Double, color: Color)
) {
    canvasGlow(
        &g, shaft.color,
        at: f.at(shaft.x, shaft.y),
        radius: f.d * shaft.length * 0.48,
        intensity: f.gain(shaft.strength),
        stretch: shaft.width,
        angle: .degrees(90 + shaft.lean)
    )
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

/// Cheap hash for particle fields. Same index always yields the same 0...1.
private func canvasHash(_ i: Int, _ salt: Double) -> Double {
    canvasFract(sin(Double(i) * 127.139 + salt * 311.7) * 43758.5453123)
}

private func canvasFract(_ x: Double) -> Double { x - floor(x) }
