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
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return .primary
        case .outline:
            return .teal
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
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.teal.opacity(0.9), Color.teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        case .secondary:
            Capsule()
                .fill(.ultraThinMaterial)
        case .outline:
            Capsule()
                .fill(.clear)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.teal, lineWidth: 1.5)
                }
        case .ghost:
            Capsule()
                .fill(Color.primary.opacity(0.05))
        case .danger:
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(Color.red.opacity(0.9))
                }
        }
    }
}

// MARK: - Icon Button

struct GlassIconButton: View {
    let icon: String
    var size: CGFloat = 44
    var tint: Color? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(tint ?? .primary)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            if let tint {
                                Circle()
                                    .fill(tint.opacity(0.1))
                            }
                        }
                }
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
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
        
        HStack(spacing: 16) {
            GlassIconButton(icon: "mic.fill") {}
            GlassIconButton(icon: "video.fill", tint: .teal) {}
            GlassIconButton(icon: "arrow.clockwise") {}
        }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
