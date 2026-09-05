import SwiftUI

// MARK: - Recording Backdrop

/// Canvas behind a practice session — the prepare countdown and the recording
/// screen itself, so the look the user picked does not vanish the moment they
/// start talking. The rest of the app stays on `AppBackground`; this enum is
/// not a second theme system.
///
/// `nonisolated` so settings tests and any off-main decode of the stored Int
/// do not hop the MainActor. Raw values are the SwiftData payload; do not
/// reorder existing cases.
nonisolated enum RecordingBackdrop: Int, Codable, CaseIterable, Identifiable, Sendable {
    case base = 0
    case aurora = 1
    case hyperspace = 2
    case nebula = 3
    case ember = 4
    case void = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .base: return "Base"
        case .aurora: return "Aurora"
        case .hyperspace: return "Hyperspace"
        case .nebula: return "Nebula"
        case .ember: return "Ember"
        case .void: return "Void"
        }
    }
}

// MARK: - View

/// Full-bleed session canvas. Driven from a single `TimelineView` so every
/// style shares one clock. `animated: false` freezes a frame for thumbnails.
///
/// Runs at 15 fps for the whole take, alongside the 60 fps waveform. Pauses
/// when the scene is inactive. Dropped from 30 → 20 → 15 — the eye cannot tell
/// on these soft canvases, and recording already spends frame budget on the
/// waveform ring. Thumbnails freeze with `animated: false`.
struct RecordingBackdropView: View {
    var backdrop: RecordingBackdrop = .base
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let shouldAnimate = animated && !reduceMotion && scenePhase == .active

        Group {
            switch backdrop {
            case .base:
                // Base is always the classic recording wash — not the user's
                // app-wide canvas. Recording Look owns session mood separately
                // from Settings → Appearance.
                AppCanvasView(canvas: .classic, style: .recording, animated: false)
            default:
                TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !shouldAnimate)) { context in
                    let time = shouldAnimate
                        ? context.date.timeIntervalSinceReferenceDate
                        : 0
                    canvas(time: time)
                        .drawingGroup(opaque: true)
                        .overlay { readabilityVignette }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func canvas(time: TimeInterval) -> some View {
        switch backdrop {
        case .base:
            EmptyView()
        case .aurora:
            AuroraCanvas(time: time)
        case .hyperspace:
            HyperspaceCanvas(time: time)
        case .nebula:
            NebulaCanvas(time: time)
        case .ember:
            EmberCanvas(time: time)
        case .void:
            VoidCanvas(time: time)
        }
    }

    /// Keeps the white countdown type readable on a busy canvas. Base already
    /// has this contrast built into `AppBackground.recording`.
    private var readabilityVignette: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.38),
                Color.black.opacity(0.08),
                Color.black.opacity(0.42)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Aurora

/// Teal-to-violet curtains. MeshGradient does the wash; two sine ribbons
/// give it a direction so it reads as sky, not a random blob.
private struct AuroraCanvas: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.04, blue: 0.07)

            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints,
                colors: [
                    Color(red: 0.02, green: 0.10, blue: 0.14),
                    AppColors.primary.opacity(0.85),
                    Color(red: 0.10, green: 0.06, blue: 0.22),
                    Color(red: 0.04, green: 0.16, blue: 0.18),
                    AppColors.categoryBrandBright,
                    Color(red: 0.18, green: 0.08, blue: 0.28),
                    Color(red: 0.02, green: 0.05, blue: 0.10),
                    Color(red: 0.06, green: 0.12, blue: 0.22),
                    Color(red: 0.08, green: 0.04, blue: 0.16)
                ]
            )
            .opacity(0.92)

            Canvas { graphics, size in
                drawRibbon(in: &graphics, size: size, phase: time * 0.35, y: 0.32, amplitude: 28, color: AppColors.categoryBrandBright.opacity(0.45))
                drawRibbon(in: &graphics, size: size, phase: time * 0.22 + 1.4, y: 0.48, amplitude: 36, color: Color(red: 0.45, green: 0.28, blue: 0.85).opacity(0.38))
                drawRibbon(in: &graphics, size: size, phase: time * 0.28 + 2.7, y: 0.62, amplitude: 22, color: AppColors.primary.opacity(0.35))
            }
        }
    }

    private var meshPoints: [SIMD2<Float>] {
        let drift = Float(sin(time * 0.23)) * 0.08
        let lift = Float(cos(time * 0.17)) * 0.07
        return [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5 + drift, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.5 + lift), SIMD2<Float>(0.5 - drift, 0.5 + lift), SIMD2<Float>(1, 0.48),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1)
        ]
    }

    private func drawRibbon(
        in graphics: inout GraphicsContext,
        size: CGSize,
        phase: Double,
        y: CGFloat,
        amplitude: CGFloat,
        color: Color
    ) {
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = t * size.width
            let wave = sin(Double(t) * 2.6 * .pi + phase) * amplitude
            let point = CGPoint(x: x, y: size.height * y + wave)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        graphics.stroke(path, with: .color(color), lineWidth: 18)
        graphics.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 2)
    }
}

// MARK: - Hyperspace

/// Warp streaks from a vanishing point. Depth is a wrapped 0...1 so stars
/// recycle instead of allocating; squaring it makes them accelerate as they
/// leave the centre — the whole point of a jump.
private struct HyperspaceCanvas: View {
    let time: TimeInterval

    private let starCount = 70

    var body: some View {
        Canvas { graphics, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
            let maxR = hypot(size.width, size.height) * 0.62

            graphics.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.01, green: 0.015, blue: 0.04)))

            // Soft well at the vanishing point so the streaks have somewhere
            // to be born from, rather than appearing out of flat black.
            let well = CGRect(x: center.x - 90, y: center.y - 90, width: 180, height: 180)
            graphics.fill(
                Path(ellipseIn: well),
                with: .radialGradient(
                    Gradient(colors: [AppColors.primary.opacity(0.22), .clear]),
                    center: center,
                    startRadius: 4,
                    endRadius: 90
                )
            )

            for i in 0..<starCount {
                let angle = hash(i, 1) * .pi * 2
                let speed = 0.14 + hash(i, 2) * 0.72
                let depth = fract(hash(i, 3) + time * speed)
                let eased = depth * depth
                let radius = 10 + eased * maxR
                let x = center.x + CGFloat(cos(angle)) * radius
                let y = center.y + CGFloat(sin(angle)) * radius
                let streak = 3 + eased * (22 + speed * 18)
                let dx = CGFloat(cos(angle)) * streak
                let dy = CGFloat(sin(angle)) * streak

                var path = Path()
                path.move(to: CGPoint(x: x - dx, y: y - dy))
                path.addLine(to: CGPoint(x: x + dx * 0.15, y: y + dy * 0.15))

                let teal = hash(i, 4) > 0.82
                let opacity = 0.12 + 0.78 * eased
                let color: Color = teal
                    ? AppColors.categoryBrandBright.opacity(opacity)
                    : Color.white.opacity(opacity)
                graphics.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 0.7 + eased * 1.6, lineCap: .round))
            }
        }
    }
}

// MARK: - Nebula

/// Slow colour clouds. Orbs orbit so the field never sits still, but the
/// motion is low-frequency — this is fog, not a screensaver.
private struct NebulaCanvas: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.02, blue: 0.07)

            orb(
                color: Color(red: 0.42, green: 0.18, blue: 0.62),
                x: 0.28 + 0.06 * sin(time * 0.13),
                y: 0.32 + 0.05 * cos(time * 0.11),
                radius: 280
            )
            orb(
                color: AppColors.primary,
                x: 0.72 + 0.05 * cos(time * 0.09),
                y: 0.28 + 0.07 * sin(time * 0.15),
                radius: 240
            )
            orb(
                color: Color(red: 0.12, green: 0.28, blue: 0.48),
                x: 0.50 + 0.08 * sin(time * 0.07),
                y: 0.70 + 0.04 * cos(time * 0.12),
                radius: 300
            )
            orb(
                color: Color(red: 0.55, green: 0.22, blue: 0.40),
                x: 0.18 + 0.04 * cos(time * 0.16),
                y: 0.78 + 0.05 * sin(time * 0.10),
                radius: 200
            )
        }
    }

    private func orb(color: Color, x: Double, y: Double, radius: CGFloat) -> some View {
        GeometryReader { geo in
            RadialGradient(
                colors: [color.opacity(0.55), color.opacity(0.12), .clear],
                center: .center,
                startRadius: 8,
                endRadius: radius
            )
            .frame(width: radius * 2, height: radius * 2)
            .position(x: geo.size.width * x, y: geo.size.height * y)
            .blendMode(.plusLighter)
        }
    }
}

// MARK: - Ember

/// Copper well at the bottom, sparks climbing out of it. Warm on purpose —
/// the other canvases live in teal/violet, so this one is the odd heat.
private struct EmberCanvas: View {
    let time: TimeInterval

    private let sparkCount = 42

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.02, blue: 0.03)

            RadialGradient(
                colors: [
                    Color(red: 0.72, green: 0.28, blue: 0.12).opacity(0.55),
                    Color(red: 0.35, green: 0.08, blue: 0.06).opacity(0.25),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 1.05),
                startRadius: 10,
                endRadius: 420
            )

            RadialGradient(
                colors: [AppColors.primary.opacity(0.18), .clear],
                center: UnitPoint(x: 0.7, y: 0.12),
                startRadius: 8,
                endRadius: 240
            )

            Canvas { graphics, size in
                for i in 0..<sparkCount {
                    let xJitter = hash(i, 1)
                    let speed = 0.08 + hash(i, 2) * 0.18
                    let life = fract(hash(i, 3) + time * speed)
                    let x = size.width * (0.18 + xJitter * 0.64)
                    let y = size.height * (1.05 - life * 0.85)
                    let sizePt = 1.2 + (1 - life) * 2.4
                    let rect = CGRect(x: x, y: y, width: sizePt, height: sizePt * (1.6 + life))
                    let hot = hash(i, 4) > 0.7
                    let color: Color = hot
                        ? Color(red: 1.0, green: 0.72, blue: 0.32).opacity(0.85 * (1 - life))
                        : Color(red: 0.92, green: 0.38, blue: 0.16).opacity(0.7 * (1 - life))
                    graphics.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }
}

// MARK: - Void

/// Near-black field, sparse stars, a thin teal horizon. The quiet option.
private struct VoidCanvas: View {
    let time: TimeInterval

    private let starCount = 48

    var body: some View {
        Canvas { graphics, size in
            graphics.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(red: 0.012, green: 0.014, blue: 0.03))
            )

            let horizonY = size.height * 0.72
            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: horizonY))
            horizon.addLine(to: CGPoint(x: size.width, y: horizonY))
            graphics.stroke(
                horizon,
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        AppColors.primary.opacity(0.45),
                        AppColors.categoryBrandBright.opacity(0.35),
                        .clear
                    ]),
                    startPoint: CGPoint(x: 0, y: horizonY),
                    endPoint: CGPoint(x: size.width, y: horizonY)
                ),
                lineWidth: 1
            )

            graphics.fill(
                Path(CGRect(x: 0, y: horizonY, width: size.width, height: size.height - horizonY)),
                with: .linearGradient(
                    Gradient(colors: [
                        AppColors.primary.opacity(0.08),
                        .clear
                    ]),
                    startPoint: CGPoint(x: size.width / 2, y: horizonY),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                )
            )

            for i in 0..<starCount {
                let x = hash(i, 1) * size.width
                let y = hash(i, 2) * horizonY * 0.92
                let twinkle = 0.25 + 0.75 * (0.5 + 0.5 * sin(time * (0.6 + hash(i, 3) * 1.8) + Double(i)))
                let r = 0.6 + hash(i, 4) * 1.4
                let rect = CGRect(x: x, y: y, width: r * 2, height: r * 2)
                graphics.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(0.2 + 0.7 * twinkle * hash(i, 5)))
                )
            }
        }
    }
}

// MARK: - Deterministic noise

/// Cheap hash for particle fields. Same index always yields the same 0...1,
/// so a TimelineView can be stateless.
private func hash(_ i: Int, _ salt: Double) -> Double {
    fract(sin(Double(i) * 127.139 + salt * 311.7) * 43758.5453123)
}

private func fract(_ x: Double) -> Double {
    x - floor(x)
}
