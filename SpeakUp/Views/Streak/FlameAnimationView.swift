import SwiftUI

/// Opal-style candle flame: a clean teardrop silhouette with an inner
/// bright core, sitting inside a large warm halo. Animated with subtle
/// sin-driven scale and sway from a `TimelineView` so the whole thing
/// "breathes" without ever looking jittery.
struct FlameAnimationView: View {
    var size: CGFloat = 220
    var isLit: Bool = true

    var body: some View {
        if isLit {
            litFlame
        } else {
            extinguishedFlame
        }
    }

    // MARK: - Lit flame

    private var litFlame: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            // Slow primary breath
            let breath = sin(t * 1.6)
            // Higher-frequency micro-flicker stacked on top
            let flicker = sin(t * 4.7) * 0.4 + sin(t * 9.3) * 0.15
            // Independent sway phase
            let sway = sin(t * 1.25)
            // Inner flame on a different phase so it doesn't move in lock-step
            let innerBreath = sin(t * 2.4 + 0.7)
            let innerFlicker = sin(t * 6.1 + 1.2)

            ZStack {
                halo(t: t)

                // Outer flame
                FlameTeardropShape()
                    .fill(outerGradient)
                    .overlay {
                        // Thin darker rim around the bottom for contact shadow
                        FlameTeardropShape()
                            .stroke(
                                LinearGradient(
                                    colors: [.clear, .clear, Color(red: 0.4, green: 0.05, blue: 0.05).opacity(0.5)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.2
                            )
                    }
                    .frame(width: size * 0.55, height: size * 0.85)
                    .scaleEffect(
                        x: 1.0 + breath * 0.025,
                        y: 1.0 + breath * 0.06 + flicker * 0.018,
                        anchor: .bottom
                    )
                    .rotationEffect(.degrees(sway * 1.4), anchor: .bottom)
                    .shadow(color: Color(red: 1.0, green: 0.4, blue: 0.05).opacity(0.55), radius: 22, y: -2)
                    .blur(radius: 0.4)

                // Inner core flame
                FlameTeardropShape()
                    .fill(innerGradient)
                    .frame(width: size * 0.26, height: size * 0.42)
                    .offset(y: size * 0.10)
                    .scaleEffect(
                        x: 1.0 + innerBreath * 0.04,
                        y: 1.0 + innerBreath * 0.07 + innerFlicker * 0.03,
                        anchor: .bottom
                    )
                    .rotationEffect(.degrees(sway * -2.2), anchor: .bottom)
                    .blur(radius: 0.6)
                    .shadow(color: Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.85), radius: 8)

                // A faint dark base touch — sells the "sitting on something" feel
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.05, green: 0.06, blue: 0.18).opacity(0.9), .clear],
                            center: .center,
                            startRadius: 1,
                            endRadius: size * 0.15
                        )
                    )
                    .frame(width: size * 0.42, height: size * 0.10)
                    .offset(y: size * 0.42)
                    .blur(radius: 4)
            }
            .frame(width: size, height: size * 1.05)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Extinguished flame

    /// Static, desaturated rendering used when the streak is 0. No halo,
    /// no breath/flicker, cool gray gradient — reads as a snuffed candle.
    private var extinguishedFlame: some View {
        ZStack {
            // Outer flame silhouette in cool gray
            FlameTeardropShape()
                .fill(extinguishedOuterGradient)
                .frame(width: size * 0.55, height: size * 0.85)

            // Inner core in a slightly lighter gray to keep the shape readable
            FlameTeardropShape()
                .fill(extinguishedInnerGradient)
                .frame(width: size * 0.26, height: size * 0.42)
                .offset(y: size * 0.10)
                .blur(radius: 0.6)

            // Faint dark base touch — same as lit version, sells the candle base
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.05, green: 0.06, blue: 0.18).opacity(0.9), .clear],
                        center: .center,
                        startRadius: 1,
                        endRadius: size * 0.15
                    )
                )
                .frame(width: size * 0.42, height: size * 0.10)
                .offset(y: size * 0.42)
                .blur(radius: 4)
        }
        .frame(width: size, height: size * 1.05)
        .accessibilityHidden(true)
    }

    // MARK: - Halo

    private func halo(t: Double) -> some View {
        let pulse = 0.88 + 0.12 * sin(t * 1.3)
        return ZStack {
            // Wide soft brown-orange halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.45, blue: 0.12).opacity(0.55 * pulse),
                            Color(red: 0.85, green: 0.30, blue: 0.05).opacity(0.28 * pulse),
                            Color(red: 0.55, green: 0.15, blue: 0.02).opacity(0.10 * pulse),
                            .clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: size * 1.6
                    )
                )
                .frame(width: size * 3.2, height: size * 3.2)
                .blur(radius: 28)

            // Tighter warm core glow right around the flame
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.55, blue: 0.18).opacity(0.55 * pulse),
                            Color(red: 1.0, green: 0.35, blue: 0.05).opacity(0.20 * pulse),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size * 1.6, height: size * 1.6)
                .blur(radius: 12)
                .scaleEffect(pulse)
        }
    }

    // MARK: - Gradients

    private var outerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.78, blue: 0.32),   // tip — warm yellow-orange
                Color(red: 1.0, green: 0.55, blue: 0.15),   // upper body — orange
                Color(red: 0.95, green: 0.30, blue: 0.05),  // bulge — deep orange-red
                Color(red: 0.55, green: 0.10, blue: 0.04)   // base — dim red
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var innerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.97, blue: 0.78),   // tip — pale yellow / near white
                Color(red: 1.0, green: 0.88, blue: 0.40),   // body — bright yellow
                Color(red: 1.0, green: 0.65, blue: 0.18)    // base — yellow-orange
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var extinguishedOuterGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.55, green: 0.58, blue: 0.64),  // tip — light cool gray
                Color(red: 0.42, green: 0.45, blue: 0.52),  // upper body
                Color(red: 0.28, green: 0.31, blue: 0.38),  // bulge — slate
                Color(red: 0.16, green: 0.18, blue: 0.24)   // base — near charcoal
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var extinguishedInnerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.70, green: 0.72, blue: 0.78),  // tip — pale gray
                Color(red: 0.52, green: 0.55, blue: 0.62),  // body
                Color(red: 0.36, green: 0.39, blue: 0.46)   // base
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Flame Shape

/// Classic candle-flame teardrop: pointy at the top, rounded at the
/// bottom, widest about 2/3 of the way down. Built from four cubic
/// curves — two shoulder curves up to the tip, two bottom-quarter
/// curves approximating a circle (Bezier constant k ≈ 0.5523).
struct FlameTeardropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let radius = w / 2
        let widestY = h - radius
        let k: CGFloat = 0.5522847498
        let kr = k * radius

        let tip = CGPoint(x: cx, y: rect.minY)
        let rightWidest = CGPoint(x: rect.maxX, y: widestY)
        let bottomCenter = CGPoint(x: cx, y: rect.maxY)
        let leftWidest = CGPoint(x: rect.minX, y: widestY)

        path.move(to: tip)

        // Right shoulder — tip down to the widest point on the right.
        path.addCurve(
            to: rightWidest,
            control1: CGPoint(x: cx + w * 0.18, y: h * 0.12),
            control2: CGPoint(x: rect.maxX, y: h * 0.42)
        )

        // Bottom-right quarter circle — rightWidest → bottomCenter.
        path.addCurve(
            to: bottomCenter,
            control1: CGPoint(x: rect.maxX, y: widestY + kr),
            control2: CGPoint(x: cx + kr, y: rect.maxY)
        )

        // Bottom-left quarter circle — bottomCenter → leftWidest.
        path.addCurve(
            to: leftWidest,
            control1: CGPoint(x: cx - kr, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: widestY + kr)
        )

        // Left shoulder — leftWidest → tip.
        path.addCurve(
            to: tip,
            control1: CGPoint(x: rect.minX, y: h * 0.42),
            control2: CGPoint(x: cx - w * 0.18, y: h * 0.12)
        )

        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        FlameAnimationView()
    }
}
