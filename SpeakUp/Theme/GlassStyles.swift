import SwiftUI

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let glass: Glass = {
            if let tint { return .regular.tint(tint) }
            return .regular.tint(AppColors.glassTintAccent)
        }()
        content
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
    }
}

// MARK: - View Extensions

extension View {
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// Material fallback when a non-card surface still wants a soft glass plate
    /// (text fields, compact chips that are not `GlassCard`).
    func glassBackground(cornerRadius: CGFloat = 16) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
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
                .lineLimit(2)
                .minimumScaleFactor(0.85)
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
