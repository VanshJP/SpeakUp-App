import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat
    var tint: Color?
    var padding: CGFloat
    var accentBorder: Color?
    var elevated: Bool

    init(
        cornerRadius: CGFloat = 18,
        tint: Color? = nil,
        // Tightened from 16. Every card in the app inherits this, so it is the
        // single highest-leverage control over how large the app feels.
        padding: CGFloat = 13,
        accentBorder: Color? = nil,
        elevated: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.padding = padding
        self.accentBorder = accentBorder
        self.elevated = elevated
    }

    var body: some View {
        content
            .padding(padding)
            .glassEffect(resolvedGlass, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                if let accentBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(accentBorder.opacity(0.35), lineWidth: 1)
                }
            }
            .shadow(
                color: .black.opacity(elevated ? 0.35 : 0.18),
                radius: elevated ? 18 : 10,
                y: elevated ? 9 : 5
            )
    }

    private var resolvedGlass: Glass {
        if let tint {
            return .regular.tint(tint)
        }
        return .regular
    }
}

// MARK: - Featured Glass Card (for hero/prominent content)

struct FeaturedGlassCard<Content: View>: View {
    let content: Content
    var gradientColors: [Color]
    var cornerRadius: CGFloat
    var padding: CGFloat

    init(
        gradientColors: [Color] = [AppColors.primary.opacity(0.10), Color.white.opacity(0.02)],
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.gradientColors = gradientColors
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .glassEffect(.regular.tint(gradientColors.first ?? AppColors.primary), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.cardStroke, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.3), radius: 18, y: 9)
    }
}

// MARK: - Tick Meter

/// Discrete segmented meter — a row of thin ticks filled up to `fraction`.
/// Reads as measured data rather than a decorative progress bar.
struct TickMeter: View {
    let fraction: Double
    let color: Color
    var tickCount: Int = 36

    var body: some View {
        Canvas { context, size in
            let gap = size.width / CGFloat(tickCount)
            let tickWidth = max(1.5, gap * 0.45)
            let filled = Int((fraction * Double(tickCount)).rounded())

            for i in 0..<tickCount {
                let x = CGFloat(i) * gap + (gap - tickWidth) / 2
                let rect = CGRect(x: x, y: 0, width: tickWidth, height: size.height)
                let path = Path(roundedRect: rect, cornerRadius: tickWidth / 2)
                context.fill(path, with: .color(i < filled ? color : .white.opacity(0.12)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Empty State Card

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil
    
    var body: some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                Circle()
                                    .stroke(AppColors.cardStroke, lineWidth: 0.5)
                            }
                    }

                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let buttonTitle, let buttonAction {
                    GlassButton(title: buttonTitle, style: .primary, action: buttonAction)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Inline Empty State

/// Empty state for a slot that already sits inside a card — a chart well, a
/// section body. `EmptyStateCard` would nest a `GlassCard` in a `GlassCard`.
///
/// Exists because four chart fallbacks were each a bare `Text` in a
/// `minHeight: 100` frame: technically an empty state, visibly an oversight
/// next to the designed ones elsewhere in the app.
struct EmptyStateInline: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Glass Cards") {
    ScrollView {
        VStack(spacing: 20) {
            GlassCard { Text("Standard card").foregroundStyle(.white) }
            FeaturedGlassCard { Text("Featured card").foregroundStyle(.white) }
            EmptyStateCard(
                icon: "mic.slash",
                title: "No Recordings Yet",
                message: "Start your first practice session to see your progress here.",
                buttonTitle: "Start Recording",
                buttonAction: {}
            )
        }
        .padding()
    }
    .background(AppBackground())
}
