import SwiftUI

/// The visual chrome for a glass capsule control — shared by `GlassButton` and
/// by card labels that sit inside a `NavigationLink` (where nesting a `Button`
/// is illegal). One shape language for every primary / secondary / outline /
/// danger CTA in the app.
struct GlassButtonLabel: View {
    let title: String
    var icon: String? = nil
    var iconPosition: GlassButton.IconPosition = .left
    var style: GlassButton.GlassButtonVariant = .primary
    var size: GlassButton.GlassButtonSize = .medium
    var isLoading: Bool = false
    var fullWidth: Bool = false

    var body: some View {
        labelContent
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(minHeight: AppLayout.minHitTarget)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .modifier(GlassButtonChrome(style: style))
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
    }

    @ViewBuilder
    private var labelContent: some View {
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
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return Color(red: 0.07, green: 0.07, blue: 0.08)
        case .secondary:
            return .primary
        case .outline, .danger:
            return .white
        }
    }

    private var shadowColor: Color {
        switch style {
        case .primary: return .black.opacity(0.28)
        case .secondary, .outline, .danger: return .clear
        }
    }

    private var shadowRadius: CGFloat {
        style == .primary ? 10 : 0
    }

    private var shadowYOffset: CGFloat {
        style == .primary ? 4 : 0
    }
}

/// Applies the capsule chrome after padding so Liquid Glass sits on the final
/// shape. Primary stays an opaque white fill — the one loud CTA on a page.
private struct GlassButtonChrome: ViewModifier {
    let style: GlassButton.GlassButtonVariant

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .primary:
            content
                .background {
                    Capsule().fill(Color.white.opacity(0.94))
                }
                .clipShape(Capsule())
        case .secondary:
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        case .outline:
            content
                .background {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }
        case .danger:
            content
                .background {
                    Capsule().fill(AppColors.error.opacity(0.9))
                }
                .clipShape(Capsule())
        }
    }
}

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
            GlassButtonLabel(
                title: title,
                icon: icon,
                iconPosition: iconPosition,
                style: style,
                size: size,
                isLoading: isLoading,
                fullWidth: fullWidth
            )
        }
        .buttonStyle(GlassPressStyle())
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "Loading" : "")
    }
}

// MARK: - Press Style

/// Shared pressed-state feedback for glass controls — a subtle scale + dim,
/// spring-animated. Keeps taps feeling physical without any layout shift.
///
/// Press scale is exactly `0.96` (anything below ~0.95 feels exaggerated).
/// Under Reduce Motion the scale is skipped so state still dims without a
/// transform the user asked not to see.
struct GlassPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(reduceMotion ? nil : AppMotion.snap, value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Glass Buttons") {
    VStack(spacing: 20) {
        GlassButton(title: "Primary", icon: "mic.fill", style: .primary) {}
        GlassButton(title: "Secondary", icon: "play.fill", style: .secondary) {}
        GlassButton(title: "Outline", icon: "arrow.clockwise", style: .outline) {}
        GlassButton(title: "Danger", icon: "trash", style: .danger) {}
        GlassButton(title: "Full Width", style: .primary, fullWidth: true) {}
        GlassButtonLabel(title: "Label only", icon: "play.fill", style: .primary, fullWidth: true)
    }
    .padding()
    .background(AppBackground())
}
