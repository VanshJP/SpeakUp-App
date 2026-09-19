import SwiftUI
import WidgetKit

// MARK: - Header

/// Brand eyebrow shared by every system-family widget: one icon, one short
/// uppercase title, an optional trailing detail. Marked accentable so tinted
/// Home Screens put the header in the accent group and the content below it in
/// the default group, which is what gives a tinted widget any hierarchy at all.
struct WidgetHeader<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))

            Text(title)
                .font(WidgetType.eyebrow)
                .textCase(.uppercase)
                .kerning(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            trailing
        }
        .foregroundStyle(WidgetPalette.brandBright)
        .widgetAccentable()
    }
}

extension WidgetHeader where Trailing == EmptyView {
    init(icon: String, title: String) {
        self.init(icon: icon, title: title) { EmptyView() }
    }
}

// MARK: - Ring

/// Progress ring with a rounded cap and a slight angular ramp, so a partly
/// filled ring reads as motion rather than as a flat arc.
struct WidgetRing: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(WidgetPalette.meterTrack, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
    }

    private var clamped: Double {
        min(max(progress, 0), 1)
    }
}

// MARK: - Meter

/// Capsule progress bar. Replaces `ProgressView` + `scaleEffect`, which
/// stretched the bar's rounded caps into ellipses.
struct WidgetMeter: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(WidgetPalette.meterTrack)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.7), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    // Never narrower than its own cap, so 1-of-7 still reads as
                    // a dot rather than disappearing.
                    .frame(width: fillWidth(in: geometry.size.width))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }

    private var clamped: Double {
        min(max(progress, 0), 1)
    }

    private func fillWidth(in available: CGFloat) -> CGFloat {
        guard clamped > 0 else { return 0 }
        return max(available * CGFloat(clamped), height)
    }
}

// MARK: - Chip

/// Small tinted pill: a category, a CTA, a delta.
struct WidgetChip: View {
    let text: String
    var icon: String?
    var tint: Color = WidgetPalette.brandBright

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }

            Text(text)
                .font(WidgetType.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.16), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.24), lineWidth: 0.5)
        }
    }
}

// MARK: - Metric

/// Label over value. Every numeral in the app's widgets is one of these, so
/// baselines line up across a row without hand-tuned spacers.
struct WidgetMetric: View {
    let label: String
    let value: String
    var tint: Color = WidgetPalette.textPrimary
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label)
                .font(WidgetType.caption)
                .textCase(.uppercase)
                .kerning(0.3)
                .foregroundStyle(WidgetPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(WidgetType.numeralMedium)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(
            maxWidth: .infinity,
            alignment: Alignment(horizontal: alignment, vertical: .center)
        )
    }
}

// MARK: - Glyph orb

/// Icon inside a soft tinted halo. The app's primary actions all read this way,
/// and it gives a small widget a focal point that a bare glyph does not.
struct WidgetGlyphOrb: View {
    let systemName: String
    var tint: Color = WidgetPalette.brandBright
    var diameter: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.32), tint.opacity(0.08)],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.62
                    )
                )

            Circle()
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)

            Image(systemName: systemName)
                .font(.system(size: diameter * 0.42, weight: .medium))
                .foregroundStyle(tint)
                .widgetAccentable()
        }
        .frame(width: diameter, height: diameter)
    }
}
