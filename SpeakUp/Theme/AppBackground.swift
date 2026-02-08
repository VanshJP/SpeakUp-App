import SwiftUI

// MARK: - App Background

/// A rich, layered gradient background that replaces plain black.
/// Deep navy base with ambient teal, indigo, and cyan orbs creates
/// a premium feel and makes glass-morphism cards pop.
struct AppBackground: View {
    var style: Style = .primary

    enum Style {
        case primary    // Default: deep navy with teal + indigo orbs
        case recording  // Darker with stronger teal accent for focus
        case subtle     // Lighter variant for sheets / detail views
    }

    var body: some View {
        ZStack {
            // 1. Deep dark base
            Color(red: 0.035, green: 0.04, blue: 0.09)

            // 2. Primary gradient wash
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 3. Teal ambient orb  (top-right area)
            RadialGradient(
                colors: [tealOrbColor, .clear],
                center: UnitPoint(x: 0.85, y: 0.08),
                startRadius: 20,
                endRadius: 280
            )

            // 4. Indigo ambient orb  (bottom-left area)
            RadialGradient(
                colors: [indigoOrbColor, .clear],
                center: UnitPoint(x: 0.12, y: 0.88),
                startRadius: 10,
                endRadius: 240
            )

            // 5. Soft cyan glow  (center-ish)
            RadialGradient(
                colors: [cyanGlowColor, .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 10,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Style-dependent colors

    private var gradientColors: [Color] {
        switch style {
        case .primary:
            return [
                Color(red: 0.05, green: 0.07, blue: 0.16),
                Color(red: 0.03, green: 0.045, blue: 0.10),
                Color(red: 0.035, green: 0.035, blue: 0.08),
            ]
        case .recording:
            return [
                Color(red: 0.02, green: 0.04, blue: 0.10),
                Color(red: 0.01, green: 0.02, blue: 0.06),
                Color(red: 0.02, green: 0.03, blue: 0.07),
            ]
        case .subtle:
            return [
                Color(red: 0.045, green: 0.06, blue: 0.14),
                Color(red: 0.035, green: 0.05, blue: 0.11),
                Color(red: 0.03, green: 0.04, blue: 0.09),
            ]
        }
    }

    private var tealOrbColor: Color {
        switch style {
        case .primary:   return Color.teal.opacity(0.12)
        case .recording: return Color.teal.opacity(0.18)
        case .subtle:    return Color.teal.opacity(0.10)
        }
    }

    private var indigoOrbColor: Color {
        switch style {
        case .primary:   return Color.indigo.opacity(0.09)
        case .recording: return Color.indigo.opacity(0.06)
        case .subtle:    return Color.indigo.opacity(0.08)
        }
    }

    private var cyanGlowColor: Color {
        switch style {
        case .primary:   return Color.cyan.opacity(0.04)
        case .recording: return Color.cyan.opacity(0.06)
        case .subtle:    return Color.cyan.opacity(0.03)
        }
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
