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

    /// One-line caption under the Light / Dark preview. The long `subtitle`
    /// is the accessibility string; this is what the picker shows.
    var previewCaption: String {
        switch self {
        case .light: return "Brighter plates"
        case .dark: return "Deeper plates"
        }
    }

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// Soft white lift for `.regular.tint(...)` on untinted surfaces. The only
    /// knob this setting has left now that cards draw no rim of their own.
    var glassTint: Color { Color.white.opacity(tintLift) }

    /// How much the plate lifts off the canvas. Dark lifts less so cards sink.
    var tintLift: Double {
        switch self {
        case .light: return 0.08
        case .dark: return 0.02
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
