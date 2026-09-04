import SwiftUI

// MARK: - App Canvas

/// Full-app background mood. Separate from `RecordingBackdrop`, which paints
/// only the prepare countdown and the take itself — so a speaker can keep a
/// calm Library while recording against Ember.
///
/// Raw values are the SwiftData payload; do not reorder existing cases.
/// `nonisolated` so settings tests and off-main decode stay off the MainActor.
nonisolated enum AppCanvas: Int, Codable, CaseIterable, Identifiable, Sendable {
    case classic = 0
    case midnight = 1
    case mist = 2
    case aurora = 3
    case ember = 4
    case horizon = 5
    case prism = 6
    case depth = 7

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .midnight: return "Midnight"
        case .mist: return "Mist"
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .horizon: return "Horizon"
        case .prism: return "Prism"
        case .depth: return "Depth"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "Deep navy with soft teal and indigo orbs"
        case .midnight: return "Near-black field, quieter glow"
        case .mist: return "Cool fog drifting across graphite"
        case .aurora: return "Slow teal-to-violet wash"
        case .ember: return "Warm copper well at the bottom"
        case .horizon: return "Sparse stars over a thin teal line"
        case .prism: return "Soft light shards across navy"
        case .depth: return "Layered wells sinking into the canvas"
        }
    }
}

// MARK: - Canvas View

/// Renders an `AppCanvas`. Animated styles run at a low frame rate so the
/// whole app does not pay recording-session backdrop cost on every tab.
/// Timeline clocks pause when the scene is inactive or Reduce Motion is on.
struct AppCanvasView: View {
    var canvas: AppCanvas = .classic
    var style: AppBackground.Style = .primary
    /// When false, freezes particles/meshes for thumbnails and Reduce Motion.
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let shouldAnimate = animated && !reduceMotion && scenePhase == .active

        Group {
            switch canvas {
            case .classic:
                classicCanvas
            case .midnight:
                midnightCanvas
            case .mist, .aurora, .ember, .horizon, .prism, .depth:
                TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: !shouldAnimate)) { context in
                    let time = shouldAnimate
                        ? context.date.timeIntervalSinceReferenceDate
                        : 0
                    styledCanvas(time: time)
                        // Flatten the orb / mesh / particle stack into one
                        // layer so Liquid Glass cards sample a cheap backdrop.
                        .drawingGroup(opaque: true)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Classic / Midnight (static — cheap)

    private var classicCanvas: some View {
        ZStack {
            Color(red: 0.035, green: 0.04, blue: 0.09)

            LinearGradient(
                colors: classicGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [classicTeal, .clear],
                center: UnitPoint(x: 0.85, y: 0.08),
                startRadius: 20,
                endRadius: 280
            )

            RadialGradient(
                colors: [classicIndigo, .clear],
                center: UnitPoint(x: 0.12, y: 0.88),
                startRadius: 10,
                endRadius: 240
            )

            RadialGradient(
                colors: [classicCyan, .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 10,
                endRadius: 320
            )
        }
    }

    private var midnightCanvas: some View {
        ZStack {
            Color(red: 0.015, green: 0.018, blue: 0.04)

            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.035, blue: 0.08),
                    Color(red: 0.015, green: 0.02, blue: 0.05),
                    Color(red: 0.01, green: 0.012, blue: 0.03)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.teal.opacity(0.05), .clear],
                center: UnitPoint(x: 0.78, y: 0.12),
                startRadius: 10,
                endRadius: 220
            )

            RadialGradient(
                colors: [Color.indigo.opacity(0.04), .clear],
                center: UnitPoint(x: 0.18, y: 0.82),
                startRadius: 8,
                endRadius: 200
            )
        }
    }

    // MARK: - Animated styles

    @ViewBuilder
    private func styledCanvas(time: TimeInterval) -> some View {
        switch canvas {
        case .classic, .midnight:
            EmptyView()
        case .mist:
            MistCanvas(time: time)
        case .aurora:
            AppAuroraCanvas(time: time)
        case .ember:
            AppEmberCanvas(time: time)
        case .horizon:
            AppHorizonCanvas(time: time)
        case .prism:
            PrismCanvas(time: time)
        case .depth:
            DepthCanvas(time: time)
        }
    }

    // MARK: - Classic style variants

    private var classicGradient: [Color] {
        switch style {
        case .primary:
            return [
                Color(red: 0.05, green: 0.07, blue: 0.16),
                Color(red: 0.03, green: 0.045, blue: 0.10),
                Color(red: 0.035, green: 0.035, blue: 0.08)
            ]
        case .recording:
            return [
                Color(red: 0.02, green: 0.04, blue: 0.10),
                Color(red: 0.01, green: 0.02, blue: 0.06),
                Color(red: 0.02, green: 0.03, blue: 0.07)
            ]
        case .subtle:
            return [
                Color(red: 0.045, green: 0.06, blue: 0.14),
                Color(red: 0.035, green: 0.05, blue: 0.11),
                Color(red: 0.03, green: 0.04, blue: 0.09)
            ]
        }
    }

    private var classicTeal: Color {
        switch style {
        case .primary: return Color.teal.opacity(0.12)
        case .recording: return Color.teal.opacity(0.18)
        case .subtle: return Color.teal.opacity(0.10)
        }
    }

    private var classicIndigo: Color {
        switch style {
        case .primary: return Color.indigo.opacity(0.09)
        case .recording: return Color.indigo.opacity(0.06)
        case .subtle: return Color.indigo.opacity(0.08)
        }
    }

    private var classicCyan: Color {
        switch style {
        case .primary: return Color.cyan.opacity(0.04)
        case .recording: return Color.cyan.opacity(0.06)
        case .subtle: return Color.cyan.opacity(0.03)
        }
    }
}

// MARK: - Mist (new)

/// Cool drifting fog — quieter cousin of Nebula, meant for all-day use.
private struct MistCanvas: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.08)

            mistOrb(
                color: Color(red: 0.18, green: 0.32, blue: 0.42),
                x: 0.22 + 0.05 * sin(time * 0.09),
                y: 0.28 + 0.04 * cos(time * 0.07),
                radius: 260
            )
            mistOrb(
                color: Color(red: 0.12, green: 0.22, blue: 0.36),
                x: 0.78 + 0.04 * cos(time * 0.08),
                y: 0.55 + 0.05 * sin(time * 0.06),
                radius: 300
            )
            mistOrb(
                color: AppColors.primary.opacity(0.7),
                x: 0.48 + 0.06 * sin(time * 0.05),
                y: 0.78 + 0.03 * cos(time * 0.1),
                radius: 220
            )
        }
    }

    private func mistOrb(color: Color, x: Double, y: Double, radius: CGFloat) -> some View {
        GeometryReader { geo in
            RadialGradient(
                colors: [color.opacity(0.35), color.opacity(0.08), .clear],
                center: .center,
                startRadius: 6,
                endRadius: radius
            )
            .frame(width: radius * 2, height: radius * 2)
            .position(x: geo.size.width * x, y: geo.size.height * y)
            .blendMode(.plusLighter)
        }
    }
}

// MARK: - Aurora (app-soft)

/// Soft colour wash for the app canvas. Orb drift only — no MeshGradient.
/// The recording Aurora still uses MeshGradient; this one stays cheap enough
/// to sit behind every tab.
private struct AppAuroraCanvas: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.04, blue: 0.07)

            auroraOrb(
                color: AppColors.primary,
                x: 0.72 + 0.05 * cos(time * 0.09),
                y: 0.22 + 0.04 * sin(time * 0.11),
                radius: 260
            )
            auroraOrb(
                color: Color(red: 0.45, green: 0.28, blue: 0.85),
                x: 0.28 + 0.05 * sin(time * 0.08),
                y: 0.48 + 0.05 * cos(time * 0.1),
                radius: 280
            )
            auroraOrb(
                color: AppColors.categoryBrandBright,
                x: 0.55 + 0.04 * sin(time * 0.07),
                y: 0.78 + 0.03 * cos(time * 0.12),
                radius: 220
            )
        }
    }

    private func auroraOrb(color: Color, x: Double, y: Double, radius: CGFloat) -> some View {
        GeometryReader { geo in
            RadialGradient(
                colors: [color.opacity(0.4), color.opacity(0.1), .clear],
                center: .center,
                startRadius: 6,
                endRadius: radius
            )
            .frame(width: radius * 2, height: radius * 2)
            .position(x: geo.size.width * x, y: geo.size.height * y)
            .blendMode(.plusLighter)
        }
    }
}

// MARK: - Ember (app-soft)

private struct AppEmberCanvas: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.02, blue: 0.03)

            RadialGradient(
                colors: [
                    Color(red: 0.55, green: 0.22, blue: 0.10).opacity(0.4 + 0.05 * sin(time * 0.2)),
                    Color(red: 0.28, green: 0.07, blue: 0.05).opacity(0.18),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 1.08),
                startRadius: 10,
                endRadius: 380
            )

            RadialGradient(
                colors: [AppColors.primary.opacity(0.12), .clear],
                center: UnitPoint(x: 0.72, y: 0.14),
                startRadius: 6,
                endRadius: 200
            )
        }
    }
}

// MARK: - Horizon (app-soft)

private struct AppHorizonCanvas: View {
    let time: TimeInterval

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
            let pulse = 0.35 + 0.1 * sin(time * 0.4)
            graphics.stroke(
                horizon,
                with: .linearGradient(
                    Gradient(colors: [
                        .clear,
                        AppColors.primary.opacity(pulse),
                        AppColors.categoryBrandBright.opacity(pulse * 0.8),
                        .clear
                    ]),
                    startPoint: CGPoint(x: 0, y: horizonY),
                    endPoint: CGPoint(x: size.width, y: horizonY)
                ),
                lineWidth: 1
            )

            for i in 0..<28 {
                let x = canvasHash(i, 1) * size.width
                let y = canvasHash(i, 2) * horizonY * 0.9
                let twinkle = 0.3 + 0.7 * (0.5 + 0.5 * sin(time * (0.5 + canvasHash(i, 3)) + Double(i)))
                let r = 0.5 + canvasHash(i, 4) * 1.2
                let rect = CGRect(x: x, y: y, width: r * 2, height: r * 2)
                graphics.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(0.15 + 0.55 * twinkle * canvasHash(i, 5)))
                )
            }
        }
    }
}

// MARK: - Prism (new)

/// Soft diagonal light shards — graphic without competing with cards.
/// Soft blur (not 28pt) keeps the wash cheap for an always-on canvas.
private struct PrismCanvas: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.035, blue: 0.08)

            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.14),
                    Color(red: 0.025, green: 0.03, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { graphics, size in
                let shards: [(CGFloat, CGFloat, Color)] = [
                    (0.15, 0.22, AppColors.primary.opacity(0.18)),
                    (0.55, 0.18, AppColors.categoryBrandBright.opacity(0.14)),
                    (0.35, 0.55, Color.indigo.opacity(0.12)),
                    (0.75, 0.62, AppColors.primary.opacity(0.1))
                ]
                for (index, shard) in shards.enumerated() {
                    let drift = CGFloat(sin(time * 0.18 + Double(index))) * 12
                    var path = Path()
                    let cx = size.width * shard.0
                    let cy = size.height * shard.1 + drift
                    path.move(to: CGPoint(x: cx - 40, y: cy - 120))
                    path.addLine(to: CGPoint(x: cx + 28, y: cy - 40))
                    path.addLine(to: CGPoint(x: cx + 8, y: cy + 140))
                    path.addLine(to: CGPoint(x: cx - 55, y: cy + 60))
                    path.closeSubpath()
                    graphics.fill(path, with: .color(shard.2))
                }
            }
            .blur(radius: 12)
        }
    }
}

// MARK: - Depth (new)

/// Concentric wells — quiet depth without particle cost.
private struct DepthCanvas: View {
    let time: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.42)
            let breathe = 1.0 + 0.04 * sin(time * 0.25)

            ZStack {
                Color(red: 0.02, green: 0.025, blue: 0.06)

                ForEach(0..<4, id: \.self) { ring in
                    let radius = (90 + CGFloat(ring) * 70) * breathe
                    Circle()
                        .stroke(
                            Color.white.opacity(0.035 - Double(ring) * 0.006),
                            lineWidth: 1.2
                        )
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                }

                RadialGradient(
                    colors: [
                        AppColors.primary.opacity(0.14),
                        Color.indigo.opacity(0.06),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: 4,
                    endRadius: 220
                )
            }
        }
    }
}

// MARK: - Hash

private func canvasHash(_ i: Int, _ salt: Double) -> Double {
    let x = sin(Double(i) * 127.139 + salt * 311.7) * 43758.5453123
    return x - floor(x)
}
