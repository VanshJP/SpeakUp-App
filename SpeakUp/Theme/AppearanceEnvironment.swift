import SwiftUI

// MARK: - Glass Appearance

/// How untinted Liquid Glass reads on the navy canvas.
///
/// Light is the post-brighten default (soft white lift). Dark drops the lift
/// and softens the rim so cards sink into the canvas — the look before the
/// brighten pass, available as a user preference.
///
/// Raw values are the SwiftData payload; do not reorder existing cases.
enum GlassAppearance: Int, Codable, CaseIterable, Identifiable {
    case light = 0
    case dark = 1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var subtitle: String {
        switch self {
        case .light: return "Brighter glass plates over the navy canvas"
        case .dark: return "Deeper glass that blends into the background"
        }
    }

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// Soft white lift for `.regular.tint(...)` on untinted surfaces.
    var glassTint: Color {
        switch self {
        case .light: return Color.white.opacity(0.08)
        case .dark: return Color.white.opacity(0.02)
        }
    }

    /// Top-edge rim gradient stops (top → mid → bottom opacity).
    var rimOpacities: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .light: return (0.28, 0.08, 0.03)
        case .dark: return (0.12, 0.04, 0.015)
        }
    }
}

// MARK: - Environment Keys

private struct GlassAppearanceKey: EnvironmentKey {
    static let defaultValue: GlassAppearance = .light
}

private struct AppCanvasKey: EnvironmentKey {
    static let defaultValue: AppCanvas = .classic
}

extension EnvironmentValues {
    var glassAppearance: GlassAppearance {
        get { self[GlassAppearanceKey.self] }
        set { self[GlassAppearanceKey.self] = newValue }
    }

    var appCanvas: AppCanvas {
        get { self[AppCanvasKey.self] }
        set { self[AppCanvasKey.self] = newValue }
    }
}

// MARK: - Glass rim helper

extension View {
    /// Shared top-edge rim light that respects the user's glass appearance.
    func glassRimStroke(cornerRadius: CGFloat, appearance: GlassAppearance) -> some View {
        let rim = appearance.rimOpacities
        return self.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(rim.0),
                            Color.white.opacity(rim.1),
                            Color.white.opacity(rim.2)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
    }
}
