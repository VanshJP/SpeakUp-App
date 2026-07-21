import SwiftUI

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppColors.surfaceLift)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint ?? Color.clear)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppColors.cardStroke, lineWidth: 0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}

// MARK: - View Extensions

extension View {
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
    
    func glassBackground(cornerRadius: CGFloat = 16) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Glass Section Header

struct GlassSectionHeader: View {
    let title: String
    let icon: String?
    
    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}
