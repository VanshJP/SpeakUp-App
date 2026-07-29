import SwiftUI

struct GlassButton: View {
    let title: String
    var icon: String? = nil
    var iconPosition: IconPosition = .left
    var style: GlassButtonVariant = .primary
    var size: GlassButtonSize = .medium
    var isLoading: Bool = false
    var fullWidth: Bool = false
    let action: () -> Void
    
    enum IconPosition {
        case left, right
    }
    
    enum GlassButtonVariant {
        case primary
        case secondary
        case outline
        case ghost
        case danger
    }
    
    enum GlassButtonSize {
        case small
        case medium
        case large
        
        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 20
            case .large: return 28
            }
        }
        
        var verticalPadding: CGFloat {
            switch self {
            case .small: return 8
            case .medium: return 12
            case .large: return 16
            }
        }
        
        var font: Font {
            switch self {
            case .small: return .subheadline.weight(.medium)
            case .medium: return .body.weight(.semibold)
            case .large: return .headline.weight(.semibold)
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 17
            case .large: return 20
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                } else {
                    if let icon, iconPosition == .left {
                        Image(systemName: icon)
                            .font(.system(size: size.iconSize, weight: .semibold))
                    }
                    
                    Text(title)
                        .font(size.font)
                    
                    if let icon, iconPosition == .right {
                        Image(systemName: icon)
                            .font(.system(size: size.iconSize, weight: .semibold))
                    }
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background {
                backgroundView
            }
            .clipShape(Capsule())
        }
        .buttonStyle(GlassPressStyle())
        .disabled(isLoading)
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary:
            // Ink text on the light pill
            return Color(red: 0.07, green: 0.07, blue: 0.08)
        case .secondary:
            return .primary
        case .outline:
            return .white
        case .ghost:
            return .primary
        case .danger:
            return .white
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            // High-contrast light pill — the one loud element on the graphite canvas
            Capsule()
                .fill(Color.white.opacity(0.94))
        case .secondary:
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(AppColors.cardStroke, lineWidth: 0.5)
                }
        case .outline:
            Capsule()
                .fill(.clear)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }
        case .ghost:
            Capsule()
                .fill(Color.primary.opacity(0.05))
        case .danger:
            Capsule()
                .fill(AppColors.error.opacity(0.9))
        }
    }
}

// MARK: - Press Style

/// Shared pressed-state feedback for glass controls — a subtle scale + dim,
/// spring-animated. Keeps taps feeling physical without any layout shift.
struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(AppMotion.snap, value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Glass Buttons") {
    VStack(spacing: 20) {
        GlassButton(title: "Primary", icon: "mic.fill", style: .primary) {}
        GlassButton(title: "Secondary", icon: "play.fill", style: .secondary) {}
        GlassButton(title: "Outline", icon: "arrow.clockwise", style: .outline) {}
        GlassButton(title: "Ghost", style: .ghost) {}
        GlassButton(title: "Danger", icon: "trash", style: .danger) {}
        GlassButton(title: "Full Width", style: .primary, fullWidth: true) {}
    }
    .padding()
    .background(AppBackground())
}
