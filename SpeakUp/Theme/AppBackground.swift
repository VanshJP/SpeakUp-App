import SwiftUI

// MARK: - App Background

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
    func appBackground(_ style: AppBackground.Style = .primary) -> some View {
        self.background { AppBackground(style: style) }
    }
}

// MARK: - Preview

#Preview {
    AppBackground()
}
