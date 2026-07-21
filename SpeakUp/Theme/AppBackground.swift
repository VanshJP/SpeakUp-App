import SwiftUI

// MARK: - App Background

/// Neutral graphite canvas. A near-black base with a soft vertical lift and a
/// single faint brand bloom at the top — color lives in the data (rings,
/// charts, scores), never in the chrome. Cards float on top as soft elevated
/// surfaces.
struct AppBackground: View {
    var style: Style = .primary

    enum Style {
        case primary    // Default: neutral graphite
        case recording  // Darker, slightly stronger brand bloom for focus
        case subtle     // Slightly lifted variant for sheets / detail views
    }

    var body: some View {
        ZStack {
            baseColor

            // Soft vertical lift — top of screen reads slightly lighter,
            // giving cards a light source without visible color.
            LinearGradient(
                colors: [Color.white.opacity(0.035), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.45)
            )

            // Single faint brand bloom — a whisper of teal, not an orb field.
            RadialGradient(
                colors: [AppColors.primary.opacity(bloomOpacity), .clear],
                center: UnitPoint(x: 0.5, y: -0.15),
                startRadius: 40,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Style-dependent values

    private var baseColor: Color {
        switch style {
        case .primary:   return Color(red: 0.051, green: 0.051, blue: 0.059) // #0D0D0F
        case .recording: return Color(red: 0.031, green: 0.031, blue: 0.039) // #08080A
        case .subtle:    return Color(red: 0.067, green: 0.067, blue: 0.078) // #111114
        }
    }

    private var bloomOpacity: Double {
        switch style {
        case .primary:   return 0.05
        case .recording: return 0.08
        case .subtle:    return 0.04
        }
    }
}

// MARK: - View Extension for easy application

extension View {
    /// Applies the neutral graphite background behind the view.
    func appBackground(_ style: AppBackground.Style = .primary) -> some View {
        self.background { AppBackground(style: style) }
    }
}

// MARK: - Preview

#Preview {
    AppBackground()
}
