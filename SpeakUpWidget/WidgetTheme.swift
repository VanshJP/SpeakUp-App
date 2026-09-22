import SwiftUI
import WidgetKit

// MARK: - Palette

/// Big Talk's widget palette. The widget target cannot import app types, so the
/// brand values are duplicated here - keep in sync with `AppColors`
/// (primary #0D8488, categoryBrandBright #2BA8A8, warning #F5A93C,
/// scoreHigh #38CC80, scoreGood #F5C542, scoreMid #FF9036, scoreLow #F5544A).
///
/// Text tones are deliberately explicit rather than `.primary` / `.secondary`:
/// in full color the widget owns a dark canvas, and the fixed white tiers also
/// map to distinct luminance groups when the system renders `.vibrant`.
enum WidgetPalette {

    // MARK: Brand

    /// Muted teal. Mirrors `AppColors.primary`.
    static let brand = Color(red: 0.051, green: 0.518, blue: 0.533)

    /// Brighter teal companion - the tone that survives on the navy canvas.
    /// Mirrors `AppColors.categoryBrandBright`.
    static let brandBright = Color(red: 0.169, green: 0.659, blue: 0.659)

    /// Warm amber for streak heat. Mirrors `AppColors.warning`.
    static let ember = Color(red: 0.961, green: 0.663, blue: 0.235)

    // MARK: Canvas

    /// Base navy - where the app's background settles.
    static let canvasBase = Color(red: 0.051, green: 0.071, blue: 0.165)

    /// Lifted navy for the top of the canvas gradient.
    static let canvasLift = Color(red: 0.086, green: 0.122, blue: 0.251)

    // MARK: Text

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.64)
    static let textTertiary = Color.white.opacity(0.42)

    // MARK: Surfaces

    /// Recessed track behind any meter or ring. Mirrors `AppColors.meterTrack`,
    /// lifted slightly because widgets are viewed small and at a glance.
    static let meterTrack = Color.white.opacity(0.11)

    // MARK: Score ramp

    /// Score ramp mirroring the app's `AppColors.scoreColor(for:)`.
    static func score(for value: Int) -> Color {
        switch value {
        case 80...100: return Color(red: 0.220, green: 0.800, blue: 0.502)  // #38CC80
        case 60..<80: return Color(red: 0.961, green: 0.773, blue: 0.259)   // #F5C542
        case 40..<60: return Color(red: 1.000, green: 0.565, blue: 0.212)   // #FF9036
        default: return Color(red: 0.961, green: 0.329, blue: 0.290)        // #F5544A
        }
    }

    /// Direction tone for a week-over-week delta. Neutral inside the noise band
    /// so a one-point wobble does not read as a trend.
    static func trend(for delta: Int) -> Color {
        if delta > 1 { return Color(red: 0.220, green: 0.800, blue: 0.502) }
        if delta < -1 { return Color(red: 0.961, green: 0.329, blue: 0.290) }
        return textSecondary
    }
}

// MARK: - Type scale

/// One scale for every widget. Rounded carries chrome and data so numerals
/// read as numerals; the default face carries prose (prompts, story titles)
/// so user content reads as content.
enum WidgetType {
    static let eyebrow = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let caption = Font.system(size: 10, weight: .medium, design: .rounded)
    static let label = Font.system(size: 11, weight: .medium, design: .rounded)
    static let value = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let numeralMedium = Font.system(size: 19, weight: .bold, design: .rounded)
    static let numeralLarge = Font.system(size: 34, weight: .bold, design: .rounded)

    /// Prose. Prompts and story titles.
    static let body = Font.system(size: 15, weight: .medium)
}

// MARK: - Canvas

/// The widget's own background.
///
/// Full color paints Big Talk's navy gradient plus a soft brand glow so the
/// widget reads with depth instead of as a flat slab. Accented and vibrant
/// paint nothing: the system owns the tint there, and anything we draw would
/// flatten into a gray rectangle. StandBy strips the background itself, which
/// is why `containerBackgroundRemovable` stays at its default.
private struct WidgetCanvas: View {
    let renderingMode: WidgetRenderingMode

    var body: some View {
        if renderingMode == .fullColor {
            ZStack {
                LinearGradient(
                    colors: [WidgetPalette.canvasLift, WidgetPalette.canvasBase],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Two stops so the glow falls off the way light does instead
                // of ending on a visible ring.
                RadialGradient(
                    colors: [
                        WidgetPalette.brandBright.opacity(0.26),
                        WidgetPalette.brand.opacity(0.12),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 170
                )
            }
        } else {
            Color.clear
        }
    }
}

private struct WidgetCanvasModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetFamily) private var family

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAccessory {
            // Lock Screen and Smart Stack draw their own backing; ours would
            // only fight the system's vibrancy.
            content.containerBackground(Color.clear, for: .widget)
        } else {
            content
                // Our full-color canvas is always dark, so resolve system tones
                // against dark there. Other modes stay the system's to decide -
                // writing the inherited value back is a no-op.
                .environment(\.colorScheme, renderingMode == .fullColor ? .dark : systemColorScheme)
                .containerBackground(for: .widget) {
                    WidgetCanvas(renderingMode: renderingMode)
                }
        }
    }
}

extension View {
    /// Big Talk's widget container background. Apply once, on the view handed
    /// to the widget's configuration closure.
    func bigTalkCanvas() -> some View {
        modifier(WidgetCanvasModifier())
    }
}
