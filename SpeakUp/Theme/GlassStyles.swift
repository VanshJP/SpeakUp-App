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

struct GlassSectionHeader<Accessory: View>: View {
    let title: String
    let icon: String?
    var accessory: Accessory

    init(_ title: String, icon: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.icon = icon
        self.accessory = accessory()
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
            accessory
        }
        .padding(.horizontal, 4)
    }
}

extension GlassSectionHeader where Accessory == EmptyView {
    init(_ title: String, icon: String? = nil) {
        self.init(title, icon: icon) { EmptyView() }
    }
}

// MARK: - Glass Card Title

/// Card-level title row — the quieter sibling of `GlassSectionHeader`: same
/// anatomy (icon, name, trailing accessory), one register down in size.
/// Chart cards and multi-card sections use it so card headers stop being
/// hand-rolled `Label`s with drifting fonts, while section headers keep the
/// headline weight above them.
struct GlassCardTitle<Accessory: View>: View {
    let title: String
    let icon: String?
    var accessory: Accessory

    init(_ title: String, icon: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.icon = icon
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
            accessory
        }
    }
}

extension GlassCardTitle where Accessory == EmptyView {
    init(_ title: String, icon: String? = nil) {
        self.init(title, icon: icon) { EmptyView() }
    }
}
