import SwiftUI

// MARK: - App Background

/// App-wide canvas. Reads `appCanvas` from the environment so Settings →
/// Appearance can re-skin every tab without each screen owning a picker.
/// Style (`.primary` / `.recording` / `.subtle`) still nudges Classic/Midnight
/// washes; every other look keeps one mood.
struct AppBackground: View {
    var style: Style = .primary
    /// Unused — every look is a still. Kept so tab call sites do not churn.
    var animated: Bool = true

    @Environment(\.appCanvas) private var canvas

    enum Style {
        case primary    // Default: deep navy with soft teal light
        case recording  // Darker with stronger teal accent for focus
        case subtle     // Lighter variant for sheets / detail views
    }

    var body: some View {
        AppCanvasView(canvas: canvas, style: style)
            .ignoresSafeArea()
    }
}

// MARK: - View Extension for easy application

extension View {
    /// Applies the rich gradient background behind the view.
    func appBackground(_ style: AppBackground.Style = .primary) -> some View {
        self.background { AppBackground(style: style) }
    }
}

// MARK: - Preview

#Preview {
    AppBackground()
}
